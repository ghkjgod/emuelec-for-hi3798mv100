#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

OVERLAY="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec"
RUNTIME_SOURCE="${SCRIPT_DIR}/runtime"
EGL_ARTIFACTS="${HISTB_WORK_ROOT}/artifacts/egl-smoke"
AUTOCONFIG_REPO="${HISTB_WORK_ROOT}/cache/sources/retroarch-joypad-autoconfig.git"
AUTOCONFIG_COMMIT="033151045d378b64e712a92592467800d7924227"
CORE_INFO_COMMIT="f8c1149c628c13be63a6ea605f49f0a94fec1421"
CORE_INFO_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/libretro-core-info-${CORE_INFO_COMMIT}.tar.gz"
CORE_INFO_SHA256="0dbe5fd3a0b8a56b6c487b5c64e4258cb12a093d086c3c51220b514bf69e4344"
CORE_INFO_WORK="${HISTB_WORK_ROOT}/build/libretro-core-info"
CONTROLLER_DB_COMMIT="af76f5b56a180aabf3553a8b2b1c0bb7022a3274"
CONTROLLER_DB_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/SDL_GameControllerDB-${CONTROLLER_DB_COMMIT}.tar.gz"
CONTROLLER_DB_SHA256="b3fd72a383bf03077164ee4619d56836f91458e1df8a1675e1489b8396c74e8f"
CONTROLLER_DB_WORK="${HISTB_WORK_ROOT}/build/SDL_GameControllerDB"
THEME_COMMIT="62509737c2f732b81ce7bf37f6c4c3b82dafae28"
THEME_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/es-theme-EmuELEC-carbon-${THEME_COMMIT}.tar.gz"
THEME_SHA256="214bb1bb7245caa1a31cf6c28ffebb8c0bce24fd3b656890a5e9ea2428bdf97e"
THEME_WORK="${HISTB_WORK_ROOT}/build/es-theme-EmuELEC-carbon"
THEME_DEST="${OVERLAY}/share/emulationstation/themes/HiSTB-EmuELEC-carbon"
CORE_NAMES=(
  fceumm gambatte gpsp mgba picodrive snes9x2010 mednafen_pce_fast
  pcsx_rearmed fbneo mame2003_plus
)

if [[ ! -d "${AUTOCONFIG_REPO}/.git" ]] ||
   ! git -C "${AUTOCONFIG_REPO}" cat-file -e "${AUTOCONFIG_COMMIT}^{commit}" 2>/dev/null; then
  echo "missing pinned RetroArch joypad profiles: ${AUTOCONFIG_REPO}@${AUTOCONFIG_COMMIT}" >&2
  exit 1
fi

for required in \
    "${OVERLAY}/bin/emulationstation" \
    "${OVERLAY}/bin/retroarch" \
    "${OVERLAY}/bin/histb-sdl2-smoke" \
    "${EGL_ARTIFACTS}/histb-egl-smoke" \
    "${EGL_ARTIFACTS}/histb-egl-gles1-smoke"; do
  if [[ ! -f "${required}" ]]; then
    echo "missing runtime input: ${required}" >&2
    exit 1
  fi
done
for core in "${CORE_NAMES[@]}"; do
  required="${OVERLAY}/lib/libretro/${core}_libretro.so"
  if [[ ! -f "${required}" ]]; then
    echo "missing runtime core: ${required}" >&2
    exit 1
  fi
done
core_count="$(find "${OVERLAY}/lib/libretro" -maxdepth 1 -type f \
  -name '*_libretro.so' | wc -l)"
[[ "${core_count}" = "${#CORE_NAMES[@]}" ]] || {
  echo "unexpected staged libretro core count: ${core_count}" >&2
  exit 1
}

[[ -f "${CORE_INFO_ARCHIVE}" ]] || {
  echo "missing pinned libretro core-info archive: ${CORE_INFO_ARCHIVE}" >&2
  exit 1
}
printf '%s  %s\n' "${CORE_INFO_SHA256}" "${CORE_INFO_ARCHIVE}" |
  sha256sum --check --status || {
    echo "libretro core-info checksum mismatch" >&2
    exit 1
  }
