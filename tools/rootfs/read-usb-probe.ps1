<# Read only the first 2 MiB of one uniquely identified external USB disk.
   Captures MBR and ext superblock for offline inspection. No device writes,
   volume dismount, filesystem mount, journal replay, or full-disk capture.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateRange(2097152,1099511627776)][long]$ExpectedDiskSizeBytes,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\..\artifacts'),
    [string]$LogDirectory = (Join-Path $PSScriptRoot '..\..\logs'),
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'usb-io.psm1') -Force
$disk = Select-Q11ProbeDisk -Disks @(Get-Disk) -ExpectedSizeBytes $ExpectedDiskSizeBytes
Write-Output "Read-only target: USB Disk $($disk.Number), $($disk.Size) bytes. Capture extent: 2097152 bytes."
if ($DryRun) { Write-Output 'DRY RUN: selection passed; no device handle opened.'; return }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator PowerShell is required for raw disk reads.' }
$commit = & git -C (Join-Path $PSScriptRoot '..\..') rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine git commit.' }
New-Item -ItemType Directory -Force -Path $OutputDirectory,$LogDirectory | Out-Null
$tag = Get-Date -Format 'yyyyMMdd_HHmmss'
$output = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "q11-usb-probe_$tag.bin"
$log = Join-Path ([IO.Path]::GetFullPath($LogDirectory)) "experiment_${tag}_usb-read.json"
if ((Test-Path -LiteralPath $log) -or (Test-Path -LiteralPath $output)) { throw 'Output already exists.' }
$record = [ordered]@{timestamp=(Get-Date -Format o); git_commit=$commit; tool_version='1.0';
    operation='usb-superblock-read'; port=$null; baud=$null; disk_number=$disk.Number;
    disk_size=$disk.Size; extent_bytes=2097152; bytes_read=0L; result='running'; exit_code=$null}
$record | ConvertTo-Json | Set-Content -LiteralPath $log -Encoding utf8
$device = $null; $destination = $null; $resultCode = 0
try {
    $current = Select-Q11ProbeDisk -Disks @(Get-Disk) -ExpectedSizeBytes $ExpectedDiskSizeBytes
    if ($current.Number -ne $disk.Number -or $current.UniqueId -ne $disk.UniqueId -or $current.FriendlyName -ne $disk.FriendlyName) { throw 'Disk identity changed.' }
    $device = [IO.FileStream]::new("\\.\PhysicalDrive$($disk.Number)",[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite,65536,[IO.FileOptions]::SequentialScan)
    $destination = [IO.FileStream]::new($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $buffer = New-Object byte[] 65536
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while ($record.bytes_read -lt $record.extent_bytes) {
        if ([DateTime]::UtcNow -gt $deadline) { throw '60-second read deadline exceeded.' }
        $n = $device.Read($buffer,0,(Get-Q11ChunkSize -RemainingBytes ($record.extent_bytes-$record.bytes_read) -BufferBytes $buffer.Length))
        if ($n -le 0) { throw 'USB read ended early.' }
        $destination.Write($buffer,0,$n); $record.bytes_read += $n
    }
    $destination.Flush($true); $destination.Dispose(); $destination=$null
    $record['sha256'] = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    $record.result = 'captured'; $record['output'] = $output
    Write-Output "Captured read-only USB prefix: $output"
}
catch { $resultCode=2; $record.result='error'; $record['error']=$_.Exception.Message; Write-Error -ErrorAction Continue $_ }
finally {
    if ($destination) { $destination.Dispose() }; if ($device) { $device.Dispose() }
    $record.exit_code=$resultCode; $record['completed_at']=(Get-Date -Format o)
    $record | ConvertTo-Json | Set-Content -LiteralPath $log -Encoding utf8
    Write-Output "Result log: $log"
}
exit $resultCode
