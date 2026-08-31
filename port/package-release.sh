#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

# Packaging is a gate, not just an archiver.  Re-stage maintained runtime
# files and re-check the target dependency closure so it cannot package stale
# or partially copied output.
"${SCRIPT_DIR}/stage-runtime.sh"
"${SCRIPT_DIR}/check-runtime-deps.sh"

OVERLAY="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec"
PACKAGE_ROOT="${HISTB_WORK_ROOT}/artifacts/releases"
STAGE_ROOT="${HISTB_WORK_ROOT}/build/release-package"
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${HISTB_EMUELEC_ROOT}" show -s --format=%ct HEAD)}"
RECIPE_SHA256="$(
  (
    cd "${HISTB_EMUELEC_ROOT}"
    find tools/histb -path 'tools/histb/.git' -prune -o -type f -print0 |
      LC_ALL=C sort -z | xargs -0 sha256sum
  ) | sha256sum | awk '{print $1}'
)"
BASE_REVISION="$(git -C "${HISTB_EMUELEC_ROOT}" rev-parse --short=12 HEAD)"
REVISION="${BASE_REVISION}-r${RECIPE_SHA256:0:12}"
SDK_REVISION="$(git -C "${HISTB_SDK_ROOT}" rev-parse HEAD)"
BUILD_DATE="$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y%m%dT%H%M%SZ)"
RELEASE_ID="histb-emuelec-${BUILD_DATE}-${REVISION}"
RELEASE_STAGE="${STAGE_ROOT}/${RELEASE_ID}"
ARCHIVE="${PACKAGE_ROOT}/${RELEASE_ID}.tar.gz"
ROOTFS_IMAGE="${HISTB_OUT_ROOT}/image/emmc_image/rootfs_6846M.ext4"
CORE_NAMES=(
  fceumm gambatte gpsp mgba picodrive snes9x2010 mednafen_pce_fast
  pcsx_rearmed fbneo mame2003_plus
)

case "${STAGE_ROOT}" in
  "${HISTB_WORK_ROOT}/build/"*) ;;
  *) echo "unsafe package staging path: ${STAGE_ROOT}" >&2; exit 1 ;;
esac

for required in \
    "${OVERLAY}/bin/emulationstation" \
    "${OVERLAY}/bin/retroarch" \
    "${OVERLAY}/bin/histb-core-probe" \
    "${OVERLAY}/bin/histb-runtime-exec" \
    "${OVERLAY}/bin/histb-sync-es-systems" \
    "${OVERLAY}/bin/histb-controller-db-select" \
    "${OVERLAY}/bin/run-emulationstation.sh" \
    "${OVERLAY}/bin/run-retroarch.sh" \
    "${OVERLAY}/bin/emuelec-utils" \
    "${OVERLAY}/share/emulationstation/themes/HiSTB-EmuELEC-carbon/nes/theme.xml" \
    "${OVERLAY}/share/emulationstation/themes/HiSTB-EmuELEC-carbon/mame/theme.xml" \
    "${OVERLAY}/share/sdl/gamecontrollerdb.txt" \
    "${OVERLAY}/share/licenses/SDL_GameControllerDB/LICENSE"; do
  if [[ ! -f "${required}" ]]; then
    echo "missing packaged runtime input: ${required}" >&2
    exit 1
  fi
done
for core in "${CORE_NAMES[@]}"; do
  required="${OVERLAY}/lib/libretro/${core}_libretro.so"
  if [[ ! -f "${required}" ]]; then
    echo "missing packaged libretro core: ${required}" >&2
    exit 1
  fi
done
for core in "${CORE_NAMES[@]}"; do
  if ! find "${OVERLAY}/share/licenses/libretro-cores/${core}" -type f -print -quit | grep -q .; then
    echo "missing staged license material for libretro core: ${core}" >&2
    exit 1
  fi
done
if [[ ! -f "${ROOTFS_IMAGE}" ]]; then
  echo "missing normalized rootfs image: ${ROOTFS_IMAGE}" >&2
  exit 1
fi
ROOTFS_SHA256="$(sha256sum "${ROOTFS_IMAGE}" | awk '{print $1}')"
SDK_CONFIG_SHA256="$(sha256sum "${HISTB_SDK_ROOT}/cfg.mak" | awk '{print $1}')"

rm -rf -- "${STAGE_ROOT}"
mkdir -p "${RELEASE_STAGE}/bin" "${RELEASE_STAGE}/lib/libretro" \
  "${RELEASE_STAGE}/etc" "${RELEASE_STAGE}/share"

