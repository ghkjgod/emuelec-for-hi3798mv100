#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "usage: $0 RELEASE.tar.gz" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null
# shellcheck source=rootfs-image-lib.sh
source "${SCRIPT_DIR}/rootfs-image-lib.sh"
histb_prepare_sparse_tools

ARCHIVE="$(readlink -m "$1")"
ROOTFS_LOGICAL_SIZE=7178551296
SPARSE_IMAGE="${HISTB_OUT_ROOT}/image/emmc_image/rootfs_6846M.ext4"
AUDIT_ROOT="${HISTB_WORK_ROOT}/build/rootfs-image-audit"
RAW_IMAGE="${AUDIT_ROOT}/rootfs.raw.ext4"
IMAGE_DUMP_ROOT="${AUDIT_ROOT}/image"
PACKAGE_DUMP_ROOT="${AUDIT_ROOT}/package"
REPORT="${HISTB_WORK_ROOT}/artifacts/rootfs-image-audit.txt"
RELEASE_ID="$(basename "${ARCHIVE}" .tar.gz)"
MIN_ROOTFS_FREE_BYTES=6442450944
CORE_NAMES=(
  fceumm gambatte gpsp mgba picodrive snes9x2010 mednafen_pce_fast
  pcsx_rearmed fbneo mame2003_plus
)

case "${AUDIT_ROOT}" in "${HISTB_WORK_ROOT}/build/"*) ;; *)
  echo "unsafe rootfs audit directory: ${AUDIT_ROOT}" >&2
  exit 1
  ;;
esac
[[ -f "${ARCHIVE}" && -f "${ARCHIVE}.sha256" ]] || {
  echo "release archive or checksum is missing: ${ARCHIVE}" >&2
  exit 1
}
[[ -f "${SPARSE_IMAGE}" ]] || {
  echo "normalized sparse rootfs is missing: ${SPARSE_IMAGE}" >&2
  exit 1
}
(
  cd "$(dirname "${ARCHIVE}")"
  sha256sum -c "$(basename "${ARCHIVE}.sha256")"
)
if ! tar -tzf "${ARCHIVE}" | awk -v prefix="${RELEASE_ID}/" '
  index($0, prefix) != 1 || $0 ~ /(^|\/)\.\.($|\/)/ { bad=1 }
  END { exit bad ? 1 : 0 }
'; then
  echo "release archive contains an unsafe path" >&2
  exit 1
fi

rm -rf -- "${AUDIT_ROOT}"
mkdir -p "${IMAGE_DUMP_ROOT}" "${PACKAGE_DUMP_ROOT}"
cleanup()
{
  rm -rf -- "${AUDIT_ROOT}"
}
trap cleanup EXIT HUP INT TERM

"${HISTB_SIMG2IMG}" "${SPARSE_IMAGE}" "${RAW_IMAGE}"
[[ "$(stat -c %s "${RAW_IMAGE}")" = "${ROOTFS_LOGICAL_SIZE}" ]]
e2fsck -fn "${RAW_IMAGE}"

debugfs -R "rdump /opt/emuelec ${IMAGE_DUMP_ROOT}" "${RAW_IMAGE}" >/dev/null 2>&1
IMAGE_RUNTIME="${IMAGE_DUMP_ROOT}/emuelec"
[[ -x "${IMAGE_RUNTIME}/bin/emulationstation" ]]
[[ -x "${IMAGE_RUNTIME}/bin/retroarch" ]]
[[ -f "${IMAGE_RUNTIME}/BUILD-INFO" ]]
grep -qx 'kind=rootfs-runtime' "${IMAGE_RUNTIME}/BUILD-INFO"
grep -qx 'target=hi3798mv100-hi3798mdmo1g' "${IMAGE_RUNTIME}/BUILD-INFO"
grep -qx 'abi=ARMv7 EABI5 softfp' "${IMAGE_RUNTIME}/BUILD-INFO"
[[ -x "${IMAGE_RUNTIME}/bin/histb-core-probe" ]]
[[ -x "${IMAGE_RUNTIME}/bin/histb-runtime-exec" ]]
[[ -x "${IMAGE_RUNTIME}/bin/histb-controller-db-select" ]]
[[ -x "${IMAGE_RUNTIME}/bin/emuelec-utils" ]]
[[ -f "${IMAGE_RUNTIME}/share/sdl/gamecontrollerdb.txt" ]]
grep -aFq 'HISTB_GAMECONTROLLERDB' "${IMAGE_RUNTIME}/bin/emulationstation"
grep -aFq 'SDL controller mappings from' "${IMAGE_RUNTIME}/bin/emulationstation"
[[ -f "${IMAGE_RUNTIME}/share/licenses/SDL_GameControllerDB/LICENSE" ]]
for theme_system in nes snes gb gba megadrive pcengine psx mame ports; do
  [[ -f "${IMAGE_RUNTIME}/share/emulationstation/themes/HiSTB-EmuELEC-carbon/${theme_system}/theme.xml" ]] || {
    echo "rootfs is missing compatible Carbon theme for: ${theme_system}" >&2
    exit 1
  }
