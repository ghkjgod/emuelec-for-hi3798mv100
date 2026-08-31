#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

OVERLAY="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec"
PACKAGE_ROOT="${HISTB_WORK_ROOT}/artifacts/tf-card"
CARD_ROOT="${PACKAGE_ROOT}/EmuELEC"
CORE_NAMES=(
  fceumm gambatte gpsp mgba picodrive snes9x2010 mednafen_pce_fast
  pcsx_rearmed fbneo mame2003_plus
)

case "${PACKAGE_ROOT}" in
  "${HISTB_WORK_ROOT}/artifacts/tf-card") ;;
  *) echo "unsafe TF package path: ${PACKAGE_ROOT}" >&2; exit 1 ;;
esac

for core in "${CORE_NAMES[@]}"; do
  binary="${OVERLAY}/lib/libretro/${core}_libretro.so"
  [[ -f "${binary}" ]] || { echo "missing TF core input: ${binary}" >&2; exit 1; }
  "${SCRIPT_DIR}/check-elf-abi.sh" "${binary}"
  if ! find "${OVERLAY}/share/licenses/libretro-cores/${core}" \
      -type f -print -quit | grep -q .; then
    echo "missing license material for TF core: ${core}" >&2
    exit 1
  fi
done
for required in \
    "${OVERLAY}/share/sdl/gamecontrollerdb.txt" \
    "${OVERLAY}/share/licenses/SDL_GameControllerDB/LICENSE"; do
  [[ -f "${required}" ]] || { echo "missing TF resource input: ${required}" >&2; exit 1; }
done

rm -rf -- "${PACKAGE_ROOT}"
install -d "${CARD_ROOT}/cores" "${CARD_ROOT}/config" \
  "${CARD_ROOT}/licenses/libretro-cores" \
  "${CARD_ROOT}/licenses/SDL_GameControllerDB"
for core in "${CORE_NAMES[@]}"; do
  install -m 0755 "${OVERLAY}/lib/libretro/${core}_libretro.so" \
    "${CARD_ROOT}/cores/"
  cp -a "${OVERLAY}/share/licenses/libretro-cores/${core}" \
    "${CARD_ROOT}/licenses/libretro-cores/"
done
install -m 0644 "${OVERLAY}/share/sdl/gamecontrollerdb.txt" \
  "${CARD_ROOT}/config/gamecontrollerdb.txt"
install -m 0644 "${OVERLAY}/share/licenses/SDL_GameControllerDB/LICENSE" \
  "${CARD_ROOT}/licenses/SDL_GameControllerDB/LICENSE"

(
  cd "${CARD_ROOT}/cores"
  sha256sum *_libretro.so | LC_ALL=C sort -k2 > cores.sha256
)
(
  cd "${CARD_ROOT}/config"
  sha256sum gamecontrollerdb.txt > gamecontrollerdb.sha256
)

cat >"${CARD_ROOT}/TF-PACKAGE-INFO.txt" <<'EOF'
target=EC6108V9C / Hi3798MV100
abi=ARMv7 EABI5 softfp, Cortex-A7, VFPv3-D16
core_count=10
snes_core=snes9x2010
contains_bios=0
contains_roms=0
controller_database=SDL_GameControllerDB af76f5b56a180aabf3553a8b2b1c0bb7022a3274
copy_scope=copy this EmuELEC directory to the TF card root, then add your licensed BIOS and ROM files
EOF
cat >"${PACKAGE_ROOT}/README.txt" <<'EOF'
Copy the EmuELEC directory to the root of a TF card.
This package contains ten Hi3798MV100 ARMv7 softfp cores, checksums,
controller mappings, and redistributable license files. It intentionally
contains no BIOS or ROM. Add your own licensed files under EmuELEC/bios and
EmuELEC/roms; see the repository README and docs/TF-CARD.md for exact paths.
EOF

if find "${PACKAGE_ROOT}" -type d \( -iname bios -o -iname roms \) -print -quit | grep -q .; then
  echo "TF package unexpectedly contains a BIOS/ROM directory" >&2
  exit 1
fi
core_count="$(find "${CARD_ROOT}/cores" -maxdepth 1 -type f -name '*_libretro.so' | wc -l)"
[[ "${core_count}" = "${#CORE_NAMES[@]}" ]] || {
  echo "unexpected TF package core count: ${core_count}" >&2
  exit 1
}
(
  cd "${PACKAGE_ROOT}"
  find . -type f ! -name MANIFEST.sha256 -print0 | LC_ALL=C sort -z | \
    xargs -0 sha256sum > MANIFEST.sha256
  sha256sum --check --status MANIFEST.sha256
)

printf 'PASS: copy-ready TF package: %s (10 cores, controller DB, no BIOS/ROM)\n' \
  "${PACKAGE_ROOT}"
