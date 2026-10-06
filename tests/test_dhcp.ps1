Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\network\dhcp.psm1') -Force
function New-TestRequest([int]$Type) {
    $data=[Collections.Generic.List[byte]]::new()
    $header=New-Object byte[] 240
    $header[0]=1; $header[1]=1; $header[2]=6
    $header[4]=12; $header[7]=34; $header[10]=128
    [Array]::Copy([byte[]](2,3,4,5,6,7),0,$header,28,6)
    [Array]::Copy([byte[]](99,130,83,99),0,$header,236,4)
    $data.AddRange($header); $data.AddRange([byte[]](53,1,$Type))
    $vendor=[Text.Encoding]::ASCII.GetBytes('dslforum.org:HUAWEI:STB:Q11')
    $data.AddRange([byte[]](60,$vendor.Length)); $data.AddRange($vendor)
    $data.AddRange([byte[]](61,7,1,2,3,4,5,6,7))
    if ($Type -eq 3) { $data.AddRange([byte[]](50,4,192,168,73,2,54,4,192,168,73,1)) }
    $data.Add(255)
    return ,$data.ToArray()
}
$packet=New-TestRequest 1
$request=Read-Q11DhcpRequest $packet
$offer=New-Q11DhcpReply $request 2
if ($offer.Length -lt 300 -or $offer[0] -ne 2 -or ($offer[16..19] -join '.') -ne '192.168.73.2' -or ($offer[4..7] -join ',') -ne ($packet[4..7] -join ',')) { throw 'Bad offer header.' }
if (($offer[240..242] -join ',') -ne '53,1,2') { throw 'Bad OFFER type.' }
$offset=240; $codes=@()
while ($offer[$offset] -ne 255) { $codes += [int]$offer[$offset]; $offset += 2+[int]$offer[$offset+1] }
if (@($codes | Where-Object { $_ -in 3,6,43,66,67,125 }).Count) { throw 'Unwanted gateway/DNS/update option.' }
$request=Read-Q11DhcpRequest (New-TestRequest 3)
if (-not (Test-Q11DhcpSelection $request)) { throw 'Valid selection rejected.' }
$ack=New-Q11DhcpReply $request 5
if ($ack[242] -ne 5) { throw 'Bad ACK type.' }
$request.Options[54]=[byte[]](192,168,73,99)
if (Test-Q11DhcpSelection $request) { throw 'Different server accepted.' }
$request.Options[54]=[byte[]](192,168,73,1); $request.Options[50]=[byte[]](192,168,73,99)
if (Test-Q11DhcpSelection $request) { throw 'Different lease address accepted.' }
foreach ($variant in 'short','cookie','relay','truncated','foreign','duplicate') {
    $bad=New-TestRequest 1
    switch ($variant) {
        short { $bad=[byte[]]$bad[0..100] }
        cookie { $bad[236]=0 }
        relay { $bad[24]=1 }
        truncated { $bad=[byte[]]$bad[0..245] }
        foreign { $bad[245]=0 }
        duplicate { $bad=[byte[]]($bad[0..($bad.Length-2)]+[byte[]](53,1,1,255)) }
    }
    $rejected=$false
    try { Read-Q11DhcpRequest $bad | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw "Malformed/foreign packet accepted: $variant" }
}
$failed=$false
try { Import-Module (Join-Path $PSScriptRoot 'missing-dhcp.psm1') -ErrorAction Stop } catch { $failed=$true }
if (-not $failed) { throw 'Missing module accepted.' }
# Exercise Windows/.NET PacketInformation and bounded receive, no real interface traffic.
$receiver=[Net.Sockets.Socket]::new([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Dgram,[Net.Sockets.ProtocolType]::Udp)
$sender=[Net.Sockets.UdpClient]::new()
try {
    $receiver.SetSocketOption([Net.Sockets.SocketOptionLevel]::IP,[Net.Sockets.SocketOptionName]::PacketInformation,$true)
    $receiver.ReceiveTimeout=1000
    $receiver.Bind([Net.IPEndPoint]::new([Net.IPAddress]::Loopback,0))
    [void]$sender.Send($packet,$packet.Length,$receiver.LocalEndPoint)
    $buffer=New-Object byte[] 2048
    [Net.EndPoint]$remote=[Net.IPEndPoint]::new([Net.IPAddress]::Any,0)
    [Net.Sockets.SocketFlags]$flags=[Net.Sockets.SocketFlags]::None
    $info=[Net.Sockets.IPPacketInformation]::new()
    $n=$receiver.ReceiveMessageFrom($buffer,0,$buffer.Length,[ref]$flags,[ref]$remote,[ref]$info)
    if ($n -ne $packet.Length -or $info.Interface -le 0 -or $info.Address.ToString() -ne '127.0.0.1') { throw 'PacketInformation did not identify loopback.' }
    $timeout=$false
    try { [void]$receiver.ReceiveMessageFrom($buffer,0,$buffer.Length,[ref]$flags,[ref]$remote,[ref]$info) }
    catch [Net.Sockets.SocketException] { $timeout=$_.Exception.SocketErrorCode -eq [Net.Sockets.SocketError]::TimedOut }
    if (-not $timeout) { throw 'Receive deadline did not produce the expected timeout.' }
}
finally { $sender.Dispose(); $receiver.Dispose() }
Write-Output 'PASS: DHCP OFFER/ACK, client/server selection, malformed/foreign/relay rejection, no update options, loopback interface metadata and receive timeout'
