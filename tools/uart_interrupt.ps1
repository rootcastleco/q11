<#
  Q11 Linux Bring-up | Batuhan Ayribas | https://batuhanayribas.com
  uart_interrupt.ps1 - Historical boot-interruption trial and capture.

  Repeats one selected byte rather than a command line. Behavior depends on the
  receiving firmware. Ctrl+C/space trials on this Q11 are complete and failed;
  do not repeat them without new evidence.

  Historical examples:
    pwsh -NoProfile -File tools\uart_interrupt.ps1 -Key ctrl-c -DurationSec 30
    pwsh -NoProfile -File tools\uart_interrupt.ps1 -Key space -DurationSec 30
#>
param(
    [string]$Port = 'auto',
    [ValidateSet('ctrl-c','ctrl-b','space','enter','esc','a','x','s')]
    [string]$Key = 'ctrl-c',
    [int]$Baud = 115200,
    [double]$DurationSec = 30,     # Total transmission duration.
    [int]$IntervalMs = 20,         # Interval between key bytes.
    [double]$IdleStopSec = 6,      # Early stop after post-data silence.
    [string]$HideRegex = 'HMW_network_getIpAddr|HMW_connectivity\.cpp|msgCallback execute failed|fdisk: can.t open',
    [string]$OutFile = (Join-Path $PSScriptRoot '..\logs\break_01.log')
)

$ErrorActionPreference = 'Stop'
$map = @{ 'ctrl-c' = 3; 'ctrl-b' = 2; 'space' = 32; 'enter' = 13; 'esc' = 27; 'a' = 97; 'x' = 120; 's' = 115 }
$byte = [byte]$map[$Key]

if ($Port -eq 'auto') {
    $d = Get-PnpDevice -PresentOnly -Class Ports -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1A86&PID_5523' } | Select-Object -First 1
    if (-not ($d -and $d.FriendlyName -match '\((COM\d+)\)')) { throw 'CH341 UART (VID_1A86&PID_5523) not found.' }
    $Port = $Matches[1]
}

$OutFile = [System.IO.Path]::GetFullPath($OutFile)
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

$sp = [System.IO.Ports.SerialPort]::new($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.DtrEnable = $false
$sp.RtsEnable = $false
$sp.ReadTimeout = 50
$sp.Open()

$fs  = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
$buf = New-Object byte[] 65536
$rx  = [System.IO.MemoryStream]::new()
$one = [byte[]]@($byte)
Write-Output "[$(Get-Date -Format s)] $Port 115200 8N1 | key='$Key' (0x$("{0:X2}" -f $byte)) $DurationSec seconds | capture: $OutFile"
Write-Output "Interruption bytes are being sent; this is a historical transmit utility."

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$lastRx = $null
try {
    while ($sw.Elapsed.TotalSeconds -lt $DurationSec) {
        try { $sp.Write($one, 0, 1) } catch { }
        $deadline = [DateTime]::UtcNow.AddMilliseconds($IntervalMs)
        while ([DateTime]::UtcNow -lt $deadline) {
            try { $n = $sp.Read($buf, 0, $buf.Length) } catch [System.TimeoutException] { $n = 0 }
            if ($n -gt 0) { $fs.Write($buf, 0, $n); $fs.Flush(); $rx.Write($buf, 0, $n); $lastRx = [DateTime]::UtcNow }
        }
        if ($lastRx -and ([DateTime]::UtcNow - $lastRx).TotalSeconds -ge $IdleStopSec) { Write-Output "[$(Get-Date -Format s)] $IdleStopSec seconds of silence; stopped early"; break }
    }
}
finally {
    $fs.Close()
    if ($sp.IsOpen) { $sp.Close() }
}

$txt = [System.Text.Encoding]::ASCII.GetString($rx.ToArray()) -replace "`r", '' -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
$lines = $txt -split "`n"
$prompt = $lines | Where-Object { $_ -match '(?i)(hisilicon|fastboot|U-?Boot|=>|#\s*$|\bboot\b.*#|\$\s*$)' -and $_ -notmatch $HideRegex } | Select-Object -Last 6
$shown  = $lines | Where-Object { $_ -notmatch $HideRegex }
Write-Output "=== received: $($rx.Length) bytes, $($lines.Count) lines ==="
if ($prompt) { Write-Output "*** POSSIBLE BOOTLOADER/PROMPT TEXT; REQUIRES INSPECTION ***"; $prompt }
Write-Output "--- last 25 filtered lines ---"
$shown | Select-Object -Last 25