case "${CORE_INFO_WORK}" in
  "${HISTB_WORK_ROOT}/build/"*) rm -rf -- "${CORE_INFO_WORK}" ;;
  *) echo "unsafe core-info work path: ${CORE_INFO_WORK}" >&2; exit 1 ;;
esac
mkdir -p "${CORE_INFO_WORK}"
tar -xzf "${CORE_INFO_ARCHIVE}" -C "${CORE_INFO_WORK}"
CORE_INFO_SOURCE="${CORE_INFO_WORK}/libretro-core-info-${CORE_INFO_COMMIT}"

[[ -f "${CONTROLLER_DB_ARCHIVE}" ]] || {
  echo "missing pinned SDL controller database archive: ${CONTROLLER_DB_ARCHIVE}" >&2
  exit 1
}
printf '%s  %s\n' "${CONTROLLER_DB_SHA256}" "${CONTROLLER_DB_ARCHIVE}" |
  sha256sum --check --status || {
    echo "SDL controller database checksum mismatch" >&2
    exit 1
  }
case "${CONTROLLER_DB_WORK}" in
  "${HISTB_WORK_ROOT}/build/"*) rm -rf -- "${CONTROLLER_DB_WORK}" ;;
  *) echo "unsafe controller database work path: ${CONTROLLER_DB_WORK}" >&2; exit 1 ;;
esac
mkdir -p "${CONTROLLER_DB_WORK}"
tar -xzf "${CONTROLLER_DB_ARCHIVE}" -C "${CONTROLLER_DB_WORK}"
CONTROLLER_DB_SOURCE="${CONTROLLER_DB_WORK}/mdqinc-SDL_GameControllerDB-af76f5b"
[[ -f "${CONTROLLER_DB_SOURCE}/gamecontrollerdb.txt" && \
   -f "${CONTROLLER_DB_SOURCE}/LICENSE" ]] || {
  echo "SDL controller database archive lacks data or license" >&2
  exit 1
}
awk '
  /^[[:space:]]*($|#)/ { next }
  /^xinput,[^,]+,/ { next }
  {
    comma=index($0, ","); guid=substr($0, 1, comma - 1)
    if (comma > 1 && length(guid) == 32 && guid !~ /[^0-9a-fA-F]/ &&
        substr($0, comma + 1) ~ /^[^,]+,/) {
      mappings++; if (index($0, "platform:Linux") != 0) linux++; next
    }
  }
  { bad=1 }
  END { exit (bad || mappings == 0 || linux == 0) ? 1 : 0 }
' "${CONTROLLER_DB_SOURCE}/gamecontrollerdb.txt" || {
  echo "pinned SDL controller database failed syntax validation" >&2
  exit 1
}

[[ -f "${THEME_ARCHIVE}" ]] || {
  echo "missing pinned EmuELEC Carbon theme archive: ${THEME_ARCHIVE}" >&2
  exit 1
}
printf '%s  %s\n' "${THEME_SHA256}" "${THEME_ARCHIVE}" |
  sha256sum --check --status || {
    echo "EmuELEC Carbon theme checksum mismatch" >&2
    exit 1
  }
if ! tar -tzf "${THEME_ARCHIVE}" | awk -v prefix="es-theme-EmuELEC-carbon-${THEME_COMMIT}/" '
  index($0, prefix) != 1 || $0 ~ /(^|\/)\.\.($|\/)/ { bad=1 }
  END { exit bad ? 1 : 0 }
'; then
  echo "EmuELEC Carbon theme archive contains an unsafe path" >&2
  exit 1
fi
case "${THEME_WORK}" in
  "${HISTB_WORK_ROOT}/build/"*) rm -rf -- "${THEME_WORK}" ;;
  *) echo "unsafe theme work path: ${THEME_WORK}" >&2; exit 1 ;;
esac
mkdir -p "${THEME_WORK}"
tar -xzf "${THEME_ARCHIVE}" -C "${THEME_WORK}"
THEME_SOURCE="${THEME_WORK}/es-theme-EmuELEC-carbon-${THEME_COMMIT}"
for theme_system in nes snes gb gba megadrive pcengine psx mame ports; do
  [[ -f "${THEME_SOURCE}/${theme_system}/theme.xml" ]] || {
    echo "compatible Carbon theme is missing ${theme_system}/theme.xml" >&2
    exit 1
  }
