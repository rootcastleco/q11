<#
  uart_string_flood.ps1 - Acilis penceresinde bir KISA METNI tekrar tekrar UART'a gonderir.

  Amac: U-Boot "stop string" (CONFIG_AUTOBOOT_STOP_STR) testi. Bootloader acilis sirasinda
  gelen baytlari belirli bir kelimeyle karsilastiriyorsa, dogru kelime autoboot'u durdurur.

  Varsayilan: sonuna CR/LF EKLEMEZ -> hicbir komut CALISMAZ, yalnizca tampon dolar.
  -AppendCR yalnizca kullanici acikca isterse (o zaman metin + Enter gider).

  Basari isareti: acilistan sonra "Booting Linux" ve middleware spam'i GORULMEZSE autoboot durmus
  demektir (bootloader prompt'ta bekliyor, ciktisi kapali olabilir).

  Ornek:
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
if ($Text.Length -gt 16) { throw 'Guvenlik: -Text en fazla 16 karakter.' }
# CR olmadan hicbir komut calismaz. CR ekleniyorsa, komutun zararsiz oldugundan EMIN ol.
if ($AppendCR) {
    $deny = 'saveenv','setenv','resetenv','erase','write','nand','mmc','sf ','flash','fastboot','dd ','mkfs','format','ubi','reboot','reset','boot','go ','run ','rm ','mw ','cp ','mtd','env '
    foreach ($p in $deny) { if ($Text -match "(?i)$p") { throw "REDDEDILDI: -AppendCR ile '$Text' riskli ('$p'). CR'siz kullan." } }
}

if ($Port -eq 'auto') {
    $d = Get-PnpDevice -PresentOnly -Class Ports -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_1A86&PID_5523' } | Select-Object -First 1
    if (-not ($d -and $d.FriendlyName -match '\((COM\d+)\)')) { throw 'CH341 bulunamadi.' }
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
Write-Output "[$(Get-Date -Format s)] $Port 115200 8N1 | gonderilen='$Text'$(if($AppendCR){'+CR'}) $DurationSec sn | kayit: $OutFile"
Write-Output "SIMDI Q11'i yeniden baslat (fisi cek-tak)."

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
Write-Output "=== alinan: $($rx.Length) bayt ==="
if ($booted) { Write-Output "SONUC: 'Booting Linux' GORULDU -> autoboot DURMADI ('$Text' stop-string DEGIL)." }
else         { Write-Output "SONUC: 'Booting Linux' YOK -> autoboot DURMUS OLABILIR! (bootloader'da bekleniyor)" }
Write-Output "--- son 20 anlamli satir ---"
$lines | Select-Object -Last 20
