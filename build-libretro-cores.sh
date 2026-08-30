#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

JOBS="${HISTB_JOBS:-4}"
BUILD_PARENT="${HISTB_WORK_ROOT}/build/libretro-multicore"
CORE_DIR="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec/lib/libretro"
PLATFORM="armv7-cortexa7-softfloat"
COMMON_CFLAGS="${HISTB_ARCH_FLAGS} -O3 -fPIC --sysroot=${HISTB_SYSROOT} -I${HISTB_VENDOR_INCLUDE}"
COMMON_CXXFLAGS="${COMMON_CFLAGS} -fno-rtti -fno-exceptions"
COMMON_LDFLAGS="--sysroot=${HISTB_SYSROOT} -L${HISTB_VENDOR_LIB} -Wl,-rpath-link,${HISTB_VENDOR_LIB}"

prepare_source()
{
  local name=$1 archive=$2 sha256=$3 source_name=$4
  local source_root="${BUILD_PARENT}/${name}"
  local source_dir="${source_root}/${source_name}"

  [[ -f "${archive}" ]] || {
    echo "missing pinned source archive: ${archive}" >&2
    return 1
  }
  printf '%s  %s\n' "${sha256}" "${archive}" |
    sha256sum --check --status || {
      echo "source archive checksum mismatch: ${archive}" >&2
      return 1
    }
  case "${source_root}" in
    "${HISTB_WORK_ROOT}/build/libretro-multicore/"*) rm -rf -- "${source_root}" ;;
    *) echo "refusing unsafe core source reset: ${source_root}" >&2; return 1 ;;
  esac
  mkdir -p "${source_root}"
  tar -xzf "${archive}" -C "${source_root}"
  [[ -d "${source_dir}" ]] || {
    echo "archive did not create expected source root: ${source_dir}" >&2
    return 1
  }
  printf '%s\n' "${source_dir}"
}

stage_core()
{
  local source_file=$1 output_name=$2
  local destination="${CORE_DIR}/${output_name}"

  [[ -f "${source_file}" ]] || {
    echo "missing built core: ${source_file}" >&2
    return 1
  }
  install -m 0755 "${source_file}" "${destination}"
  "${STRIP}" --strip-unneeded "${destination}"
  "${SCRIPT_DIR}/check-elf-abi.sh" "${destination}"
  local symbol
  for symbol in retro_init retro_deinit retro_load_game retro_run; do
    if ! "${NM}" -D "${destination}" | grep -q " ${symbol}$"; then
      echo "${output_name}: missing libretro entry point ${symbol}" >&2
      return 1
    fi
  done
  printf 'staged_core=%s bytes=%s sha256=%s\n' \
    "${output_name}" "$(stat -c %s "${destination}")" \
    "$(sha256sum "${destination}" | awk '{print $1}')"
}

mkdir -p "${BUILD_PARENT}" "${CORE_DIR}"
case "${CORE_DIR}" in
  "${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec/lib/libretro")
    find "${CORE_DIR}" -maxdepth 1 -type f -name '*_libretro.so' \
      ! -name 'quicknes_libretro.so' -delete
    ;;
  *) echo "unsafe libretro staging path: ${CORE_DIR}" >&2; exit 1 ;;
esac

SNES_COMMIT=187e2b58fc09dfeb9fdb5a95bc26786219a111cf
SNES_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/snes9x2010-${SNES_COMMIT}.tar.gz"
SNES_SOURCE="$(prepare_source snes9x2010 "${SNES_ARCHIVE}" \
  323070dc047a9e483ca67fc85823dac576491f7026a8e2260c54b3cbec2c0542 \
  "snes9x2010-${SNES_COMMIT}")"
(
  export CFLAGS="${COMMON_CFLAGS}"
  export CXXFLAGS="${COMMON_CXXFLAGS}"
  export ASFLAGS="${HISTB_ARCH_FLAGS}"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${SNES_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}"
)
stage_core "${SNES_SOURCE}/snes9x2010_libretro.so" snes9x2010_libretro.so

GAMBATTE_COMMIT=dd1cf9fdbadbdceee50ff0600321251c823c3ca5
GAMBATTE_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/gambatte-libretro-${GAMBATTE_COMMIT}.tar.gz"
GAMBATTE_SOURCE="$(prepare_source gambatte "${GAMBATTE_ARCHIVE}" \
  25e27bcfc0a023e6f959d52cb2942d01ca177eb6a59311373b69bfbd3898e007 \
  "gambatte-libretro-${GAMBATTE_COMMIT}")"
(
  export CFLAGS="${COMMON_CFLAGS}"
  export CXXFLAGS="${COMMON_CXXFLAGS}"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${GAMBATTE_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}"
)
stage_core "${GAMBATTE_SOURCE}/gambatte_libretro.so" gambatte_libretro.so

VBA_NEXT_COMMIT=019132daf41e33a9529036b8728891a221a8ce2e
VBA_NEXT_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/vba-next-${VBA_NEXT_COMMIT}.tar.gz"
VBA_NEXT_SOURCE="$(prepare_source vba-next "${VBA_NEXT_ARCHIVE}" \
  29481df161a67fd2a9a3d5e4ff1c3330c3b60482c4527b9642a71f0e63505d6d \
  "vba-next-${VBA_NEXT_COMMIT}")"
