Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Q11DhcpRequest {
    param([Parameter(Mandatory=$true)][byte[]]$Packet)
    if ($Packet.Length -lt 240 -or $Packet.Length -gt 2048) { throw 'Invalid DHCP packet size.' }
    if ($Packet[0] -ne 1 -or $Packet[1] -ne 1 -or $Packet[2] -ne 6 -or $Packet[3] -ne 0) { throw 'Only direct Ethernet BOOTREQUEST is supported.' }
    if ([BitConverter]::ToUInt32($Packet,24) -ne 0) { throw 'DHCP relays are not supported.' }
    if (($Packet[236..239] -join ',') -ne '99,130,83,99') { throw 'Bad DHCP cookie.' }
    if (($Packet[28] -band 1) -or (($Packet[28..33] -join ',') -eq '0,0,0,0,0,0')) { throw 'Invalid client address.' }
    $options = @{}; $offset=240; $ended=$false
    while ($offset -lt $Packet.Length) {
        $code=[int]$Packet[$offset]; $offset++
        if ($code -eq 255) { $ended=$true; break }
        if ($code -eq 0) { continue }
        if ($offset -ge $Packet.Length) { throw 'Truncated DHCP option length.' }
        $length=[int]$Packet[$offset]; $offset++
        if ($offset+$length -gt $Packet.Length) { throw 'Truncated DHCP option.' }
        if ($options.ContainsKey($code)) { throw 'Duplicate DHCP option is unsupported.' }
        [byte[]]$value = if ($length) { $Packet[$offset..($offset+$length-1)] } else { @() }
        $options[$code]=$value; $offset += $length
    }
    if (-not $ended -or -not $options.ContainsKey(53) -or $options[53].Length -ne 1) { throw 'Missing DHCP end/type.' }
    foreach ($code in 50,54) { if ($options.ContainsKey($code) -and $options[$code].Length -ne 4) { throw 'Bad DHCP IPv4 option.' } }
    if ($options.ContainsKey(52)) { throw 'Overloaded DHCP fields are unsupported.' }
    if (-not $options.ContainsKey(60) -or [Text.Encoding]::ASCII.GetString($options[60]) -ne 'dslforum.org:HUAWEI:STB:Q11') { throw 'Client is not the observed Q11 vendor class.' }
    return [pscustomobject]@{Packet=$Packet; Options=$options; Type=[int]$options[53][0];
        MacHex=([BitConverter]::ToString($Packet[28..33])).Replace('-','');
        Xid=([BitConverter]::ToString($Packet[4..7])).Replace('-','')}
}

function New-Q11DhcpReply {
    param([Parameter(Mandatory=$true)]$Request,
        [Parameter(Mandatory=$true)][ValidateSet(2,5)][int]$MessageType,
        [string]$ServerAddress='192.168.73.1',[string]$ClientAddress='192.168.73.2')
    $server=[Net.IPAddress]::Parse($ServerAddress).GetAddressBytes()
    $client=[Net.IPAddress]::Parse($ClientAddress).GetAddressBytes()
    if ($server.Length -ne 4 -or $client.Length -ne 4) { throw 'IPv4 required.' }
    if ($Request.Type -notin 1,3) { throw 'Only DISCOVER/REQUEST replies are supported.' }
    $reply=[Collections.Generic.List[byte]]::new()
    $header=New-Object byte[] 240
    [Array]::Copy($Request.Packet,0,$header,0,44)
    $header[0]=2; $header[3]=0
    [Array]::Clear($header,24,4)
    [Array]::Copy($client,0,$header,16,4); [Array]::Copy($server,0,$header,20,4)
    [Array]::Copy([byte[]](99,130,83,99),0,$header,236,4)
    $reply.AddRange($header)
    $reply.AddRange([byte[]](53,1,$MessageType,54,4)); $reply.AddRange($server)
    $reply.AddRange([byte[]](1,4,255,255,255,0,51,4,0,0,1,44,58,4,0,0,0,150,59,4,0,0,1,4))
    if ($Request.Options.ContainsKey(61)) {
        $identity=[byte[]]$Request.Options[61]
        $reply.AddRange([byte[]](61,$identity.Length)); $reply.AddRange($identity)
    }
    # No router, DNS, TFTP, boot image, vendor management or update options.
    $reply.Add(255)
    while ($reply.Count -lt 300) { $reply.Add(0) }
    return ,$reply.ToArray()
}

function Test-Q11DhcpSelection {
    param([Parameter(Mandatory=$true)]$Request,[string]$ServerAddress='192.168.73.1',[string]$ClientAddress='192.168.73.2')
    if ($Request.Type -ne 3) { return $false }
    if ($Request.Options.ContainsKey(54) -and [Net.IPAddress]::new([byte[]]$Request.Options[54]).ToString() -ne $ServerAddress) { return $false }
    $address = if ($Request.Options.ContainsKey(50)) { [Net.IPAddress]::new([byte[]]$Request.Options[50]).ToString() } else { [Net.IPAddress]::new([byte[]]$Request.Packet[12..15]).ToString() }
    return $address -eq $ClientAddress
}
Export-ModuleMember -Function Read-Q11DhcpRequest,New-Q11DhcpReply,Test-Q11DhcpSelection
