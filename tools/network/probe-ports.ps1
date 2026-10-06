<# Bounded TCP SYN inventory of the one client in an active isolated Q11 lease.
   No authentication, application payload, NSE scripts or version probes.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$LeaseLog,
    [ValidateSet('Common','All')][string]$Scope='Common',
    [string]$NmapPath='C:\Program Files (x86)\Nmap\nmap.exe',
    [string]$LogDirectory=(Join-Path $PSScriptRoot '..\..\logs'),
    [string]$ArtifactDirectory=(Join-Path $PSScriptRoot '..\..\artifacts'),
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not (Test-Path -LiteralPath $LeaseLog -PathType Leaf) -or (Get-Item -LiteralPath $LeaseLog).Length -gt 65536) { throw 'Missing/oversized lease record.' }
if (-not (Test-Path -LiteralPath $NmapPath -PathType Leaf)) { throw 'Nmap executable missing.' }
$lease=Get-Content -LiteralPath $LeaseLog -Raw | ConvertFrom-Json
if ($lease.operation -ne 'isolated-dhcp' -or $lease.stage -ne 'listening' -or $lease.acks -lt 1 -or $lease.server -ne '192.168.73.1' -or $lease.client -ne '192.168.73.2') { throw 'Requires active, acknowledged isolated Q11 lease.' }
$adapter=Get-NetAdapter -InterfaceIndex $lease.interface_index
if (-not $adapter.HardwareInterface -or $adapter.Status -ne 'Up' -or $adapter.Name -ne $lease.interface_alias) { throw 'Lease adapter is unavailable/changed.' }
$addresses=@(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq $lease.server })
if ($addresses.Count -ne 1) { throw 'Temporary server address is not active.' }
if (@(Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).Count) { throw 'Probe link must have no gateway.' }
$ports=if ($Scope -eq 'All') {'1-65535'} else {'21,22,23,24,80,443,8000,8080,8443,8888'}
Write-Output "Single-Q11 TCP SYN inventory: $($lease.client), ports=$ports, host timeout=60s."
if ($DryRun) { Write-Output 'DRY RUN: no probe process started.'; return }
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator PowerShell required for TCP SYN capture.' }
New-Item -ItemType Directory -Force -Path $LogDirectory,$ArtifactDirectory | Out-Null
$tag=Get-Date -Format 'yyyyMMdd_HHmmss'
$xmlPath=Join-Path ([IO.Path]::GetFullPath($ArtifactDirectory)) "q11-ports_${tag}.xml"
$logPath=Join-Path ([IO.Path]::GetFullPath($LogDirectory)) "experiment_${tag}_ports.json"
$rawPath=Join-Path ([IO.Path]::GetFullPath($LogDirectory)) "experiment_${tag}_ports.txt"
foreach ($path in $xmlPath,$logPath,$rawPath) { if (Test-Path -LiteralPath $path) { throw 'Output exists.' } }
$commit=& git -C (Join-Path $PSScriptRoot '..\..') rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine git commit.' }
$version=& $NmapPath --version | Select-Object -First 1
if ($LASTEXITCODE -ne 0) { throw 'Cannot read Nmap version.' }
$record=[ordered]@{timestamp=(Get-Date -Format o);git_commit=$commit;tool_version=$version;operation='isolated-tcp-syn';
    port=$null;baud=$null;target=$lease.client;interface_index=$adapter.ifIndex;ports=$ports;scope=$Scope;
    result='running';exit_code=$null;xml=$xmlPath;lease_log=[IO.Path]::GetFullPath($LeaseLog)}
$record | ConvertTo-Json | Set-Content -LiteralPath $logPath -Encoding utf8
$resultCode=2
try {
    # -Pn says skip host discovery; its "up" label is not independent reachability proof.
    & $NmapPath -sS -Pn -n -p $ports -T4 --max-rate 1500 --max-retries 0 --max-parallelism 256 --host-timeout 60s --reason -oX $xmlPath $lease.client 2>&1 | Set-Content -LiteralPath $rawPath -Encoding utf8
    $resultCode=$LASTEXITCODE
    if ($resultCode -ne 0) { throw "Nmap exit $resultCode; see private raw output." }
    [xml]$scan=Get-Content -LiteralPath $xmlPath -Raw
    if ($scan.nmaprun.runstats.finished.exit -ne 'success') { throw 'Nmap XML does not report successful completion.' }
    $record.result='completed'
    $record['xml_sha256']=(Get-FileHash -LiteralPath $xmlPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
catch { $resultCode=2; $record.result='error'; $record['error']=$_.Exception.Message; Write-Error -ErrorAction Continue $_ }
finally {
    $record.exit_code=$resultCode; $record['completed_at']=(Get-Date -Format o)
    $record | ConvertTo-Json | Set-Content -LiteralPath $logPath -Encoding utf8
    Write-Output "Result: $logPath"
}
exit $resultCode
