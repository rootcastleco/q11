$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\network\port-report.psm1') -Force
$directory=Join-Path ([IO.Path]::GetTempPath()) ('q11-port-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $directory | Out-Null
$path=Join-Path $directory 'scan.xml'
$fixture='<nmaprun><scaninfo protocol="tcp" numservices="65535"/><host><address addr="192.168.73.2" addrtype="ipv4"/><ports><extraports state="closed" count="65534"/><port protocol="tcp" portid="56790"><state state="open"/></port></ports></host><runstats><finished exit="success"/></runstats></nmaprun>'
function Expect-Failure([scriptblock]$Action) { $failed=$false; try { & $Action | Out-Null } catch { $failed=$true }; if (-not $failed) { throw 'Expected input rejection.' } }
try {
    $fixture | Set-Content -LiteralPath $path
    $before=(Get-FileHash $path).Hash
    $result=Read-Q11PortInventory -Path $path
    if ($result.CoveredPorts -ne 65535 -or $result.OpenPorts.Count -ne 1 -or $result.OpenPorts[0] -ne 56790 -or (Get-FileHash $path).Hash -ne $before) { throw 'Valid XML parse failed/modified input.' }
    foreach ($invalid in @($fixture.Replace('count="65534"','count="65533"'),$fixture.Replace('exit="success"','exit="error"'),$fixture.Replace('<host>','<host timedout="true">'),$fixture.Replace('192.168.73.2','192.168.1.1'),'<broken>')) {
        $invalid | Set-Content -LiteralPath $path
        Expect-Failure { Read-Q11PortInventory -Path $path }
    }
    Expect-Failure { Read-Q11PortInventory -Path (Join-Path $directory 'missing.xml') }
    Write-Output 'Port XML success/coverage/timeout/target/malformed/missing tests passed.'
} finally { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $directory }
