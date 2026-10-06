<# Write a validated MBR image to the uniquely labelled USB disk, then hash readback.
   Requires Administrator. Never selects a disk from a guessed disk number.
   Re-running after success requires relabelling; Windows cannot mount ext4.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Image,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$Sha256,
    [Parameter(Mandatory=$true)][ValidateRange(1,1099511627776)][long]$ExpectedDiskSizeBytes,
    [string]$TargetLabel = 'REI',
    [string]$LogDirectory = (Join-Path $PSScriptRoot '..\..\logs'),
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Image = [IO.Path]::GetFullPath($Image)
if (-not (Test-Path -LiteralPath $Image -PathType Leaf)) { throw "Missing image: $Image" }
if ((Get-Item -LiteralPath $Image).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Image symlinks are not supported.' }
$imageSize = (Get-Item -LiteralPath $Image).Length
if ($imageSize -lt 256MB -or $imageSize % 512 -ne 0) { throw 'Image size must be >=256 MiB and sector aligned.' }
if ((Get-FileHash -LiteralPath $Image -Algorithm SHA256).Hash -ne $Sha256) { throw 'Image SHA256 mismatch.' }
$volumes = @(Get-Volume | Where-Object { $_.FileSystemLabel -eq $TargetLabel })
if ($volumes.Count -ne 1 -or -not $volumes[0].DriveLetter) { throw 'Exactly one mounted target label is required.' }
$letter = [string]$volumes[0].DriveLetter
$partitions = @(Get-Partition -DriveLetter $letter)
if ($partitions.Count -ne 1) { throw 'Ambiguous volume-to-disk mapping.' }
$disk = Get-Disk -Number $partitions[0].DiskNumber
if ($disk.BusType -ne 'USB' -or $disk.IsBoot -or $disk.IsSystem -or $disk.IsReadOnly -or $disk.Size -ne $ExpectedDiskSizeBytes) { throw 'Target is not the expected writable non-system USB disk.' }
if ($disk.PartitionStyle -ne 'MBR' -or $disk.LogicalSectorSize -ne 512 -or $imageSize -gt $disk.Size) { throw 'Requires an existing MBR USB disk with 512-byte sectors and sufficient capacity.' }
$allPartitions = @(Get-Partition -DiskNumber $disk.Number)
if ($allPartitions.Count -ne 1 -or $allPartitions[0].DriveLetter -ne $letter) { throw 'Target must have exactly one partition, carrying the requested label.' }
$check = [IO.File]::OpenRead($Image)
try {
    $header = New-Object byte[] 512
    if ($check.Read($header,0,512) -ne 512 -or $header[510] -ne 0x55 -or $header[511] -ne 0xaa -or $header[450] -ne 0x83 -or [BitConverter]::ToUInt32($header,454) -ne 2048) { throw 'Image is not a Q11 MBR/ext4 image.' }
    if ([BitConverter]::ToUInt32($header,458)*512L + 1MB -ne $imageSize) { throw 'Partition size disagrees with image size.' }
}
finally { $check.Dispose() }
Write-Output "Target: $TargetLabel ($letter`:) Disk $($disk.Number), $($disk.Size) bytes; image $imageSize bytes."
if ($DryRun) { Write-Output 'DRY RUN: all validation passed; no device handles opened for writing.'; return }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this exact command from Administrator PowerShell (Windows requires elevation for raw disk writes).' }
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$logPath = Join-Path ([IO.Path]::GetFullPath($LogDirectory)) ('experiment_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_usb-write.json')
$commit = & git -C (Join-Path $PSScriptRoot '..\..') rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine git commit.' }
$record = [ordered]@{ timestamp=(Get-Date -Format o); git_commit=$commit; tool_version='1.0'; port=$null; baud=$null; operation='usb-image-write'; target_label=$TargetLabel; disk_number=$disk.Number; disk_size=$disk.Size; image_sha256=$Sha256.ToLowerInvariant(); image_bytes=$imageSize; result='running'; exit_code=$null }
# Windows volume locking keeps the filesystem driver from racing the raw write.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class Q11UsbNative {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool DeviceIoControl(SafeFileHandle handle, uint code, IntPtr input, uint inputSize, IntPtr output, uint outputSize, out uint returned, IntPtr overlapped);
}
'@
$volume = $null; $device = $null; $source = $null; $resultCode = 0
try {
    $volume = [Q11UsbNative]::CreateFile("\\.\$letter`:",[uint32]3221225472,3,[IntPtr]::Zero,3,0,[IntPtr]::Zero)
    if ($volume.IsInvalid) { throw "Cannot open USB volume: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    [uint32]$returned = 0
    if (-not [Q11UsbNative]::DeviceIoControl($volume,0x90018,[IntPtr]::Zero,0,[IntPtr]::Zero,0,[ref]$returned,[IntPtr]::Zero)) { throw "Cannot lock USB volume: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
    if (-not [Q11UsbNative]::DeviceIoControl($volume,0x90020,[IntPtr]::Zero,0,[IntPtr]::Zero,0,[ref]$returned,[IntPtr]::Zero)) { throw 'Cannot dismount locked USB volume.' }
    # Re-check disk identity immediately before opening the physical disk.
    $current = Get-Disk -Number $disk.Number
    if ($current.Size -ne $ExpectedDiskSizeBytes -or $current.BusType -ne 'USB' -or $current.IsSystem -or $current.IsBoot -or $current.UniqueId -ne $disk.UniqueId -or $current.FriendlyName -ne $disk.FriendlyName) { throw 'Disk identity changed.' }
    $device = [IO.FileStream]::new("\\.\PhysicalDrive$($disk.Number)",[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::ReadWrite,1MB,[IO.FileOptions]::WriteThrough)
    $source = [IO.File]::OpenRead($Image)
    $buffer = New-Object byte[] 1MB
    $deadline = [DateTime]::UtcNow.AddMinutes(15)
    [long]$written = 0
    while ($written -lt $imageSize) {
        if ([DateTime]::UtcNow -gt $deadline) { throw '15-minute write deadline exceeded.' }
        $n = $source.Read($buffer,0,[int][Math]::Min($buffer.Length,$imageSize-$written))
        if ($n -le 0 -or $n % 512 -ne 0) { throw 'Image truncated/unaligned during write.' }
        $device.Write($buffer,0,$n); $written += $n
    }
    $device.Flush($true)
    [void]$device.Seek(0,[IO.SeekOrigin]::Begin)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        [long]$remaining = $imageSize
        while ($remaining -gt 0) {
            if ([DateTime]::UtcNow -gt $deadline) { throw '15-minute verification deadline exceeded.' }
            $n = $device.Read($buffer,0,[int][Math]::Min($buffer.Length,$remaining))
            if ($n -le 0) { throw 'USB readback ended early.' }
            [void]$hasher.TransformBlock($buffer,0,$n,$buffer,0); $remaining -= $n
        }
        [void]$hasher.TransformFinalBlock([byte[]]@(),0,0)
        $actual = ([BitConverter]::ToString($hasher.Hash)).Replace('-','').ToLowerInvariant()
    }
    finally { $hasher.Dispose() }
    $record['readback_sha256'] = $actual
    if ($actual -ne $Sha256.ToLowerInvariant()) { throw 'USB readback SHA256 mismatch.' }
    $record.result = 'written-and-verified'
    Write-Output 'USB image written and verified. Windows cannot mount ext4; decline any format prompt.'
}
catch { $resultCode=2; $record.result='error'; $record['error']=$_.Exception.Message; Write-Error -ErrorAction Continue $_ }
finally {
    if ($source) { $source.Dispose() }; if ($device) { $device.Dispose() }; if ($volume) { $volume.Dispose() }
    $record.exit_code=$resultCode; $record['completed_at']=(Get-Date -Format o)
    $record | ConvertTo-Json | Set-Content -LiteralPath $logPath -Encoding utf8
    Write-Output "Result log: $logPath"
}
exit $resultCode
