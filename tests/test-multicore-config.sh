#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../env.sh
source "${HISTB_DIR}/env.sh" >/dev/null
CORE_NAMES=(
  quicknes snes9x2010 gambatte vba_next genesis_plus_gx
  mednafen_pce_fast pcsx_rearmed mame2003
)

bash -n "${HISTB_DIR}/build-libretro-cores.sh" \
  "${HISTB_DIR}/build-retroarch.sh" \
  "${HISTB_DIR}/stage-runtime.sh" \
  "${HISTB_DIR}/package-release.sh" \
  "${HISTB_DIR}/check-rootfs-image.sh"
sh -n "${HISTB_DIR}/runtime/bin/run-retroarch.sh" \
  "${HISTB_DIR}/runtime/bin/run-emulationstation.sh" \
  "${HISTB_DIR}/runtime/bin/emuelec-utils"
sh -n "${HISTB_DIR}/rootfs-overlay/emuelec/scripts/emuelec-utils"

for core in "${CORE_NAMES[@]}"; do
  grep -Fq "${core}" "${HISTB_DIR}/stage-runtime.sh"
  grep -Fq "${core}" "${HISTB_DIR}/package-release.sh"
  grep -Fq "${core}" "${HISTB_DIR}/check-rootfs-image.sh"
  grep -Fq "${core}" "${HISTB_DIR}/runtime/bin/run-retroarch.sh"
done

RETROARCH_BINARY="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec/bin/retroarch"
PCSX_BINARY="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec/lib/libretro/pcsx_rearmed_libretro.so"
for binary in "${RETROARCH_BINARY}" "${PCSX_BINARY}"; do
  [[ -f "${binary}" ]]
done
grep -aFq 'Built: Oct 20 2021' "${RETROARCH_BINARY}"
grep -aFq 'Oct 20 2021' "${PCSX_BINARY}"
for binary in "${RETROARCH_BINARY}" "${PCSX_BINARY}"; do
  unexpected_dates="$(
    grep -aoE '(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ 0-9][0-9] [0-9]{4}' \
      "${binary}" | grep -Fv 'Oct 20 2021' || true
  )"
  if [[ -n "${unexpected_dates}" ]]; then
    printf '%s\n' "${unexpected_dates}" >&2
    echo "non-deterministic build date remains in ${binary}" >&2
    exit 1
  fi
done
for core in "${CORE_NAMES[@]:1}"; do
  grep -Fq "${core}_libretro.so" "${HISTB_DIR}/build-libretro-cores.sh"
done

grep -Fxq 'input_driver = "sdl2"' "${HISTB_DIR}/retroarch-histb.cfg"
grep -Fxq 'input_joypad_driver = "sdl2"' "${HISTB_DIR}/retroarch-histb.cfg"
grep -Fxq 'midi_driver = "null"' "${HISTB_DIR}/retroarch-histb.cfg"
grep -Fq 'content_history_path' \
  "${HISTB_DIR}/runtime/bin/run-retroarch.sh"
grep -Fq 'content_favorites_path' \
  "${HISTB_DIR}/runtime/bin/run-retroarch.sh"
for rom_dir in nes snes gb gba megadrive pce psx arcade; do
  grep -Fq "roms/${rom_dir}" \
    "${HISTB_DIR}/runtime/bin/run-emulationstation.sh"
  grep -Fq "roms/${rom_dir}" \
    "${HISTB_DIR}/rootfs-overlay/usr/bin/histb-storage-init"
done
grep -Fq '${RUNTIME_SOURCE}/bin/emuelec-utils' "${HISTB_DIR}/stage-runtime.sh"
grep -Fq 'emuelec.conf' "${HISTB_DIR}/runtime/bin/run-emulationstation.sh"
grep -Fq '/usr/bin/histb-storage-guard --require-marker' \
  "${HISTB_DIR}/runtime/bin/emuelec-utils"