done
for core in "${CORE_NAMES[@]}"; do
  [[ -f "${IMAGE_RUNTIME}/lib/libretro/${core}_libretro.so" ]] || {
    echo "rootfs is missing libretro core: ${core}" >&2
    exit 1
  }
done
for core in "${CORE_NAMES[@]}"; do
  if ! find "${IMAGE_RUNTIME}/share/licenses/libretro-cores/${core}" -type f -print -quit | grep -q .; then
    echo "rootfs is missing license material for libretro core: ${core}" >&2
    exit 1
  fi
done
core_count="$(find "${IMAGE_RUNTIME}/lib/libretro" -maxdepth 1 -type f \
  -name '*_libretro.so' | wc -l)"
[[ "${core_count}" = "${#CORE_NAMES[@]}" ]] || {
  echo "unexpected libretro core count in rootfs: ${core_count}" >&2
  exit 1
}
info_count="$(find "${IMAGE_RUNTIME}/share/libretro/info" -maxdepth 1 \
  -type f -name '*_libretro.info' | wc -l)"
[[ "${info_count}" = "${#CORE_NAMES[@]}" ]] || {
  echo "unexpected libretro core-info count in rootfs: ${info_count}" >&2
  exit 1
}
[[ -z "$(find -L "${IMAGE_RUNTIME}/lib" -type l -print -quit)" ]]

tar -xzf "${ARCHIVE}" -C "${PACKAGE_DUMP_ROOT}"
PACKAGE_RUNTIME="${PACKAGE_DUMP_ROOT}/${RELEASE_ID}"
(
  cd "${PACKAGE_RUNTIME}"
  sha256sum --quiet -c MANIFEST.sha256
)
runtime_recipe_sha="$(awk -F= '$1 == "recipe_sha256" { print $2; count++ } END { if (count != 1) exit 1 }' \
  "${IMAGE_RUNTIME}/BUILD-INFO")"
package_recipe_sha="$(awk -F= '$1 == "recipe_sha256" { print $2; count++ } END { if (count != 1) exit 1 }' \
  "${PACKAGE_RUNTIME}/BUILD-INFO")"
[[ "${runtime_recipe_sha}" = "${package_recipe_sha}" ]] || {
  echo "rootfs runtime recipe differs from release recipe" >&2
  exit 1
}
grep -v '  \./BUILD-INFO$' "${PACKAGE_RUNTIME}/MANIFEST.sha256" \
  >"${AUDIT_ROOT}/runtime-subset.sha256"
(
  cd "${IMAGE_RUNTIME}"
  sha256sum --quiet -c "${AUDIT_ROOT}/runtime-subset.sha256"
)
while IFS= read -r -d '' package_link; do
  relative_link="${package_link#${PACKAGE_RUNTIME}/}"
  image_link="${IMAGE_RUNTIME}/${relative_link}"
  [[ -L "${image_link}" ]] || {
    echo "rootfs is missing packaged symlink: ${relative_link}" >&2
    exit 1
  }
  [[ "$(readlink "${package_link}")" = "$(readlink "${image_link}")" ]] || {
    echo "rootfs symlink differs from package: ${relative_link}" >&2
    exit 1
  }
done < <(find "${PACKAGE_RUNTIME}" -type l -print0)

rootfs_sha="$(sha256sum "${SPARSE_IMAGE}" | awk '{print $1}')"
free_blocks="$(dumpe2fs -h "${RAW_IMAGE}" 2>/dev/null |
  awk -F: '/^Free blocks:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }')"
block_size="$(dumpe2fs -h "${RAW_IMAGE}" 2>/dev/null |
  awk -F: '/^Block size:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }')"
