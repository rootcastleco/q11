<#
  Q11 Linux Bring-up | Batuhan Ayribas | https://batuhanayribas.com
  uart_capture.ps1 - Receive-only raw UART capture.

  Never transmits serial data. DTR/RTS and flow control are disabled.
  Preserves received bytes and writes a companion <OutFile>.timing.tsv with
  elapsed milliseconds, byte offsets and chunk sizes. Waits for the adapter,
  reconnects after removal and resumes the same capture.

  Example (use a new filename; the low-level tool can overwrite output):
    pwsh -NoProfile -File tools\uart_capture.ps1 -Port auto -OutFile logs\boot_01.log
  -Port auto selects the currently enumerated CH341 UART port.
#>
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [int]$Baud = 115200,
    [ValidateRange(0,3600)][int]$MaxTotalSec = 0,
    [string]$OutFile = (Join-Path $PSScriptRoot '..\logs\boot_01.log'),
    [int]$ArmBytes = 64,            # Received-byte threshold before data timers start.
    [int]$ArmAfterSilenceSec = 0,   # Require this quiet interval before arming.
    [int]$WaitFirstByteSec = 1200,  # Maximum wait including missing-port time.
    [int]$SilenceStopSec = 120,     # Stop after this much post-data silence.
    [int]$MaxAfterFirstSec = 900    # Maximum capture after the first armed bytes.
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$OutFile = [System.IO.Path]::GetFullPath($OutFile)
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

function Say([string]$msg) {
    $line = "[$(Get-Date -Format s)] $msg"
    Write-Output $line
    $tf.WriteLine("# $line"); $tf.Flush()
}

# Resolve CH341 UART VID/PID; moving USB ports can change the COM number.
function Resolve-Port([string]$p) {
    if ($p -ne 'auto') { return $p }
    $d = Get-PnpDevice -PresentOnly -Class Ports -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1A86&PID_5523' } | Select-Object -First 1
    if ($d -and $d.FriendlyName -match '\((COM\d+)\)') { return $Matches[1] }
    return $null
}

function Open-Port([string]$name) {
    $p = [System.IO.Ports.SerialPort]::new($name, $Baud, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    $p.Handshake      = [System.IO.Ports.Handshake]::None
    $p.DtrEnable      = $false
    $p.RtsEnable      = $false
    $p.ReadTimeout    = 500
    $p.ReadBufferSize = 1MB
    $p.Open()
    return $p
}

$fs  = [System.IO.File]::Open($OutFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
$tf  = [System.IO.StreamWriter]::new("$OutFile.timing.tsv", $false)
$tf.WriteLine("ms`toffset`tbytes")
$buf = New-Object byte[] 65536
$sw  = [System.Diagnostics.Stopwatch]::StartNew()
$sp  = $null
$start = Get-Date; $first = $null; $last = $null; $total = 0; $reason = ''
$lastAny = $start; $quietSeen = ($ArmAfterSilenceSec -le 0); $armBase = 0
Say "receive-only capture: $Port $Baud 8N1 -> $OutFile"

try {
    while ($true) {
        if ($MaxTotalSec -gt 0 -and $sw.Elapsed.TotalSeconds -ge $MaxTotalSec) { $reason = 'total duration limit'; break }
        $now = Get-Date
        $n = 0
        if ($null -eq $sp) {
            $name = Resolve-Port $Port
            if ($name -and ([System.IO.Ports.SerialPort]::GetPortNames() -contains $name)) {
                try { $sp = Open-Port $name; Say "$name opened" }
                catch { $sp = $null; Start-Sleep -Milliseconds 500 }
            } else {
                Start-Sleep -Milliseconds 500
            }
        } else {
            try { $n = $sp.Read($buf, 0, $buf.Length) }
            catch [System.TimeoutException] { $n = 0 }
            catch {
                Say "$($sp.PortName) disconnected: $($_.Exception.Message)"
                try { $sp.Dispose() } catch { }
                $sp = $null; $n = 0
            }
        }
        $now = Get-Date
        if (-not $quietSeen -and ($now - $lastAny).TotalSeconds -ge $ArmAfterSilenceSec) {
            $quietSeen = $true; $armBase = $total; Say "line quiet for $ArmAfterSilenceSec seconds; waiting for new data"
        }
        if ($n -gt 0) {
            $tf.WriteLine("$($sw.ElapsedMilliseconds)`t$total`t$n"); $tf.Flush()
            $fs.Write($buf, 0, $n); $fs.Flush()
            $total += $n; $last = $now; $lastAny = $now
            if (-not $first -and $quietSeen -and ($total - $armBase) -ge $ArmBytes) { $first = $now; Say "data stream started" }
        }
        if (-not $first -and ($now - $start).TotalSeconds -ge $WaitFirstByteSec) { $reason = 'insufficient data'; break }
        if ($first -and ($now - $last).TotalSeconds -ge $SilenceStopSec)          { $reason = "$SilenceStopSec seconds of silence"; break }
        if ($first -and ($now - $first).TotalSeconds -ge $MaxAfterFirstSec)       { $reason = 'post-data duration limit'; break }
    }
}
finally {
    if ($sp) { try { $sp.Dispose() } catch { } }
    Say "stopped ($reason); total $total bytes"
    $fs.Close(); $tf.Close()
}
