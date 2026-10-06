<#
  Q11 Linux Bring-up | Batuhan Ayribas | https://batuhanayribas.com
  uart_send.ps1 - Historical one-line/Enter transmit and response capture.

  Rejects a broad set of state-changing commands by default. A denylist is a
  guard, not proof of harmless behavior on an unknown console. Use -Override only
  for an explicitly authorized command. Appends data and ### notes to OutFile.
  No usable console has been obtained on the current Q11 firmware.

  Historical examples, not instructions for another trial:
    pwsh -NoProfile -File tools\uart_send.ps1 -Port COM10 -Enter
    pwsh -NoProfile -File tools\uart_send.ps1 -Port COM10 -Line 'cat /proc/mtd'
#>
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [string]$Line,                 # Transmit this line with a trailing CR.
    [switch]$Enter,                # Transmit CR only.
    [switch]$Override,             # Explicitly authorized denylist override.
    [switch]$DryRun,               # Check the denylist without opening the port.
    [int]$Baud = 115200,
    [double]$PreListenSec = 1,     # Receive before transmission.
    [double]$ListenSec = 8,        # Receive after transmission.
    [string]$HideRegex = 'HMW_network_getIpAddr|HMW_connectivity\.cpp|msgCallback execute failed|fdisk: can.t open',
    [string]$OutFile = (Join-Path $PSScriptRoot '..\logs\session_01.log')
)

$ErrorActionPreference = 'Stop'
if (-not $Enter -and [string]::IsNullOrEmpty($Line)) { throw 'Specify either -Enter or -Line.' }
if ($Enter -and $Line) { throw '-Enter and -Line cannot be combined.' }

# Broad guard: flash/environment writes, deletion, file changes, restart and more.
$deny = @(
    'saveenv', 'setenv', 'resetenv', '\benv\b', 'erase', 'nand\s+(write|scrub)', 'nandwrite', 'flash_',
    'flashcp', 'mtd\s+write', 'mtd_debug', 'mmc\s+write', 'sf\s+(write|update)', 'fastboot', '\bdd\b',
    'mkfs', 'format', 'ubi', 'fw_setenv', '\brm\b', '\bmv\b', '\bcp\b', '>', '\breboot\b', '\bpoweroff\b',
    '\bhalt\b', 'factory', 'upgrade', '\bwrite\b', '\bmount\b', '\bumount\b', '\bkill', '\bchmod\b',
    '\bchown\b', '\btouch\b', '\bmkdir\b', '\bln\b', 'insmod', 'rmmod', 'modprobe', '\bsysctl\b',
    '\bifconfig\b', '\budhcpc\b', '\bip\b', '\bboot', '\bgo\b', '\brun\b', '\bsed\b', '\btee\b'
)
if ($Line -and -not $Override) {
    foreach ($p in $deny) {
        if ($Line -match "(?i)$p") { throw "REJECTED: '$Line' matches '$p' (risk of persistent changes)." }
    }
}
if ($DryRun) { Write-Output "DRY RUN: allowed by guard -> $(if ($Enter) { '<Enter>' } else { $Line })"; return }

$OutFile = [System.IO.Path]::GetFullPath($OutFile)
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

# Select the currently enumerated CH341 UART COM port.
if ($Port -eq 'auto') {
    $d = Get-PnpDevice -PresentOnly -Class Ports -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1A86&PID_5523' } | Select-Object -First 1
    if (-not ($d -and $d.FriendlyName -match '\((COM\d+)\)')) { throw 'CH341 UART (VID_1A86&PID_5523) not found.' }
    $Port = $Matches[1]
}

$sp = [System.IO.Ports.SerialPort]::new($Port, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.Handshake    = [System.IO.Ports.Handshake]::None
$sp.DtrEnable    = $false
$sp.RtsEnable    = $false
$sp.ReadTimeout  = 200
$sp.WriteTimeout = 2000
$sp.Open()

$fs  = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
$buf = New-Object byte[] 65536
$rx  = [System.IO.MemoryStream]::new()

function Note([string]$t) {
    $b = [System.Text.Encoding]::UTF8.GetBytes("`n### [$(Get-Date -Format s)] $t`n")
    $fs.Write($b, 0, $b.Length); $fs.Flush()
}
function Pump([double]$sec) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $sec) {
        try { $n = $sp.Read($buf, 0, $buf.Length) } catch [System.TimeoutException] { $n = 0 }
        if ($n -gt 0) { $fs.Write($buf, 0, $n); $fs.Flush(); $rx.Write($buf, 0, $n) }
    }
}

try {
    $label = if ($Enter) { '<Enter>' } else { $Line }
    if ($Override) { Note "WARNING: denylist overridden with explicit authorization" }
    Note "listening ($PreListenSec seconds)"
    Pump $PreListenSec
    $mark = $rx.Length
    $payload = if ($Enter) { "`r" } else { "$Line`r" }
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($payload)
    Note "SENT: $label"
    $sp.Write($bytes, 0, $bytes.Length)
    Pump $ListenSec
    Note "completed"
}
finally {
    $fs.Close()
    if ($sp.IsOpen) { $sp.Close() }
}

$all  = $rx.ToArray()
$post = if ($all.Length -gt $mark) { $all[$mark..($all.Length - 1)] } else { @() }
$text = [System.Text.Encoding]::ASCII.GetString([byte[]]$post) -replace "`r", '' -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
$lines = $text -split "`n"
$shown = $lines | Where-Object { $_ -notmatch $HideRegex }
Write-Output "=== SENT: $label | response: $($post.Length) bytes, $($lines.Count) lines ($(($lines.Count) - ($shown.Count)) noisy lines hidden) ==="
$shown