[[ "${free_blocks}" =~ ^[0-9]+$ && "${block_size}" =~ ^[0-9]+$ ]]
rootfs_free_bytes=$((free_blocks * block_size))
(( rootfs_free_bytes >= MIN_ROOTFS_FREE_BYTES )) || {
  echo "rootfs free space is below ${MIN_ROOTFS_FREE_BYTES} bytes: ${rootfs_free_bytes}" >&2
  exit 1
}
grep -qx "rootfs_partition_sha256=${rootfs_sha}" "${PACKAGE_RUNTIME}/BUILD-INFO"
profile_count="$(find "${IMAGE_RUNTIME}/share/retroarch/autoconfig/sdl2" \
  -type f -name '*.cfg' | wc -l)"
[[ "${profile_count}" = 82 ]] || {
  echo "unexpected SDL2 controller profile count in rootfs: ${profile_count}" >&2
  exit 1
}

dump_and_compare()
{
  local image_path=$1 source_path=$2 destination
  destination="${AUDIT_ROOT}/integration${image_path}"
  mkdir -p "$(dirname "${destination}")"
  debugfs -R "dump -p ${image_path} ${destination}" "${RAW_IMAGE}" >/dev/null 2>&1
  cmp "${source_path}" "${destination}"
  [[ -x "${destination}" ]] || {
    echo "rootfs integration file is not executable: ${image_path}" >&2
    return 1
  }
}

dump_and_compare /etc/init.d/S90modules \
  "${SCRIPT_DIR}/rootfs-overlay/etc/init.d/S90modules"
dump_and_compare /etc/init.d/S81histb-network \
  "${SCRIPT_DIR}/rootfs-overlay/etc/init.d/S81histb-network"
dump_and_compare /etc/init.d/S82dropbear \
  "${SCRIPT_DIR}/rootfs-overlay/etc/init.d/S82dropbear"
dump_and_compare /etc/init.d/S91histb-tf-storage \
  "${SCRIPT_DIR}/rootfs-overlay/etc/init.d/S91histb-tf-storage"
dump_and_compare /etc/init.d/S95emuelec \
  "${SCRIPT_DIR}/rootfs-overlay/etc/init.d/S95emuelec"
for helper in histb-emuelec-stop histb-emuelec-supervisor histb-manual-smoke \
  histb-preflight histb-release-rollback histb-run-retroarch histb-storage-init \
  histb-storage-guard histb-tf-storage histb-tf-core-select; do
  dump_and_compare "/usr/bin/${helper}" \
    "${SCRIPT_DIR}/rootfs-overlay/usr/bin/${helper}"
done
dump_and_compare /usr/bin/histb-install-release \
  "${SCRIPT_DIR}/target/install-release.sh"
dump_and_compare /emuelec/scripts/emuelec-utils \
  "${SCRIPT_DIR}/rootfs-overlay/emuelec/scripts/emuelec-utils"

dropbear_image="${AUDIT_ROOT}/integration/usr/sbin/dropbear"
dropbear_build="${HISTB_WORK_ROOT}/build/dropbear-2026.94/output/dropbearmulti"
mkdir -p "$(dirname "${dropbear_image}")"
debugfs -R "dump -p /usr/sbin/dropbear ${dropbear_image}" "${RAW_IMAGE}" >/dev/null 2>&1
cmp "${dropbear_build}" "${dropbear_image}"
"${SCRIPT_DIR}/check-elf-abi.sh" "${dropbear_image}"
debugfs -R 'stat /usr/bin/dropbearkey' "${RAW_IMAGE}" 2>/dev/null |
  grep -Fq 'Fast link dest: "../sbin/dropbear"'

inittab="${AUDIT_ROOT}/integration/etc/inittab"
mkdir -p "$(dirname "${inittab}")"
debugfs -R "dump -p /etc/inittab ${inittab}" "${RAW_IMAGE}" >/dev/null 2>&1
[[ "$(grep -c '^::shutdown:/usr/bin/histb-emuelec-stop$' "${inittab}")" = 1 ]]
stop_line="$(grep -n '^::shutdown:/usr/bin/histb-emuelec-stop$' "${inittab}" | cut -d: -f1)"
umount_line="$(grep -n '^::shutdown:/bin/umount -a -r$' "${inittab}" | cut -d: -f1)"
(( stop_line < umount_line )) || {
  echo "HiSTB stop hook is not before rootfs unmount" >&2
  exit 1
}