done

install -d "${OVERLAY}/bin" "${OVERLAY}/etc/emulationstation" \
  "${OVERLAY}/share/emulationstation/diagnostics" \
  "${OVERLAY}/share/retroarch/autoconfig" \
  "${OVERLAY}/share/libretro/info" "${OVERLAY}/share/sdl" \
  "${OVERLAY}/share/licenses/SDL_GameControllerDB"
install -m 0755 "${RUNTIME_SOURCE}/bin/histb-runtime-exec" \
  "${OVERLAY}/bin/histb-runtime-exec"
install -m 0755 "${RUNTIME_SOURCE}/bin/emuelec-utils" \
  "${OVERLAY}/bin/emuelec-utils"
install -m 0755 "${RUNTIME_SOURCE}/bin/run-emulationstation.sh" \
  "${OVERLAY}/bin/run-emulationstation.sh"
install -m 0755 "${RUNTIME_SOURCE}/bin/histb-sync-es-systems" \
  "${OVERLAY}/bin/histb-sync-es-systems"
install -m 0755 "${RUNTIME_SOURCE}/bin/histb-controller-db-select" \
  "${OVERLAY}/bin/histb-controller-db-select"
install -m 0755 "${RUNTIME_SOURCE}/bin/run-retroarch.sh" \
  "${OVERLAY}/bin/run-retroarch.sh"
install -m 0644 "${SCRIPT_DIR}/retroarch-histb.cfg" \
  "${OVERLAY}/etc/retroarch.cfg"
install -m 0644 "${RUNTIME_SOURCE}/etc/emulationstation/es_systems.cfg" \
  "${OVERLAY}/etc/emulationstation/es_systems.cfg"
install -m 0644 "${RUNTIME_SOURCE}/etc/emulationstation/es_input.cfg" \
  "${OVERLAY}/etc/emulationstation/es_input.cfg"
install -m 0644 "${CONTROLLER_DB_SOURCE}/gamecontrollerdb.txt" \
  "${OVERLAY}/share/sdl/gamecontrollerdb.txt"
install -m 0644 "${CONTROLLER_DB_SOURCE}/LICENSE" \
  "${OVERLAY}/share/licenses/SDL_GameControllerDB/LICENSE"
install -m 0755 "${RUNTIME_SOURCE}/share/emulationstation/diagnostics/"*.sh \
  "${OVERLAY}/share/emulationstation/diagnostics/"
case "${THEME_DEST}" in
  "${OVERLAY}/share/emulationstation/themes/"*) rm -rf -- "${THEME_DEST}" ;;
  *) echo "unsafe staged theme path: ${THEME_DEST}" >&2; exit 1 ;;
esac
install -d "$(dirname "${THEME_DEST}")"
cp -a "${THEME_SOURCE}" "${THEME_DEST}"
install -m 0755 "${EGL_ARTIFACTS}/histb-egl-smoke" \
  "${OVERLAY}/bin/histb-egl-smoke"
install -m 0755 "${EGL_ARTIFACTS}/histb-egl-gles1-smoke" \
  "${OVERLAY}/bin/histb-egl-gles1-smoke"

rm -f -- "${OVERLAY}/share/libretro/info/"*.info
for core in "${CORE_NAMES[@]}"; do
  info="${CORE_INFO_SOURCE}/${core}_libretro.info"
  [[ -f "${info}" ]] || {
    echo "missing pinned core metadata: ${info}" >&2
    exit 1
  }
  install -m 0644 "${info}" "${OVERLAY}/share/libretro/info/"
done

rm -rf -- "${OVERLAY}/share/retroarch/autoconfig/sdl2"
git -C "${AUTOCONFIG_REPO}" archive "${AUTOCONFIG_COMMIT}" sdl2 |
  tar -x -C "${OVERLAY}/share/retroarch/autoconfig"
install -m 0644 "${RUNTIME_SOURCE}/share/retroarch/autoconfig/sdl2/"*.cfg \
  "${OVERLAY}/share/retroarch/autoconfig/sdl2/"
