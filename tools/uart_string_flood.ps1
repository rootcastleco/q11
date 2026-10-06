<#
  Q11 Linux Bring-up | Batuhan Ayribas | https://batuhanayribas.com
  uart_string_flood.ps1 - Historical short stop-string trial.

  Tests a possible U-Boot CONFIG_AUTOBOOT_STOP_STR. No CR/LF is appended by
  default; receiving-firmware behavior is not guaranteed. -AppendCR requires
  explicit authorization. Missing kernel text alone does not prove a stopped
  bootloader or a shell. The current Q11's 'set' trial failed and is complete.

  Historical example:
    pwsh -NoProfile -File tools\uart_string_flood.ps1 -Text set -DurationSec 120
#>
param(
    [string]$Port = 'auto',
    [Parameter(Mandatory = $true)][string]$Text,
    [switch]$AppendCR,
    [int]$Baud = 115200,
    [double]$DurationSec = 120,
    [int]$IntervalMs = 40,
    [string]$HideRegex = 'HMW_network_getIpAddr|HMW_connectivity\.cpp|msgCallback execute failed|fdisk: can.t open',
    [string]$OutFile = (Join-Path $PSScriptRoot '..\logs\flood_01.log')
)

$ErrorActionPreference = 'Stop'
if ($Text.Length -gt 16) { throw '-Text must contain at most 16 characters.' }
# Appending CR can submit a command; apply the historical guard.
if ($AppendCR) {
    $deny = 'saveenv','setenv','resetenv','erase','write','nand','mmc','sf ','flash','fastboot','dd ','mkfs','format','ubi','reboot','reset','boot','go ','run ','rm ','mw ','cp ','mtd','env '
    foreach ($p in $deny) { if ($Text -match "(?i)$p") { throw "REJECTED: -AppendCR text '$Text' matches '$p'." } }
}

if ($Port -eq 'auto') {
    $d = Get-PnpDevice -PresentOnly -Class Ports -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1A86&PID_5523' } | Select-Object -First 1
    if (-not ($d -and $d.FriendlyName -match '\((COM\d+)\)')) { throw 'CH341 UART not found.' }
    $Port = $Matches[1]
}

$OutFile = [System.IO.Path]::GetFullPath($OutFile)
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

$payload = if ($AppendCR) { "$Text`r" } else { $Text }
$bytes = [System.Text.Encoding]::ASCII.GetBytes($payload)

$sp = [System.IO.Ports.SerialPort]::new($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.DtrEnable = $false; $sp.RtsEnable = $false; $sp.ReadTimeout = 50
$sp.Open()

$fs  = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
$buf = New-Object byte[] 65536
$rx  = [System.IO.MemoryStream]::new()
Write-Output "[$(Get-Date -Format s)] $Port 115200 8N1 | text='$Text'$(if($AppendCR){'+CR'}) $DurationSec seconds | capture: $OutFile"
Write-Output "Stop-string bytes are being sent; this is a historical transmit utility."

$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    while ($sw.Elapsed.TotalSeconds -lt $DurationSec) {
        try { $sp.Write($bytes, 0, $bytes.Length) } catch { }
        $deadline = [DateTime]::UtcNow.AddMilliseconds($IntervalMs)
        while ([DateTime]::UtcNow -lt $deadline) {
            try { $n = $sp.Read($buf, 0, $buf.Length) } catch [System.TimeoutException] { $n = 0 }
            if ($n -gt 0) { $fs.Write($buf, 0, $n); $fs.Flush(); $rx.Write($buf, 0, $n) }
        }
    }
}
finally { $fs.Close(); if ($sp.IsOpen) { $sp.Close() } }

$txt = [System.Text.Encoding]::ASCII.GetString($rx.ToArray()) -replace "`r", '' -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
$booted = [bool]($txt -match 'Booting Linux')
$lines = ($txt -split "`n") | Where-Object { $_ -notmatch $HideRegex }
Write-Output "=== received: $($rx.Length) bytes ==="
if ($booted) { Write-Output "RESULT: 'Booting Linux' observed; this trial did not stop autoboot ('$Text')." }
else         { Write-Output "RESULT: no 'Booting Linux' observed; reason UNKNOWN, not proof of a shell." }
Write-Output "--- last 20 filtered lines ---"
$lines | Select-Object -Last 20
