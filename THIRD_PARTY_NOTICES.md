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
| HiSTBLinux BSP | `fd20f78ab02934e71474dbb1d933c6ec911b01c9` | Mixed/vendor terms; fetched as the fixed `sdk/` submodule and not relicensed here |
| EmulationStation | `2afe6efec4e09176882d98323bda5d3f664870a7` | Retain the license and notices in the pinned upstream archive |
| RetroArch | `ccbff758b46556407d1b9931a72cfcc46201276d` | GPL family; retain upstream COPYING |
| FCEUmm | `236ccdfc911e84c60fea6b9d0699c2d440a8de14` | GPL-2.0 upstream plus separately licensed bundled files |
| Gambatte | `d9d6cd06382d1ced30de34d56d3609452323dab1` | GPL-2.0 upstream |
| gpSP | `8d268a6bb2cd799f8f2791ebb544a7ef550cfc6f` | GPL-2.0 upstream |
| mGBA | `c65e8a3d4666b0ea68a01578232452f31b185332` | MPL-2.0 upstream plus bundled dependency notices |
| PicoDrive | `733c711a477a642fd2006d5a7a581b2790ec36b4` | Upstream non-commercial/source-distribution terms plus five pinned submodule license sets |
| Snes9x 2010 | `7db129b1ecdccb38cb4d7184bcbed39beed79656` | Upstream non-commercial terms; Snes9x 2005 is not built |
| Beetle PCE Fast | `2f623abd033257b969370b73d9da982dcb0c3fdd` | GPL-2.0 upstream plus bundled dependency notices |
| PCSX-ReARMed | `ba61a4fdee1f789e8012f205f1b63826667644fa` | GPL-2.0 upstream plus bundled dependency notices |
| FinalBurn Neo | `26f11fa9e43227a04953e20e8c7e4bf322cd53cb` | Upstream non-commercial terms plus per-driver/dependency notices |
| MAME 2003-Plus | `21256d24120b04916c5197d95b757635ca880fd9` | Classic MAME non-commercial terms plus individually marked files |
| SDL2 | 2.0.9 | zlib license |
| Dropbear | 2026.94 | Upstream component-specific notices |
| pugixml | `7247a823b72259a2b814696838d02f7424a8ce0e` | MIT; `LICENSE.md` is present in the pinned archive |
| FreeImage | 3.18.0 | FreeImage Public License / GPL alternatives plus bundled-code notices; retain `license-fi.txt`, GPL texts and dependency notices |
| curl | 7.71.1 | curl permissive license; retain upstream `COPYING` |
| RapidJSON | 1.1.0 | MIT for RapidJSON, with separately licensed bundled directories listed in `license.txt`; the recipe does not use `bin/jsonchecker` |
| SDL2_mixer | 2.0.4 | zlib license for SDL2_mixer; retain applicable bundled dependency notices |
| libogg | 1.3.3 | Xiph BSD-style license; retain upstream `COPYING` |
| libvorbis | 1.3.6 | Xiph BSD-style license; retain upstream `COPYING` |
| libretro core info | `f8c1149c628c13be63a6ea605f49f0a94fec1421` | MIT; retain upstream `COPYING` |
| SDL GameControllerDB | `af76f5b56a180aabf3553a8b2b1c0bb7022a3274` | zlib license; the built-in fallback database and license are retained together |
| EmuELEC Carbon theme | `62509737c2f732b81ce7bf37f6c4c3b82dafae28` | The pinned `readme.txt` requires attribution, non-commercial use and share-alike distribution; it labels the work CC BY-NC-SA 2.0 while embedding 4.0 license text, so retain that file verbatim and apply the stricter non-commercial boundary |
| CMake host binary | 3.20.6 | Kitware BSD-style license plus bundled component notices under `doc/cmake`; host build tool only |

No ROM, console BIOS, device backup, generated firmware image or official
flashing tool is stored in this repository. The complete upstream SDK checkout
is linked as a fixed external Git submodule; its vendor files remain governed
by upstream terms. Review those terms before use or redistribution.

Every archive named in `SOURCES.lock` is SHA-256 pinned and its applicable
upstream licensing material is retained by the build; the table above covers
all 29 locked archives as well as the two fixed submodules. The repository does not publish the generated
release tarball or rootfs image. Anyone redistributing those generated binaries
must separately accompany them with every applicable notice, attribution,
corresponding-source offer/source and non-commercial restriction required by
the upstream components. A successful technical build is not a license grant.
