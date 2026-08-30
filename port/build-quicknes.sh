#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

QUICKNES_COMMIT="31654810b9ebf8b07f9c4dc27197af7714364ea7"
QUICKNES_SHA256="c05865407952cd102d78a6f4a1bc19666091357294cfe12909bc8dcdba019189"
ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/QuickNES_Core-${QUICKNES_COMMIT}.tar.gz"
SOURCE_PARENT="${HISTB_WORK_ROOT}/build/quicknes-${QUICKNES_COMMIT}"
SOURCE_DIR="${SOURCE_PARENT}/QuickNES_Core-${QUICKNES_COMMIT}"
CORE_DIR="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec/lib/libretro"
JOBS="${HISTB_JOBS:-4}"

if [[ ! -f "${ARCHIVE}" ]]; then
  echo "missing QuickNES archive: ${ARCHIVE}" >&2
  exit 1
fi
printf '%s  %s\n' "${QUICKNES_SHA256}" "${ARCHIVE}" | sha256sum --check --status || {
  echo "QuickNES archive checksum mismatch: ${ARCHIVE}" >&2
  exit 1
}

case "${SOURCE_PARENT}" in
  "${HISTB_WORK_ROOT}/build/"*) rm -rf -- "${SOURCE_PARENT}" ;;
  *) echo "refusing to reset path outside build root: ${SOURCE_PARENT}" >&2; exit 1 ;;
esac
mkdir -p "${SOURCE_PARENT}" "${CORE_DIR}"
tar -xzf "${ARCHIVE}" -C "${SOURCE_PARENT}"

make -C "${SOURCE_DIR}" -j"${JOBS}" \
  platform=armv7-softfloat \
  CC="${CC}" \
  CXX="${CXX}" \
  AR="${AR}" \
  CFLAGS="${HISTB_ARCH_FLAGS} -O3 --sysroot=${HISTB_SYSROOT}" \
  CXXFLAGS="${HISTB_ARCH_FLAGS} -O3 --sysroot=${HISTB_SYSROOT} -fno-rtti -fno-exceptions" \
  LDFLAGS="--sysroot=${HISTB_SYSROOT}"

cp "${SOURCE_DIR}/quicknes_libretro.so" "${CORE_DIR}/quicknes_libretro.so"
"${STRIP}" --strip-unneeded "${CORE_DIR}/quicknes_libretro.so"

"${SCRIPT_DIR}/check-elf-abi.sh" "${CORE_DIR}/quicknes_libretro.so"
for symbol in retro_init retro_load_game retro_run; do
  if ! "${NM}" -D "${CORE_DIR}/quicknes_libretro.so" | grep -q " ${symbol}$"; then
    echo "missing libretro entry point: ${symbol}" >&2
    exit 1
  fi
done

printf 'QuickNES staged at %s/quicknes_libretro.so\n' "${CORE_DIR}"