(
  export CFLAGS="${COMMON_CFLAGS}"
  export CXXFLAGS="${COMMON_CXXFLAGS}"
  export ASFLAGS="${HISTB_ARCH_FLAGS}"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${VBA_NEXT_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}"
)
stage_core "${VBA_NEXT_SOURCE}/vba_next_libretro.so" vba_next_libretro.so

GENESIS_COMMIT=7fa34f20de659004399f58a845291a4496cc9d8c
GENESIS_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/Genesis-Plus-GX-${GENESIS_COMMIT}.tar.gz"
GENESIS_SOURCE="$(prepare_source genesis-plus-gx "${GENESIS_ARCHIVE}" \
  a6199c3b5a6ce7d693e60d4ccb32256915f6fa96603f42f557940e9423775b2f \
  "Genesis-Plus-GX-${GENESIS_COMMIT}")"
(
  export CFLAGS="${COMMON_CFLAGS} -DALIGN_LONG"
  export CXXFLAGS="${COMMON_CXXFLAGS} -DALIGN_LONG"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${GENESIS_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" GIT_VERSION="${GENESIS_COMMIT}" \
    CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}"
)
stage_core "${GENESIS_SOURCE}/genesis_plus_gx_libretro.so" genesis_plus_gx_libretro.so

PCE_COMMIT=bdcb39400470cfc9457e170e223a2e70130fdd5c
PCE_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/beetle-pce-fast-libretro-${PCE_COMMIT}.tar.gz"
PCE_SOURCE="$(prepare_source beetle-pce-fast "${PCE_ARCHIVE}" \
  341d63129e3baba52f95080fd7c23d421e1f0696d18cc4c4971780bdc49d44bf \
  "beetle-pce-fast-libretro-${PCE_COMMIT}")"
(
  export CFLAGS="${COMMON_CFLAGS}"
  # Beetle PCE's CD reader uses C++ exceptions for parse failures.
  export CXXFLAGS="${COMMON_CFLAGS} -fno-rtti"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${PCE_SOURCE}" -j"${JOBS}" platform="${PLATFORM}" \
    CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}" HAVE_CHD=0
)
stage_core "${PCE_SOURCE}/mednafen_pce_fast_libretro.so" mednafen_pce_fast_libretro.so

PCSX_COMMIT=19b9695a71f15ef0bf61c7c3cfd6c98ec5ccb028
PCSX_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/pcsx_rearmed-${PCSX_COMMIT}.tar.gz"
PCSX_SOURCE="$(prepare_source pcsx-rearmed "${PCSX_ARCHIVE}" \
  2a5722b82870c8688f5819e7f4db3bedae394c5b79c2165c9d2abc3c9bfff1ab \
  "pcsx_rearmed-${PCSX_COMMIT}")"
patch -d "${PCSX_SOURCE}" -p1 --forward --batch \
  < "${SCRIPT_DIR}/patches/PCSX-ReARMed-Reproducible-Build-Date.patch"
(
  export CFLAGS="${COMMON_CFLAGS}"
  export CXXFLAGS="${COMMON_CXXFLAGS}"
  export ASFLAGS="${HISTB_ARCH_FLAGS}"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${PCSX_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" GIT_VERSION="${PCSX_COMMIT}" \
    DYNAREC=ari64 BUILTIN_GPU=peops HAVE_CHD=0 WANT_ZLIB=1 \
    CC="${CC}" CXX="${CXX}" CC_AS="${CC}" AR="${AR}" AS="${AS}" LD="${CC}"
)
stage_core "${PCSX_SOURCE}/pcsx_rearmed_libretro.so" pcsx_rearmed_libretro.so

MAME_COMMIT=e3d1dac4cfaa4d03f8da5a6d78149bfefe894302
MAME_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/mame2003-libretro-${MAME_COMMIT}.tar.gz"
MAME_SOURCE="$(prepare_source mame2003 "${MAME_ARCHIVE}" \
  9a8abe56aa8fca8c899f28f8fe10f3d0aef62ee8825a96266e5482739b087ca5 \
  "mame2003-libretro-${MAME_COMMIT}")"
(
  # MAME2003 vendors zlib; do not put the BSP's zlib headers ahead of it.
  # env.sh exports BSP include paths through CPPFLAGS as well, so replace them
  # here while retaining the selected sysroot.
  export CPPFLAGS="--sysroot=${HISTB_SYSROOT}"
  export CFLAGS="${HISTB_ARCH_FLAGS} -O3 -fPIC --sysroot=${HISTB_SYSROOT}"
  export CXXFLAGS="${HISTB_ARCH_FLAGS} -O3 -fPIC --sysroot=${HISTB_SYSROOT} -fno-rtti -fno-exceptions"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${MAME_SOURCE}" -j"${JOBS}" platform="${PLATFORM}" ARCH= \
    CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CC}" NATIVE_CC=gcc
)
stage_core "${MAME_SOURCE}/mame2003_libretro.so" mame2003_libretro.so

printf 'libretro multicore staging complete: %s\n' "${CORE_DIR}"
