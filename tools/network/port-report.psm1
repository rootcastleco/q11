Set-StrictMode -Version Latest
function Read-Q11PortInventory {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -gt 8MB) { throw 'Missing/oversized port XML.' }
    $settings=[Xml.XmlReaderSettings]::new()
    # Nmap includes its own DOCTYPE. Ignore it; never resolve external resources.
    $settings.DtdProcessing=[Xml.DtdProcessing]::Ignore
    $settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create([IO.Path]::GetFullPath($Path),$settings)
    $scan=[Xml.XmlDocument]::new(); $scan.XmlResolver=$null
    try { $scan.Load($reader) } finally { $reader.Dispose() }
    $finished=$scan.SelectSingleNode('/nmaprun/runstats/finished')
    if (-not $finished -or $finished.GetAttribute('exit') -ne 'success') { throw 'Nmap XML does not report successful completion.' }
    $hosts=$scan.SelectNodes('/nmaprun/host')
    if ($hosts.Count -ne 1 -or $hosts[0].GetAttribute('timedout') -eq 'true') { throw 'Requires exactly one completed target scan.' }
    $ipv4=$hosts[0].SelectNodes('address[@addrtype="ipv4"]')
    if ($ipv4.Count -ne 1 -or $ipv4[0].GetAttribute('addr') -ne '192.168.73.2') { throw 'XML target is not the isolated Q11.' }
    $info=$scan.SelectNodes('/nmaprun/scaninfo[@protocol="tcp"]')
    if ($info.Count -ne 1) { throw 'Requires one TCP scan.' }
    $requested=[int]$info[0].GetAttribute('numservices')
    if ($requested -lt 1 -or $requested -gt 65535) { throw 'Invalid requested port count.' }
    $observed=0; $open=@(); $explicit=@{}
    foreach ($node in $scan.SelectNodes('/nmaprun/host/ports/extraports')) {
        $count=[int]$node.GetAttribute('count')
        if ($count -lt 1) { throw 'Invalid extraports count.' }
        $observed += $count
    }
    foreach ($node in $scan.SelectNodes('/nmaprun/host/ports/port')) {
        $port=[int]$node.GetAttribute('portid'); $state=$node.SelectSingleNode('state')
        if ($node.GetAttribute('protocol') -ne 'tcp' -or $port -lt 1 -or $port -gt 65535 -or $explicit.ContainsKey($port) -or -not $state) { throw 'Invalid/duplicate TCP port.' }
        $explicit[$port]=$true; $observed++
        if ($state.GetAttribute('state') -eq 'open') { $open += $port }
    }
    if ($observed -ne $requested) { throw 'Incomplete TCP port-state coverage.' }
    [pscustomobject]@{Target='192.168.73.2';CoveredPorts=$observed;OpenPorts=$open;XmlSha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
}
Export-ModuleMember -Function Read-Q11PortInventory
