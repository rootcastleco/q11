<# Temporary single-Q11 DHCP on the explicitly named direct Ethernet interface.
   PacketInformation checks receiving interface; Q11 vendor-class and one MAC only.
   ActiveStore address/firewall changes are restored in finally. No forwarding,
   DNS/router/update options or client credentials. Requires Administrator.
#>
[CmdletBinding()]
param(
    [string]$InterfaceAlias='Ethernet',
    [ValidateRange(30,600)][int]$DurationSec=180,
    [string]$LogDirectory=(Join-Path $PSScriptRoot '..\..\logs'),
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'dhcp.psm1') -Force
$adapter=Get-NetAdapter -Name $InterfaceAlias
if (-not $adapter.HardwareInterface -or $adapter.Status -ne 'Up') { throw 'A connected physical Ethernet adapter is required.' }
$interface=Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
if ([string]$interface.Dhcp -ne 'Enabled' -or [string]$interface.Forwarding -eq 'Enabled') { throw 'Requires DHCP-enabled, non-forwarding direct interface.' }
$addresses=@(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4)
if (@($addresses | Where-Object { $_.IPAddress -notlike '169.254.*' }).Count) { throw 'Direct interface already has a non-link-local address; refusing to replace it.' }
if (@(Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).Count) { throw 'Direct interface has a gateway.' }
if (@(Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -like '192.168.73.*' }).Count) { throw 'Lab subnet already routed.' }
$server='192.168.73.1'; $client='192.168.73.2'; $broadcast='192.168.73.255'
Write-Output "Temporary DHCP on $InterfaceAlias (#$($adapter.ifIndex)); server=$server, one Q11=$client, $DurationSec seconds."
if ($DryRun) { Write-Output 'DRY RUN: no network settings/sockets changed.'; return }
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator PowerShell required.' }
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$tag=Get-Date -Format 'yyyyMMdd_HHmmss'
$log=Join-Path ([IO.Path]::GetFullPath($LogDirectory)) "experiment_${tag}_dhcp.json"
if (Test-Path -LiteralPath $log) { throw 'Log exists.' }
$commit=& git -C (Join-Path $PSScriptRoot '..\..') rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine git commit.' }
$record=[ordered]@{timestamp=(Get-Date -Format o);git_commit=$commit;tool_version='1.0';operation='isolated-dhcp';
    port=$null;baud=$null;interface_index=$adapter.ifIndex;interface_alias=$InterfaceAlias;server=$server;client=$client;
    result='running';exit_code=$null;stage='validated';offers=0;acks=0;received=0;ignored=0;restored=$false}
function Save-Q11DhcpRecord { $record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $log -Encoding utf8 }
$socket=$null; $addressAdded=$false; $dhcpChanged=$false; $ruleAdded=$false; $resultCode=0; $selectedMac=$null
$rule="Q11-Lab-DHCP-$tag"
Save-Q11DhcpRecord
try {
    Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Dhcp Disabled -PolicyStore ActiveStore
    $dhcpChanged=$true
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $server -PrefixLength 24 -PolicyStore ActiveStore | Out-Null
    $addressAdded=$true
    New-NetFirewallRule -Name $rule -DisplayName $rule -Direction Inbound -Action Allow -Protocol UDP -LocalPort 67 -RemotePort 68 -InterfaceAlias $InterfaceAlias -Profile Any | Out-Null
    $ruleAdded=$true
    $socket=[Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
    $socket.ExclusiveAddressUse=$false
    $socket.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket,[Net.Sockets.SocketOptionName]::ReuseAddress,$true)
    $socket.SetSocketOption([Net.Sockets.SocketOptionLevel]::IP,[Net.Sockets.SocketOptionName]::PacketInformation,$true)
    $socket.EnableBroadcast=$true; $socket.ReceiveTimeout=1000; $socket.SendTimeout=1000
    $socket.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Any,67))
    $record.stage='listening'; Save-Q11DhcpRecord
    $buffer=New-Object byte[] 2048
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $DurationSec) {
        [Net.EndPoint]$remote=[Net.IPEndPoint]::new([Net.IPAddress]::Any,0)
        [Net.Sockets.SocketFlags]$flags=[Net.Sockets.SocketFlags]::None
        $info=[Net.Sockets.IPPacketInformation]::new()
        try { $n=$socket.ReceiveMessageFrom($buffer,0,$buffer.Length,[ref]$flags,[ref]$remote,[ref]$info) }
        catch [Net.Sockets.SocketException] { if ($_.Exception.SocketErrorCode -eq [Net.Sockets.SocketError]::TimedOut) { continue }; throw }
        $record.received++
        if ($info.Interface -ne $adapter.ifIndex -or $remote.Port -ne 68 -or $flags -band [Net.Sockets.SocketFlags]::Truncated) { $record.ignored++; continue }
        try { $request=Read-Q11DhcpRequest -Packet ([byte[]]$buffer[0..($n-1)]) }
        catch { $record.ignored++; continue }
        if ($selectedMac -and $selectedMac -ne $request.MacHex) { $record.ignored++; continue }
        if ($request.Type -eq 1) { $type=2; $selectedMac=$request.MacHex }
        elseif (Test-Q11DhcpSelection -Request $request) { $type=5; $selectedMac=$request.MacHex }
        else { $record.ignored++; continue }
        $reply=New-Q11DhcpReply -Request $request -MessageType $type
        $destination = if ([BitConverter]::ToUInt32($request.Packet,12)) { $client } else { $broadcast }
        $sent=$socket.SendTo($reply,[Net.IPEndPoint]::new([Net.IPAddress]::Parse($destination),68))
        if ($sent -ne $reply.Length) { throw 'Incomplete DHCP datagram send.' }
        if ($type -eq 2) { $record.offers++ } else { $record.acks++; $record['last_ack']=(Get-Date -Format o) }
        Save-Q11DhcpRecord
    }
    $record.result = if ($record.acks) { 'ack-sent' } else { 'no-ack' }
    if (-not $record.acks) { $resultCode=3 }
}
catch { $resultCode=2; $record.result='error'; $record['error']=$_.Exception.Message; Write-Error -ErrorAction Continue $_ }
finally {
    if ($socket) { $socket.Dispose() }
    $record.stage='restoring'; Save-Q11DhcpRecord
    try {
        if ($ruleAdded) { Remove-NetFirewallRule -Name $rule }
        if ($addressAdded) { Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -IPAddress $server -PolicyStore ActiveStore -Confirm:$false }
        if ($dhcpChanged) { Set-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -Dhcp Enabled -PolicyStore ActiveStore }
        $record.restored=$true
    }
    catch { $resultCode=2; $record.result='restore-error'; $record['restore_error']=$_.Exception.Message }
    $record.stage='complete'; $record.exit_code=$resultCode; $record['completed_at']=(Get-Date -Format o)
    Save-Q11DhcpRecord
    Write-Output "Result: $log"
}
exit $resultCode
