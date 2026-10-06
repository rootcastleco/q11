# Contributing

Q11 Linux Bring-up is maintained by [Batuhan Ayrıbaş](https://batuhanayribas.com).
Useful contributions reduce the gap between observed hardware behavior and a
reproducible external Linux boot.

## Make the evidence reviewable

Label findings **CONFIRMED**, **LIKELY** or **UNKNOWN**. Include the device/board
variant, experiment date, source revision, relevant log lines and the limitation
of the observation. A public MV100 example is not automatically a Q11 result.
Keep failed trials and corrections in the technical record.

Describe tools through their inputs, bounds, outputs and failure behavior. Prefer
fixtures over physical operations. Existing UART interruption trials are complete;
do not submit random key-flood experiments as a new boot method.

## Validate changes

```powershell
python -m unittest discover -s tests -v
pwsh -NoProfile -File tests/test_powershell.ps1
pwsh -NoProfile -File tests/test_dhcp.ps1
pwsh -NoProfile -File tests/test_port_report.ps1
```

On Linux, use `shellcheck tools/rootfs/*.sh tools/kernel/build.sh` and
`shellcheck -s sh tools/rootfs/init`. The optional `tests/test_host_tools.sh` suite
exercises real image/QEMU operations on the host with its documented dependencies.
Explain which checks ran and distinguish their result from a Q11 boot result.

## Capture and publication boundaries

Do not commit device serials/MACs, UDNs, passwords, private keys, proprietary
firmware blobs, downloaded rootfs images or new raw device captures. New
`logs/experiment_*`, build logs and generated `artifacts/` are ignored. Existing
historical captures are retained unchanged for checksum and timing references.
Publish a non-identifying summary with the checksum of private evidence instead.

Linux bring-up is the scope. CA/DRM bypasses, protected-credential extraction,
signature bypasses and speculative internal flash writes are outside it. A full
NAND backup project is not a prerequisite. Review any boot payload for internal
writes before calling it RAM-only.

## Documentation and identity

Write documentation, help text and comments in English. Use the project name and
website consistently; preserve upstream attribution. See [BRANDING](docs/BRANDING.md).
For a hardware-dependent change, document connector identity, power state,
connections, expected output and a bounded command before proposing a trial.
