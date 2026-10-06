# Isolated stock Ethernet result

CONFIRMED on 2026-10-07: Q11 LAN connected directly to the PC physical Realtek
Ethernet port,100Mbps link; Q11 stock DHCP accepted192.168.73.2 from temporary
PC192.168.73.1/24. Two ICMP replies, TTL64,1–2ms, and an ARP neighbour confirm
reachability. The DHCP request vendor class is `dslforum.org:HUAWEI:STB:Q11`.
MAC values/raw replies stay private. Persistent MAC source is UNKNOWN.

No gateway/DNS/update options were offered. No forwarding/router/WAN was used;
Wi-Fi was untouched. Consequently DNS/routed connectivity was not tested. This
validates stock Ethernet, not Ethernet under the prepared custom userspace.

Private DHCP records: `logs/experiment_20261007_000359_dhcp.json`,
`experiment_20261007_000819_dhcp.json`, `experiment_20261007_001355_dhcp.json`.
All completed with ACKs, exit 0 and restored=true. Last completion00:17:58 restored
the physical interface to DHCP enabled/forwarding disabled, removing the lab IP
and the temporary firewall rule. Initial DHCP evidence is also in receive-only
`logs/experiment_20261007_000359_passive.log`.

## Bounded service inspection

Initial common-port connect scan produced filtered/no-response; it did not prove
closed ports. A subsequent Nmap SYN scan covered all 65,535 TCP ports in44.10s:
7547,56789,56790 open;65,532 closed/reset. Raw XML reports successful completion
and ARP response; `-Pn` alone is not reachability evidence. Private XML:
`artifacts/q11-ports_20261007_000632.xml`. The wrapper initially errored after the
scan due to PowerShell XML-property lookup. Preserve that error record; the fixed
XPath parser independently validates target/completion and65,535-state coverage.

All three ports accepted ordinary TCP connects and responded to `HEAD /`:
7547→404,56789/56790→400. No passive banner. The port 7547 role is LIKELY CWMP,
based on port and stock CPE logs; it was not treated as a shell or controlled.
No credentials, SOAP, application launch, reset, update or shell commands sent.

CONFIRMED: read-only `GET /dd.xml` on 56790 returned HTTP200, deviceType
`urn:schemas-upnp-org:device:tvdevice:1`, and a DIAL Application-URL pointing to
the same device's port 56789 `/apps/`. The request used the exact descriptor path
in the primary [Netflix DIAL reference implementation](https://github.com/Netflix/dial-reference/blob/29cb4ac0bf9be0ad9c5a2ecdef2729819ab01f5c/server/quick_ssdp.c).
No SSDP multicast was sent and no advertised application was launched. The pair
provides DIAL media discovery/application control, not a Linux maintenance shell.
Raw XML/UDN and HTTP responses remain in private
`artifacts/q11-dial_20261007_descriptor.json` and the banner/HEAD reports.

No SSH/telnet console is exposed in this scan. This snapshot does not prove that
all possible firmware maintenance modes are absent. No verified LAN command for
recovery or bootargs control was found.

## Reproduction tools

Only run the following on a confirmed direct PC→Q11 cable, with the named
physical adapter connected, initially DHCP-enabled, no non-APIPA IPv4/gateway.
Run the DHCP server in an Administrator PowerShell; it restores its changes in
finally. Do not kill that process before cleanup.

```powershell
pwsh -NoProfile -File tools/network/isolated-dhcp.ps1 -InterfaceAlias Ethernet -DryRun
pwsh -NoProfile -File tools/network/isolated-dhcp.ps1 -InterfaceAlias Ethernet -DurationSec 180
```

In a second Administrator PowerShell use the printed private lease record after
an ACK. `probe-ports.ps1` requires that record still says listening, plus the
correct physical adapter/server IP/no gateway. Nmap must already be installed.

```powershell
pwsh -NoProfile -File tools/network/probe-ports.ps1 -LeaseLog logs/experiment_YYYYMMDD_HHMMSS_dhcp.json -Scope All -DryRun
pwsh -NoProfile -File tools/network/probe-ports.ps1 -LeaseLog logs/experiment_YYYYMMDD_HHMMSS_dhcp.json -Scope All
python tools/network/probe_services.py --target 192.168.73.2 --source 192.168.73.1 --ports 56790 --mode dial-description --output artifacts/dial-new.json
```

Service inspection binds the explicit source, requires distinct RFC1918 addresses
on one/24, limits ports/time/response bytes, follows no redirects and never
overwrites output. It does not independently validate a live DHCP lease; confirm
the isolated setup first. Offline XML parser never resolves external resources.

```powershell
python -m unittest discover -s tests -v
pwsh -NoProfile -File tests/test_dhcp.ps1
pwsh -NoProfile -File tests/test_port_report.ps1
```

---

Maintained by [Batuhan Ayrıbaş](https://batuhanayribas.com) · Q11 Linux Bring-up