debugfs -R "rdump /storage ${IMAGE_DUMP_ROOT}" "${RAW_IMAGE}" >/dev/null 2>&1
[[ -f "${IMAGE_DUMP_ROOT}/storage/ee/README.txt" ]]
[[ -f "${IMAGE_DUMP_ROOT}/storage/ee/enable-autostart" ]]
[[ ! -e "${IMAGE_DUMP_ROOT}/storage/ee/disable-autostart" ]]
grep -qx 'histb-emuelec-storage-v1' \
  "${IMAGE_DUMP_ROOT}/storage/.histb-emuelec-storage-v1"
grep -Fq '"${STATE_ROOT}/enable-autostart"' \
  "${AUDIT_ROOT}/integration/etc/init.d/S95emuelec"

p9_marker="${AUDIT_ROOT}/integration/etc/histb-emuelec-p9-root-storage-v1"
debugfs -R "dump -p /etc/histb-emuelec-p9-root-storage-v1 ${p9_marker}" \
  "${RAW_IMAGE}" >/dev/null 2>&1
grep -qx 'histb-emuelec-p9-root-storage-v1' "${p9_marker}"
grep -Fq 'HISTB_ENABLE_NETWORK' \
  "${AUDIT_ROOT}/integration/etc/init.d/S81histb-network"
grep -Fq 'HISTB_ENABLE_SSH' \
  "${AUDIT_ROOT}/integration/etc/init.d/S82dropbear"

TEST_ROM_ROOT="${IMAGE_DUMP_ROOT}/storage/roms/nes"
TEST_ROM="${TEST_ROM_ROOT}/240p Test Mini v0.23.nes"
TEST_ROM_LICENSE="${TEST_ROM_ROOT}/240p Test Mini v0.23.LICENSE.txt"
TEST_ROM_SOURCE="${TEST_ROM_ROOT}/240p Test Mini v0.23.SOURCE.txt"
if [[ -f "${TEST_ROM}" ]]; then
  [[ -f "${TEST_ROM_LICENSE}" && -f "${TEST_ROM_SOURCE}" ]] || {
    echo "bundled test ROM is missing its license or source record" >&2
    exit 1
  }
  bundled_test_rom="240p-test-mini-v0.23@$(sha256sum "${TEST_ROM}" | awk '{print $1}')"
  bundled_test_rom_license="gpl-v2@$(sha256sum "${TEST_ROM_LICENSE}" | awk '{print $1}')"
  bundled_test_rom_source="240p-test-mini-v0.23@$(sha256sum "${TEST_ROM_SOURCE}" | awk '{print $1}')"
else
  [[ ! -e "${TEST_ROM_LICENSE}" && ! -e "${TEST_ROM_SOURCE}" ]] || {
    echo "test ROM metadata is present without the ROM payload" >&2
    exit 1
  }
  bundled_test_rom=none
  bundled_test_rom_license=none
  bundled_test_rom_source=none
fi

manifest_entries="$(grep -vc '  \./BUILD-INFO$' "${PACKAGE_RUNTIME}/MANIFEST.sha256")"
cat >"${REPORT}.new" <<EOF
release_id=${RELEASE_ID}
rootfs_sparse_sha256=${rootfs_sha}
rootfs_sparse_size=$(stat -c %s "${SPARSE_IMAGE}")
rootfs_logical_size=${ROOTFS_LOGICAL_SIZE}
filesystem_check=clean
raw_sparse_round_trip=verified-by-normalizer
packaged_runtime_entries_verified=${manifest_entries}
packaged_symlinks_verified=yes
controller_profiles=${profile_count}
bundled_test_rom=${bundled_test_rom}
bundled_test_rom_license=${bundled_test_rom_license}
bundled_test_rom_source=${bundled_test_rom_source}
libretro_cores=${core_count}
libretro_core_info_files=${info_count}
emulationstation_theme=HiSTB-EmuELEC-carbon@62509737c2f732b81ce7bf37f6c4c3b82dafae28
rootfs_free_bytes=${rootfs_free_bytes}
rootfs_minimum_free_bytes=${MIN_ROOTFS_FREE_BYTES}
integration_files_verified=18
shutdown_stop_before_umount=yes
autostart_default=enabled
storage_layout=p9-root-ext4
storage_marker_default=present
p9_root_guard=mmcblk0p9-via-sysfs
dropbear_ssh=opt-in-configured-address
result=PASS
EOF
mv -f "${REPORT}.new" "${REPORT}"

echo "Final sparse rootfs payload audit: PASS"
echo "Audit report: ${REPORT}"
