Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\rootfs\usb-io.psm1') -Force
$cases = @(
    @{ Remaining=0L; Expected=0 },
    @{ Remaining=512L; Expected=512 },
    @{ Remaining=1048576L; Expected=1048576 },
    @{ Remaining=2148532224L; Expected=1048576 },
    @{ Remaining=1099511627776L; Expected=1048576 }
)
foreach ($case in $cases) {
    $actual = Get-Q11ChunkSize -RemainingBytes $case.Remaining
    if ($actual -ne $case.Expected) { throw "Wrong chunk size for $($case.Remaining): $actual" }
}
$failed = $false
try { Get-Q11ChunkSize -RemainingBytes -1 | Out-Null } catch { $failed=$true }
if (-not $failed) { throw 'Negative remaining bytes accepted.' }
$failed = $false
try { Import-Module (Join-Path $PSScriptRoot 'missing-q11-module.psm1') -ErrorAction Stop } catch { $failed=$true }
if (-not $failed) { throw 'Missing module accepted.' }
$probeDisk = [pscustomobject]@{BusType='USB'; IsSystem=$false; IsBoot=$false; Size=15833497600L; LogicalSectorSize=512; Number=3}
if ((Select-Q11ProbeDisk -Disks @($probeDisk) -ExpectedSizeBytes 15833497600L).Number -ne 3) { throw 'Expected USB disk was not selected.' }
foreach ($candidates in @(@(), @($probeDisk,$probeDisk))) {
    $failed=$false
    try { Select-Q11ProbeDisk -Disks $candidates -ExpectedSizeBytes 15833497600L | Out-Null } catch { $failed=$true }
    if (-not $failed) { throw 'Missing/ambiguous USB selection accepted.' }
}
$probeDisk.IsSystem=$true
$failed=$false
try { Select-Q11ProbeDisk -Disks @($probeDisk) -ExpectedSizeBytes 15833497600L | Out-Null } catch { $failed=$true }
if (-not $failed) { throw 'System disk selected.' }
$probeDisk.IsSystem=$false; $probeDisk.BusType='SATA'
$failed=$false
try { Select-Q11ProbeDisk -Disks @($probeDisk) -ExpectedSizeBytes 15833497600L | Out-Null } catch { $failed=$true }
if (-not $failed) { throw 'Non-USB disk selected.' }
$capturePreview = & (Join-Path $PSScriptRoot '..\tools\uart\capture_experiment.ps1') -DryRun
if ($capturePreview -notmatch 'Receive only: port=auto baud=115200') {
    throw 'Default receive-only capture preview failed.'
}
$issues=@()
Get-ChildItem (Join-Path $PSScriptRoot '..\tools') -Recurse -File | Where-Object { $_.Extension -in '.ps1','.psm1' } | ForEach-Object {
    $tokens=$null; $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
    $issues += $errors
}
if ($issues.Count) { throw ($issues | Out-String) }
Write-Output 'PASS: transfer sizes, unique/non-system USB selection, invalid/missing inputs and PowerShell parsing'
