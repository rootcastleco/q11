<# Receive-only capture with metadata; no UART transmit and no flash operations. #>
[CmdletBinding()]
param(
    [string]$Port = 'auto',
    [ValidateRange(5,300)][int]$DurationSec = 120,
    [ValidateSet('media-probe','passive')][string]$Operation = 'media-probe',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\logs'),
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$capture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\uart_capture.ps1'))
if (-not (Test-Path -LiteralPath $capture -PathType Leaf)) { throw "Missing capture tool: $capture" }
if ($Port -ne 'auto' -and $Port -notmatch '^COM[1-9][0-9]*$') { throw 'Port must be auto or COMn.' }
if ($DryRun) { Write-Output "Receive only: port=$Port baud=115200 operation=$Operation max duration=$DurationSec seconds"; return }
if ($Port -eq 'auto') {
    $devices = @(Get-PnpDevice -PresentOnly -Class Ports | Where-Object { $_.InstanceId -match 'VID_1A86&PID_5523' })
    if ($devices.Count -ne 1 -or $devices[0].FriendlyName -notmatch '\((COM\d+)\)') { throw 'Exactly one CH341A UART port is required.' }
    $Port = $Matches[1]
}
$directory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$name = 'experiment_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + $Operation
$output = Join-Path $directory "$name.log"
if (Test-Path -LiteralPath $output) { throw "Capture already exists: $output" }
$commit = (& git -C (Join-Path $PSScriptRoot '..\..') rev-parse HEAD)
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine repository commit.' }
$meta = [ordered]@{ timestamp = (Get-Date -Format o); git_commit = $commit; tool_version = '1.0'; port = $Port; baud = 115200; operation = $Operation; result = 'running'; exit_code = $null }
$exitCode = 0
try {
    & $capture -Port $Port -Baud 115200 -OutFile $output -MaxTotalSec $DurationSec -WaitFirstByteSec $DurationSec -MaxAfterFirstSec $DurationSec -SilenceStopSec $DurationSec -ArmAfterSilenceSec 0 -ArmBytes 1
    if (-not (Test-Path -LiteralPath $output) -or (Get-Item -LiteralPath $output).Length -eq 0) { throw 'No UART bytes received.' }
    $meta.result = 'captured'
    $meta['sha256'] = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
}
catch { $exitCode = 2; $meta.result = 'error'; $meta['error'] = $_.Exception.Message; Write-Error -ErrorAction Continue $_ }
finally {
    $meta.exit_code = $exitCode
    $meta['completed_at'] = (Get-Date -Format o)
    $meta | ConvertTo-Json | Set-Content -LiteralPath "$output.metadata.json" -Encoding utf8
    Write-Output "Log: $output"
    Write-Output "Metadata: $output.metadata.json"
}
exit $exitCode
