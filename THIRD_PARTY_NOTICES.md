# Third-party boundaries

The repository-level 0BSD license applies only to original integration code,
tests, scripts and documentation that are not otherwise marked. It does not
relicense upstream EmuELEC, HiSTBLinux, Linux, SDL, RetroArch,
EmulationStation, libretro cores, vendor libraries, patches derived from those
projects, generated images, ROMs or BIOS files.

Pinned components used by the recipe include:

| Component | Revision/version | License boundary |
|---|---|---|
| EmuELEC | `65b3db37ebdca93d543b7e7b3d5df4a2c9ceee79` | Package aggregation; retain each upstream license |
| HiSTBLinux BSP | `fd20f78ab02934e71474dbb1d933c6ec911b01c9` | Mixed/vendor terms; SDK and binaries are not distributed here |
| EmulationStation | `2afe6efec4e09176882d98323bda5d3f664870a7` | Retain upstream license |
| RetroArch | `ccbff758b46556407d1b9931a72cfcc46201276d` | GPL family; retain upstream COPYING |
| QuickNES | `31654810b9ebf8b07f9c4dc27197af7714364ea7` | LGPL-2.1-or-later upstream |
| Snes9x 2010 | `187e2b58fc09dfeb9fdb5a95bc26786219a111cf` | Upstream non-commercial terms |
| Gambatte | `dd1cf9fdbadbdceee50ff0600321251c823c3ca5` | GPL-2.0 upstream |
| VBA Next | `019132daf41e33a9529036b8728891a221a8ce2e` | GPL-2.0 upstream |
| Genesis Plus GX | `7fa34f20de659004399f58a845291a4496cc9d8c` | Upstream non-commercial terms |
| Beetle PCE Fast | `bdcb39400470cfc9457e170e223a2e70130fdd5c` | GPL-2.0 upstream |
| PCSX-ReARMed | `19b9695a71f15ef0bf61c7c3cfd6c98ec5ccb028` | GPL-2.0 upstream |
| MAME 2003 | `e3d1dac4cfaa4d03f8da5a6d78149bfefe894302` | MAME upstream terms |
| SDL2 | 2.0.9 | zlib license |
| Dropbear | 2026.94 | Upstream component-specific notices |

No ROM, console BIOS, vendor SDK, vendor binary, device backup or official
flashing tool is included. Obtain those only from lawful sources and follow
their own terms.