grep -Fq '/bin/emuelec-utils' "${HISTB_DIR}/rootfs-overlay/emuelec/scripts/emuelec-utils"
[[ "$(grep -Fc '${OVERLAY}/bin/emuelec-utils' "${HISTB_DIR}/package-release.sh")" = 2 ]]
grep -Fq 'libretro-core-info-' "${HISTB_DIR}/stage-runtime.sh"
grep -Fq 'share/libretro' "${HISTB_DIR}/package-release.sh"
grep -Fq 'rootfs_minimum_free_bytes' "${HISTB_DIR}/check-rootfs-image.sh"

DS4_GUID=030000004c050000cc09000011010000
DS4_NAME='Sony Computer Entertainment Wireless Controller'
DS4_AUTOCONFIG="${HISTB_DIR}/runtime/share/retroarch/autoconfig/sdl2/${DS4_NAME}.cfg"
grep -Fxq 'input_driver = "sdl2"' "${DS4_AUTOCONFIG}"
grep -Fxq "input_device = \"${DS4_NAME}\"" "${DS4_AUTOCONFIG}"
grep -Fxq 'input_vendor_id = "1356"' "${DS4_AUTOCONFIG}"
grep -Fxq 'input_product_id = "2508"' "${DS4_AUTOCONFIG}"
grep -Fxq 'input_b_btn = "1"' "${DS4_AUTOCONFIG}"
grep -Fxq 'input_a_btn = "2"' "${DS4_AUTOCONFIG}"
grep -Fxq 'input_r_x_plus_axis = "+2"' "${DS4_AUTOCONFIG}"
grep -Fxq 'input_r_y_plus_axis = "+5"' "${DS4_AUTOCONFIG}"
grep -Fq '${RUNTIME_SOURCE}/share/retroarch/autoconfig/sdl2/' \
  "${HISTB_DIR}/stage-runtime.sh"

XBOX_GUID=03000000373500000f10000000010000
XBOX_NAME='Generic X-Box pad'
XBOX_AUTOCONFIG="${HISTB_DIR}/runtime/share/retroarch/autoconfig/sdl2/${XBOX_NAME}.cfg"
grep -Fxq 'input_driver = "sdl2"' "${XBOX_AUTOCONFIG}"
grep -Fxq "input_device = \"${XBOX_NAME}\"" "${XBOX_AUTOCONFIG}"
grep -Fxq 'input_vendor_id = "13623"' "${XBOX_AUTOCONFIG}"
grep -Fxq 'input_product_id = "4111"' "${XBOX_AUTOCONFIG}"
grep -Fxq 'input_b_btn = "0"' "${XBOX_AUTOCONFIG}"
grep -Fxq 'input_a_btn = "1"' "${XBOX_AUTOCONFIG}"
grep -Fxq 'input_r_x_plus_axis = "+3"' "${XBOX_AUTOCONFIG}"
grep -Fxq 'input_r_y_plus_axis = "+4"' "${XBOX_AUTOCONFIG}"

python3 - "${HISTB_DIR}/runtime/etc/emulationstation/es_input.cfg" \
  "${DS4_GUID}" "${DS4_NAME}" "${XBOX_GUID}" "${XBOX_NAME}" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, ds4_guid, ds4_name, xbox_guid, xbox_name = sys.argv[1:]
root = ET.parse(path).getroot()
configs = root.findall("inputConfig")
if len(configs) != 2:
    raise SystemExit(f"unexpected input config count: {len(configs)}")
by_guid = {config.attrib.get("deviceGUID"): config for config in configs}
config = by_guid.get(ds4_guid)
if config is None or config.attrib != {"type": "joystick", "deviceName": ds4_name, "deviceGUID": ds4_guid}:
    raise SystemExit(f"unexpected DS4 identity: {None if config is None else config.attrib}")
