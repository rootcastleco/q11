# Memory accounting and conservative first boot

Stock log L6–8, L21:

* Physical RAM: 1,048,576 KiB =1,024 MiB.
* Boot-time available: 566,652 KiB =553.37 MiB.
* Reported reserved: 481,924 KiB =470.63 MiB.
* CMA media area:380 MiB at0x18400000, ending0x30000000 (exclusive).
* Second CMA area:4 MiB at0x3fc00000, ending0x40000000.
* DSP:8 MiB at0x02000000, ending0x02800000.
* Legacy RAM disk payload: about56.43 MiB compressed SquashFS, and associated
  copying/decompression phases. Boot-time available and later MemAvailable are
  different measurements; CMA can be usable for some movable allocations.

The stock initrd interval0x02500110..0x05d6f910 overlaps the DSP interval by about
3 MiB. This does not prove a boot bug: those regions may have distinct lifetimes.
It does prove that copying stock addresses without understanding lifetime is unsafe.
Loader workspaces, DTB, zImage relocation, DMA buffers and all reservations must be
checked before selecting a RAM download address. No fixed RAM load address is
asserted safe by this repository.

| Proposed MMZ | Reservation reduction versus380 MiB | Illustrative available if all other accounting stays identical |
|---|---|---|
|380 MiB (initial baseline)|0|553.37 MiB|
|128 MiB|252 MiB|805.37 MiB|
|64 MiB|316 MiB|869.37 MiB|

The last column is arithmetic, not measured or guaranteed memory. MMZ/CMA may be
fixed by DT/config rather than solely by `mmz=`. Changing media-region placement
can conflict with DSP/firmware DMA. First custom boot preserves380 MiB. After
shell/storage/network work, collect `/proc/iomem`, `/proc/meminfo`, boot reservation
messages and module dependency/allocation failures privately. Try a smaller MMZ
only through temporary arguments, without loading unnecessary media modules, and
measure before/after. Never write permanent bootargs for this experiment.

Framebuffer-only graphics needs a measured display-buffer allocation and working
module ABI. A smaller MMZ is not a prerequisite for the initial serial server.
