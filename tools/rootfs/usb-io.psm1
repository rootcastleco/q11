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
Export-ModuleMember -Function Get-Q11ChunkSize