if ! find "${OVERLAY}/share/retroarch/autoconfig/sdl2" -type f -name '*.cfg' \
    -print -quit | grep -q .; then
  echo "pinned SDL2 joypad profile set is empty" >&2
  exit 1
fi

# The SDK rootbox consumes this overlay directly.  Keep only target runtime
# content so headers, pkg-config metadata, libtool files, and non-deterministic
# static archives cannot leak into the rootfs partition.
rm -rf -- "${OVERLAY}/include" "${OVERLAY}/lib/pkgconfig" \
  "${OVERLAY}/share/aclocal"
rm -f -- "${OVERLAY}/bin/sdl2-config" "${OVERLAY}/lib/"*.a \
  "${OVERLAY}/lib/"*.la

broken_link="$(find -L "${OVERLAY}/lib" -maxdepth 2 -type l -print -quit)"
if [[ -n "${broken_link}" ]]; then
  echo "broken runtime library link: ${broken_link}" >&2
  exit 1
fi

for binary in \
    "${OVERLAY}/bin/emulationstation" \
    "${OVERLAY}/bin/retroarch" \
    "${OVERLAY}/bin/histb-sdl2-smoke" \
    "${OVERLAY}/bin/histb-egl-smoke" \
    "${OVERLAY}/bin/histb-egl-gles1-smoke"; do
  "${SCRIPT_DIR}/check-elf-abi.sh" "${binary}"
done

for core in "${CORE_NAMES[@]}"; do
  "${SCRIPT_DIR}/check-elf-abi.sh" \
    "${OVERLAY}/lib/libretro/${core}_libretro.so"
done

while IFS= read -r library; do
  "${SCRIPT_DIR}/check-elf-abi.sh" "${library}"
done < <(find "${OVERLAY}/lib" -maxdepth 1 -type f \
  \( -name 'libSDL2-2.0.so*' -o -name 'libSDL2_mixer*.so*' \
     -o -name 'libogg.so*' -o -name 'libvorbis*.so*' \
     -o -name 'libfreeimage*.so*' -o -name 'libcurl.so*' \) | sort)

# Keep an identity record inside the rootfs itself.  The release package adds
# the final sparse-image checksum later, but that checksum cannot be embedded
# in the filesystem it hashes.  This deterministic subset is enough for live
# target tooling to bind evidence to the exact public recipe and core set.
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${HISTB_EMUELEC_ROOT}" show -s --format=%ct HEAD)}"
RUNTIME_RECIPE_SHA256="$(
  (
    cd "${HISTB_EMUELEC_ROOT}"
    find tools/histb -path 'tools/histb/.git' -prune -o -type f -print0 |
      LC_ALL=C sort -z | xargs -0 sha256sum
  ) | sha256sum | awk '{print $1}'
)"
cat >"${OVERLAY}/BUILD-INFO" <<EOF
kind=rootfs-runtime
source_date_epoch=${SOURCE_DATE_EPOCH}
recipe_sha256=${RUNTIME_RECIPE_SHA256}
target=hi3798mv100-hi3798mdmo1g
abi=ARMv7 EABI5 softfp
fceumm=236ccdfc911e84c60fea6b9d0699c2d440a8de14
gambatte=d9d6cd06382d1ced30de34d56d3609452323dab1
gpsp=8d268a6bb2cd799f8f2791ebb544a7ef550cfc6f
mgba=c65e8a3d4666b0ea68a01578232452f31b185332
picodrive=733c711a477a642fd2006d5a7a581b2790ec36b4
snes9x2010=7db129b1ecdccb38cb4d7184bcbed39beed79656
mednafen_pce_fast=2f623abd033257b969370b73d9da982dcb0c3fdd
pcsx_rearmed=ba61a4fdee1f789e8012f205f1b63826667644fa
fbneo=26f11fa9e43227a04953e20e8c7e4bf322cd53cb
mame2003_plus=21256d24120b04916c5197d95b757635ca880fd9
sdl_gamecontrollerdb=af76f5b56a180aabf3553a8b2b1c0bb7022a3274
EOF

echo "Runtime launchers and minimum configuration staged at ${OVERLAY}"
