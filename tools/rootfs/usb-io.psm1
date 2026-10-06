Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Q11ChunkSize {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateRange(0,9223372036854775807)][long]$RemainingBytes,
        [ValidateRange(1,16777216)][int]$BufferBytes = 1048576
    )
    # Both operands must be Int64: image extents can exceed Int32.MaxValue.
    return [int][Math]::Min([long]$BufferBytes,[long]$RemainingBytes)
}
function Select-Q11ProbeDisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Disks,
        [Parameter(Mandatory=$true)][ValidateRange(2097152,1099511627776)][long]$ExpectedSizeBytes
    )
    $selected = @($Disks | Where-Object { $_.BusType -eq 'USB' -and
        -not $_.IsSystem -and -not $_.IsBoot -and $_.Size -eq $ExpectedSizeBytes })
    if ($selected.Count -ne 1) { throw 'Exactly one non-system/non-boot USB disk of the expected capacity is required.' }
    if ($selected[0].LogicalSectorSize -ne 512) { throw 'USB probe requires 512-byte logical sectors.' }
    return $selected[0]
}
Export-ModuleMember -Function Get-Q11ChunkSize,Select-Q11ProbeDisk