mapping = {node.attrib["name"]: node.attrib for node in config.findall("input")}
expected = {
    "up": ("hat", "0", "1"),
    "down": ("hat", "0", "4"),
    "left": ("hat", "0", "8"),
    "right": ("hat", "0", "2"),
    "a": ("button", "1", "1"),
    "b": ("button", "2", "1"),
    "x": ("button", "0", "1"),
    "y": ("button", "3", "1"),
    "select": ("button", "8", "1"),
    "start": ("button", "9", "1"),
}
for key, (kind, ident, value) in expected.items():
    item = mapping.get(key)
    if not item or (item.get("type"), item.get("id"), item.get("value")) != (kind, ident, value):
        raise SystemExit(f"{key}: unexpected mapping {item}")

config = by_guid.get(xbox_guid)
if config is None or config.attrib != {"type": "joystick", "deviceName": xbox_name, "deviceGUID": xbox_guid}:
    raise SystemExit(f"unexpected Xbox identity: {None if config is None else config.attrib}")
mapping = {node.attrib["name"]: node.attrib for node in config.findall("input")}
expected = {
    "up": ("hat", "0", "1"),
    "down": ("hat", "0", "4"),
    "left": ("hat", "0", "8"),
    "right": ("hat", "0", "2"),
    "a": ("button", "0", "1"),
    "b": ("button", "1", "1"),
    "x": ("button", "2", "1"),
    "y": ("button", "3", "1"),
    "select": ("button", "6", "1"),
    "start": ("button", "7", "1"),
    "hotkeyenable": ("button", "8", "1"),
}
for key, (kind, ident, value) in expected.items():
    item = mapping.get(key)
    if not item or (item.get("type"), item.get("id"), item.get("value")) != (kind, ident, value):
        raise SystemExit(f"Xbox {key}: unexpected mapping {item}")
PY

grep -Fq 'RetroArch-Reproducible-Build-Date.patch' \
  "${HISTB_DIR}/build-retroarch.sh"
grep -Fq 'PCSX-ReARMed-Reproducible-Build-Date.patch' \
  "${HISTB_DIR}/build-libretro-cores.sh"
for patch in \
  "${HISTB_DIR}/patches/RetroArch-Reproducible-Build-Date.patch" \
  "${HISTB_DIR}/patches/PCSX-ReARMed-Reproducible-Build-Date.patch"; do
  grep -Fq 'Oct 20 2021' "${patch}"
  if grep -E '^\+.*__(DATE|TIME)__' "${patch}"; then
    echo "reproducible date patch still adds a wall-clock macro: ${patch}" >&2
    exit 1
  fi
done

grep -Fq 'EmulationStation-OptionalSplash-HiSTB.patch' "${HISTB_DIR}/build-emulationstation.sh"
grep -Fq 'path == ":/splash.xml" || path == ":/gamesplash.xml"' \
  "${HISTB_DIR}/patches/EmulationStation-OptionalSplash-HiSTB.patch"

python3 - "${HISTB_DIR}/runtime/etc/emulationstation/es_systems.cfg" <<'PY'
import sys
import xml.etree.ElementTree as ET

expected = {
    "nes": "quicknes",
    "snes": "snes9x2010",
    "gb": "gambatte",
    "gba": "vba_next",
    "megadrive": "genesis_plus_gx",
    "pce": "mednafen_pce_fast",
    "psx": "pcsx_rearmed",
    "arcade": "mame2003",
    "diagnostics": None,
}
root = ET.parse(sys.argv[1]).getroot()
systems = {node.findtext("name"): node for node in root.findall("system")}
if set(systems) != set(expected):
    raise SystemExit(f"unexpected ES systems: {sorted(systems)}")
for name, core in expected.items():
    command = systems[name].findtext("command") or ""
    if core is None:
        wanted = '/bin/sh %ROM%'
    else:
        wanted = f'run-retroarch.sh {core} %ROM%'
    if wanted not in command:
        raise SystemExit(f"{name}: missing command fragment {wanted!r}")
PY

python3 -B "${SCRIPT_DIR}/test-es-command-argv.py" \
  "${HISTB_DIR}/runtime/etc/emulationstation/es_systems.cfg"

printf '%s\n' 'PASS: eight-core build, package, launcher, ES mappings, and controller profiles'