install -m 0755 \
  "${OVERLAY}/bin/emulationstation" \
  "${OVERLAY}/bin/retroarch" \
  "${OVERLAY}/bin/histb-core-probe" \
  "${OVERLAY}/bin/histb-runtime-exec" \
  "${OVERLAY}/bin/histb-sync-es-systems" \
  "${OVERLAY}/bin/histb-controller-db-select" \
  "${OVERLAY}/bin/emuelec-utils" \
  "${OVERLAY}/bin/run-emulationstation.sh" \
  "${OVERLAY}/bin/run-retroarch.sh" \
  "${OVERLAY}/bin/histb-sdl2-smoke" \
  "${OVERLAY}/bin/histb-egl-smoke" \
  "${OVERLAY}/bin/histb-egl-gles1-smoke" \
  "${RELEASE_STAGE}/bin/"
cp -a "${OVERLAY}/bin/resources" "${RELEASE_STAGE}/bin/"
for core in "${CORE_NAMES[@]}"; do
  install -m 0755 "${OVERLAY}/lib/libretro/${core}_libretro.so" \
    "${RELEASE_STAGE}/lib/libretro/"
done
cp -a "${OVERLAY}/etc/." "${RELEASE_STAGE}/etc/"
cp -a "${OVERLAY}/share/emulationstation" "${RELEASE_STAGE}/share/"
cp -a "${OVERLAY}/share/retroarch" "${RELEASE_STAGE}/share/"
cp -a "${OVERLAY}/share/libretro" "${RELEASE_STAGE}/share/"
cp -a "${OVERLAY}/share/sdl" "${RELEASE_STAGE}/share/"
cp -a "${OVERLAY}/share/licenses" "${RELEASE_STAGE}/share/"

for pattern in \
    'libSDL2-2.0.so*' 'libSDL2_mixer-2.0.so*' 'libogg.so*' 'libvorbis.so*' \
    'libvorbisenc.so*' 'libvorbisfile.so*' 'libfreeimage*.so*' 'libcurl.so*'; do
  matches=("${OVERLAY}/lib/"${pattern})
  if [[ ! -e "${matches[0]}" && ! -L "${matches[0]}" ]]; then
    echo "missing runtime library family: ${pattern}" >&2
    exit 1
  fi
  cp -a "${matches[@]}" "${RELEASE_STAGE}/lib/"
done

broken_link="$(find -L "${RELEASE_STAGE}/lib" -maxdepth 2 -type l -print -quit)"
if [[ -n "${broken_link}" ]]; then
  echo "broken packaged library link: ${broken_link}" >&2
  exit 1
fi

cat > "${RELEASE_STAGE}/BUILD-INFO" <<EOF
release_id=${RELEASE_ID}
source_date_epoch=${SOURCE_DATE_EPOCH}
emuelec_port_revision=${REVISION}
recipe_sha256=${RECIPE_SHA256}
sdk_revision=${SDK_REVISION}
toolchain=$(${CC} -dumpversion)
target=hi3798mv100-hi3798mdmo1g
abi=ARMv7 EABI5 softfp
frontend=EmulationStation 2afe6efec4e09176882d98323bda5d3f664870a7
retroarch=ccbff758b46556407d1b9931a72cfcc46201276d
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
dropbear=2026.94
dropbear_source_sha256=e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81
joypad_autoconfig=033151045d378b64e712a92592467800d7924227
sdl_gamecontrollerdb=af76f5b56a180aabf3553a8b2b1c0bb7022a3274
libretro_core_info=f8c1149c628c13be63a6ea605f49f0a94fec1421
emuelec_carbon_theme=62509737c2f732b81ce7bf37f6c4c3b82dafae28
emuelec_carbon_theme_source_sha256=214bb1bb7245caa1a31cf6c28ffebb8c0bce24fd3b656890a5e9ea2428bdf97e
sdk_config_sha256=${SDK_CONFIG_SHA256}
rootfs_partition_sha256=${ROOTFS_SHA256}
rootfs_partition_logical_size=7178551296
storage_layout=p9-root-ext4
autostart_default=enabled
ssh_bind=opt-in-configured-address:22
EOF

(
  cd "${RELEASE_STAGE}"
  find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256
)

mkdir -p "${PACKAGE_ROOT}"
tar --sort=name --owner=0 --group=0 --numeric-owner \
  --mtime="@${SOURCE_DATE_EPOCH}" --clamp-mtime \
  -C "${STAGE_ROOT}" -czf "${ARCHIVE}" "${RELEASE_ID}"
(
  cd "${PACKAGE_ROOT}"
  sha256sum "$(basename "${ARCHIVE}")" > "$(basename "${ARCHIVE}").sha256"
)
install -m 0755 "${SCRIPT_DIR}/target/install-release.sh" "${PACKAGE_ROOT}/install-release.sh"
"${SCRIPT_DIR}/check-rootfs-image.sh" "${ARCHIVE}"

echo "Release archive: ${ARCHIVE}"
echo "Release checksum: ${ARCHIVE}.sha256"
echo "Target installer: ${PACKAGE_ROOT}/install-release.sh"
echo "Rootfs image audit: ${HISTB_WORK_ROOT}/artifacts/rootfs-image-audit.txt"
