<#
  uart_capture.ps1 - Huawei Q11 UART log yakalayici (YALNIZCA OKUR).

  Bu betik seri porta hicbir zaman veri yazmaz. DTR/RTS kapali, akis kontrolu yok.
  Gelen baytlar oldugu gibi (ham) dosyaya yazilir. Yanina <OutFile>.timing.tsv
  dosyasi yazilir: her okuma parcasinin zamani (ms) ve dosyadaki konumu.

  Port henuz yoksa (adaptor takili degil) takilmasini bekler; kayit sirasinda adaptor
  cikarilirsa yeniden takilmasini bekler ve ayni dosyaya eklemeye devam eder.

  Ornek:
    pwsh -NoProfile -File tools\uart_capture.ps1 -Port auto -OutFile logs\boot_01.log
  (-Port auto: CH341'in o anki COM numarasini kendisi bulur.)
#>
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [int]$Baud = 115200,
    [string]$OutFile = (Join-Path $PSScriptRoot '..\logs\boot_01.log'),
    [int]$ArmBytes = 64,            # bu kadar bayt gelmeden zamanlayicilar baslamaz (kablo takarken gelen cop baytlar)
    [int]$ArmAfterSilenceSec = 0,   # >0 ise: once hat bu kadar sn sessiz kalmali (Q11 kapali), sonra gelen veriyle baslar
    [int]$WaitFirstByteSec = 1200,  # veri gelmesi icin en fazla bekleme (port bekleme dahil)
    [int]$SilenceStopSec = 120,     # veri geldikten sonra bu kadar sessizlikte dur
    [int]$MaxAfterFirstSec = 900    # veri gelmeye basladiktan sonra en fazla kayit suresi
)

$ErrorActionPreference = 'Stop'
$OutFile = [System.IO.Path]::GetFullPath($OutFile)
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null

function Say([string]$msg) {
    $line = "[$(Get-Date -Format s)] $msg"
    Write-Output $line
    $tf.WriteLine("# $line"); $tf.Flush()
}

# -Port auto: CH341 (VID_1A86&PID_5523) hangi COM numarasini aldiysa onu bul (USB portu degisince numara degisir)
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
Say "salt-okunur kayit: $Port $Baud 8N1 -> $OutFile"

try {
    while ($true) {
        $now = Get-Date
        $n = 0
        if ($null -eq $sp) {
            $name = Resolve-Port $Port
            if ($name -and ([System.IO.Ports.SerialPort]::GetPortNames() -contains $name)) {
                try { $sp = Open-Port $name; Say "$name acildi" }
                catch { $sp = $null; Start-Sleep -Milliseconds 500 }
            } else {
                Start-Sleep -Milliseconds 500
            }
        } else {
            try { $n = $sp.Read($buf, 0, $buf.Length) }
            catch [System.TimeoutException] { $n = 0 }
            catch {
                Say "$($sp.PortName) baglantisi koptu: $($_.Exception.Message)"
                try { $sp.Dispose() } catch { }
                $sp = $null; $n = 0
            }
        }
        $now = Get-Date
        if (-not $quietSeen -and ($now - $lastAny).TotalSeconds -ge $ArmAfterSilenceSec) {
            $quietSeen = $true; $armBase = $total; Say "hat $ArmAfterSilenceSec sn sessiz kaldi, yeni veri bekleniyor"
        }
        if ($n -gt 0) {
            $tf.WriteLine("$($sw.ElapsedMilliseconds)`t$total`t$n"); $tf.Flush()
            $fs.Write($buf, 0, $n); $fs.Flush()
            $total += $n; $last = $now; $lastAny = $now
            if (-not $first -and $quietSeen -and ($total - $armBase) -ge $ArmBytes) { $first = $now; Say "veri akisi basladi" }
        }
        if (-not $first -and ($now - $start).TotalSeconds -ge $WaitFirstByteSec) { $reason = 'yeterli veri gelmedi'; break }
        if ($first -and ($now - $last).TotalSeconds -ge $SilenceStopSec)          { $reason = "$SilenceStopSec sn sessizlik"; break }
        if ($first -and ($now - $first).TotalSeconds -ge $MaxAfterFirstSec)       { $reason = 'azami sure'; break }
    }
}
finally {
    if ($sp) { try { $sp.Dispose() } catch { } }
    Say "durdu ($reason). Toplam $total bayt"
    $fs.Close(); $tf.Close()
}
