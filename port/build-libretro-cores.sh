#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

JOBS="${HISTB_JOBS:-4}"
BUILD_PARENT="${HISTB_WORK_ROOT}/build/libretro-multicore"
CORE_DIR="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec/lib/libretro"
LICENSE_ROOT="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec/share/licenses/libretro-cores"
CMAKE_BIN="${HISTB_WORK_ROOT}/host-tools/cmake-3.20.6-linux-x86_64/bin/cmake"
PLATFORM="armv7-cortexa7-softfloat"
COMMON_CFLAGS="${HISTB_ARCH_FLAGS} -O3 -fPIC --sysroot=${HISTB_SYSROOT} -I${HISTB_VENDOR_INCLUDE}"
COMMON_CXXFLAGS="${COMMON_CFLAGS} -fno-rtti -fno-exceptions"
COMMON_LDFLAGS="--sysroot=${HISTB_SYSROOT} -L${HISTB_VENDOR_LIB} -Wl,-rpath-link,${HISTB_VENDOR_LIB}"
HWCAP_CFLAGS="-DHWCAP_NEON=4096 -DHWCAP2_AES=1 -DHWCAP2_SHA1=4 -DHWCAP2_SHA2=8 -DHWCAP2_CRC32=16"

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
  local symbol symbols_file="${BUILD_PARENT}/.${output_name}.dynamic-symbols"
  "${NM}" -D "${destination}" > "${symbols_file}"
  for symbol in retro_init retro_deinit retro_load_game retro_run; do
    if ! grep -q " ${symbol}$" "${symbols_file}"; then
      echo "${output_name}: missing libretro entry point ${symbol}" >&2
      return 1
    fi
  done
  rm -f -- "${symbols_file}"
  printf 'staged_core=%s bytes=%s sha256=%s\n' \
    "${output_name}" "$(stat -c %s "${destination}")" \
    "$(sha256sum "${destination}" | awk '{print $1}')"
}

install_submodule_archive()
{
  local archive=$1 sha256=$2 destination=$3
  [[ -f "${archive}" ]] || { echo "missing pinned submodule archive: ${archive}" >&2; return 1; }
  printf '%s  %s\n' "${sha256}" "${archive}" | sha256sum --check --status || {
    echo "submodule archive checksum mismatch: ${archive}" >&2
    return 1
  }
  case "${destination}" in
    "${BUILD_PARENT}/picodrive/"*) rm -rf -- "${destination}" ;;
    *) echo "refusing unsafe submodule destination: ${destination}" >&2; return 1 ;;
  esac
  mkdir -p "${destination}"
  tar -xzf "${archive}" -C "${destination}" --strip-components=1
}

stage_licenses()
{
  local name=$1 source_dir=$2 destination="${LICENSE_ROOT}/${1}"
  rm -rf -- "${destination}"
  mkdir -p "${destination}"
  while IFS= read -r -d '' license; do
    relative=${license#"${source_dir}/"}
    install -d "${destination}/$(dirname "${relative}")"
    install -m 0644 "${license}" "${destination}/${relative}"
  done < <(find "${source_dir}" -type f \
    \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'LICENSE-*' \
       -o -iname 'COPYING' -o -iname 'COPYING.*' -o -iname 'COPYING-*' \) \
    -print0 | sort -z)
  find "${destination}" -type f -print -quit | grep -q . || {
    echo "no license material staged for ${name}" >&2
    return 1
  }
}

[[ -x "${CMAKE_BIN}" ]] || { echo "portable CMake missing: ${CMAKE_BIN}" >&2; exit 1; }
mkdir -p "${BUILD_PARENT}" "${CORE_DIR}"
case "${CORE_DIR}" in
  "${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec/lib/libretro")
    find "${CORE_DIR}" -maxdepth 1 -type f -name '*_libretro.so' -delete
    ;;
  *) echo "unsafe libretro staging path: ${CORE_DIR}" >&2; exit 1 ;;
esac
case "${LICENSE_ROOT}" in
  "${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec/share/licenses/libretro-cores")
    rm -rf -- "${LICENSE_ROOT}"; mkdir -p "${LICENSE_ROOT}" ;;
  *) echo "unsafe license staging path: ${LICENSE_ROOT}" >&2; exit 1 ;;
esac

FCEUMM_COMMIT=236ccdfc911e84c60fea6b9d0699c2d440a8de14
FCEUMM_SOURCE="$(prepare_source fceumm \
  "${HISTB_WORK_ROOT}/cache/sources/libretro-fceumm-${FCEUMM_COMMIT}.tar.gz" \
  dd002cde9b5271979e0394bb9e696bd37e149ced473ff1e3629cc7fed502381f \
  "libretro-fceumm-${FCEUMM_COMMIT}")"
(
  export CFLAGS="${COMMON_CFLAGS}" CXXFLAGS="${COMMON_CXXFLAGS}"
  export ASFLAGS="${HISTB_ARCH_FLAGS}" LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${FCEUMM_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}"
)
stage_core "${FCEUMM_SOURCE}/fceumm_libretro.so" fceumm_libretro.so
stage_licenses fceumm "${FCEUMM_SOURCE}"

GAMBATTE_COMMIT=d9d6cd06382d1ced30de34d56d3609452323dab1
GAMBATTE_SOURCE="$(prepare_source gambatte \
  "${HISTB_WORK_ROOT}/cache/sources/gambatte-libretro-${GAMBATTE_COMMIT}.tar.gz" \
  bd39cd38662135d17e221a7fd34baf2908a40065ade16edf2e8d1168b21b921e \
  "gambatte-libretro-${GAMBATTE_COMMIT}")"
(
  export CFLAGS="${COMMON_CFLAGS}" CXXFLAGS="${COMMON_CXXFLAGS}"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${GAMBATTE_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}"
)
stage_core "${GAMBATTE_SOURCE}/gambatte_libretro.so" gambatte_libretro.so
stage_licenses gambatte "${GAMBATTE_SOURCE}"

GPSP_COMMIT=8d268a6bb2cd799f8f2791ebb544a7ef550cfc6f
GPSP_SOURCE="$(prepare_source gpsp \
  "${HISTB_WORK_ROOT}/cache/sources/gpsp-${GPSP_COMMIT}.tar.gz" \
  0b7833468c5fee9da7dcb433de0c11701fbb0734dba2c8b3630bd054d607e004 \
  "gpsp-${GPSP_COMMIT}")"
(
  export CFLAGS="${COMMON_CFLAGS}" CXXFLAGS="${COMMON_CXXFLAGS}"
  export ASFLAGS="${HISTB_ARCH_FLAGS}" LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${GPSP_SOURCE}" -j"${JOBS}" platform="${PLATFORM}" \
    CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}"
)
stage_core "${GPSP_SOURCE}/gpsp_libretro.so" gpsp_libretro.so
stage_licenses gpsp "${GPSP_SOURCE}"

MGBA_COMMIT=c65e8a3d4666b0ea68a01578232452f31b185332
MGBA_SOURCE="$(prepare_source mgba \
  "${HISTB_WORK_ROOT}/cache/sources/mgba-${MGBA_COMMIT}.tar.gz" \
  c79009b38da5c438aecfcf536c3ce2eb86588c622e756aa42dcbe8ee47b0a9f4 \
  "mgba-${MGBA_COMMIT}")"
patch -d "${MGBA_SOURCE}" -p1 --forward --batch \
  < "${SCRIPT_DIR}/patches/mGBA-GCC-Werror-Feature-Gate.patch"
MGBA_BUILD="${MGBA_SOURCE}/build-histb-libretro"
"${CMAKE_BIN}" -S "${MGBA_SOURCE}" -B "${MGBA_BUILD}" \
  -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=arm \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="${CC}" -DCMAKE_CXX_COMPILER="${CXX}" \
  -DCMAKE_AR="${AR}" -DCMAKE_STRIP="${STRIP}" \
  -DCMAKE_SYSROOT="${HISTB_SYSROOT}" \
  -DCMAKE_C_FLAGS="${COMMON_CFLAGS}" \
  -DCMAKE_CXX_FLAGS="${COMMON_CFLAGS} -fno-rtti" \
  -DCMAKE_SHARED_LINKER_FLAGS="${COMMON_LDFLAGS} -Wl,--no-as-needed -lz" \
  -DBUILD_LIBRETRO=ON -DBUILD_QT=OFF -DBUILD_SDL=OFF \
  -DBUILD_GL=OFF -DBUILD_GLES2=OFF -DBUILD_GLES3=OFF \
  -DBUILD_TEST=OFF -DBUILD_EXAMPLE=OFF \
  -DUSE_FFMPEG=OFF -DUSE_LIBZIP=OFF -DUSE_SQLITE3=OFF \
  -DUSE_ELF=OFF -DUSE_JSON_C=OFF -DUSE_EDITLINE=OFF
"${CMAKE_BIN}" --build "${MGBA_BUILD}" --target mgba_libretro --parallel "${JOBS}"
stage_core "${MGBA_BUILD}/mgba_libretro.so" mgba_libretro.so
stage_licenses mgba "${MGBA_SOURCE}"

PICODRIVE_COMMIT=733c711a477a642fd2006d5a7a581b2790ec36b4
PICODRIVE_SOURCE="$(prepare_source picodrive \
  "${HISTB_WORK_ROOT}/cache/sources/picodrive-${PICODRIVE_COMMIT}.tar.gz" \
  57e6b4bb2a5246380cb607975626dd9c0358bf0aef406340651dfd3542b5bd94 \
  "picodrive-${PICODRIVE_COMMIT}")"
install_submodule_archive \
  "${HISTB_WORK_ROOT}/cache/sources/cyclone68000-3ac7cf1bdeecb60e2414980e8dc72ff092f69769.tar.gz" \
  46368968d72556b50249b2d6584f24b21d6a25dfa9ab6cabf195726b253803cf \
  "${PICODRIVE_SOURCE}/cpu/cyclone"
install_submodule_archive \
  "${HISTB_WORK_ROOT}/cache/sources/libchdr-e62ac5995b1c7ef65ece35293914843b8ee57d49.tar.gz" \
  c2dfb6022858bd41db0b2f32d0a624e24a0fde937deea3d35182876baa2cb07c \
  "${PICODRIVE_SOURCE}/pico/cd/libchdr"
install_submodule_archive \
  "${HISTB_WORK_ROOT}/cache/sources/emu2413-a2dfc20ff507e4fd075cd325620bcea655e2c1f7.tar.gz" \
  e5f4e871789a94dbec60aba9fe9b8a843824f433b0163cdf87c94a9833517c4f \
  "${PICODRIVE_SOURCE}/pico/sound/emu2413"
install_submodule_archive \
  "${HISTB_WORK_ROOT}/cache/sources/dr_libs-dd762b861ecadf5ddd5fb03e9ca1db6707b54fbb.tar.gz" \
  7412af515c7c950e22913748ca41f2ed2c76768571e3fee30633d8e79d83be88 \
  "${PICODRIVE_SOURCE}/platform/common/dr_libs"
install_submodule_archive \
  "${HISTB_WORK_ROOT}/cache/sources/libpicofe-9ed5822606dd7ff20a782a882e8fd611cb53ba88.tar.gz" \
  a066ccb611ab08cb3b0749e1e5319e8b349e2ad489dbcc7e198c4b3f1f86ca1e \
  "${PICODRIVE_SOURCE}/platform/libpicofe"
patch -d "${PICODRIVE_SOURCE}" -p1 --forward --batch \
  < "${SCRIPT_DIR}/patches/PicoDrive-zlib-gzread-compat.patch"
(
  export CFLAGS="${COMMON_CFLAGS} ${HWCAP_CFLAGS}"
  export CXXFLAGS="${COMMON_CXXFLAGS} ${HWCAP_CFLAGS}"
  export ASFLAGS="${HISTB_ARCH_FLAGS}" LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${PICODRIVE_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" GIT_VERSION="${PICODRIVE_COMMIT}" \
    CC="${CC}" CXX="${CXX}" AR="${AR}" AS="${AS}" LD="${CC}"
)
stage_core "${PICODRIVE_SOURCE}/picodrive_libretro.so" picodrive_libretro.so
stage_licenses picodrive "${PICODRIVE_SOURCE}"

SNES_COMMIT=7db129b1ecdccb38cb4d7184bcbed39beed79656
SNES_SOURCE="$(prepare_source snes9x2010 \
  "${HISTB_WORK_ROOT}/cache/sources/snes9x2010-${SNES_COMMIT}.tar.gz" \
  612ee9484d076b38fb8cd880ba14aac071bacf126915b9fa4364c2300cdb157a \
  "libretro-snes9x2010-7db129b")"
(
  export CFLAGS="${COMMON_CFLAGS}" CXXFLAGS="${COMMON_CXXFLAGS}"
  export ASFLAGS="${HISTB_ARCH_FLAGS}" LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${SNES_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}"
)
stage_core "${SNES_SOURCE}/snes9x2010_libretro.so" snes9x2010_libretro.so
stage_licenses snes9x2010 "${SNES_SOURCE}"

PCE_COMMIT=2f623abd033257b969370b73d9da982dcb0c3fdd
PCE_SOURCE="$(prepare_source beetle-pce-fast \
  "${HISTB_WORK_ROOT}/cache/sources/beetle-pce-fast-libretro-${PCE_COMMIT}.tar.gz" \
  c9a78af8a3137375f6eb65484a1b3a7b794fd5192e523f8ecea08c9ccceed485 \
  "libretro-beetle-pce-fast-libretro-2f623ab")"
(
  export CFLAGS="${COMMON_CFLAGS}"
  export CXXFLAGS="${COMMON_CFLAGS} -fno-rtti"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${PCE_SOURCE}" -j"${JOBS}" platform="${PLATFORM}" HAVE_CHD=0 \
    CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CXX}"
)
stage_core "${PCE_SOURCE}/mednafen_pce_fast_libretro.so" mednafen_pce_fast_libretro.so
stage_licenses mednafen_pce_fast "${PCE_SOURCE}"

PCSX_COMMIT=ba61a4fdee1f789e8012f205f1b63826667644fa
PCSX_SOURCE="$(prepare_source pcsx-rearmed \
  "${HISTB_WORK_ROOT}/cache/sources/pcsx_rearmed-${PCSX_COMMIT}.tar.gz" \
  4580c6509a394c342faefab1ed0432326d49331e81c8ad79cc3f0a67d91fcec5 \
  "libretro-pcsx_rearmed-ba61a4f")"
patch -d "${PCSX_SOURCE}" -p1 --forward --batch \
  < "${SCRIPT_DIR}/patches/PCSX-ReARMed-Reproducible-Build-Date.patch"
(
  export CFLAGS="${COMMON_CFLAGS}" CXXFLAGS="${COMMON_CXXFLAGS}"
  export ASFLAGS="${HISTB_ARCH_FLAGS}" LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${PCSX_SOURCE}" -f Makefile.libretro -j"${JOBS}" \
    platform="${PLATFORM}" GIT_VERSION="${PCSX_COMMIT}" \
    DYNAREC=ari64 BUILTIN_GPU=peops HAVE_CHD=0 WANT_ZLIB=1 \
    HAVE_PHYSICAL_CDROM=0 \
    CC="${CC}" CXX="${CXX}" CC_AS="${CC}" AR="${AR}" AS="${AS}" LD="${CC}"
)
stage_core "${PCSX_SOURCE}/pcsx_rearmed_libretro.so" pcsx_rearmed_libretro.so
stage_licenses pcsx_rearmed "${PCSX_SOURCE}"

FBNEO_COMMIT=26f11fa9e43227a04953e20e8c7e4bf322cd53cb
FBNEO_SOURCE="$(prepare_source fbneo \
  "${HISTB_WORK_ROOT}/cache/sources/FBNeo-${FBNEO_COMMIT}.tar.gz" \
  0c013456154f00b2cb4a70e36d5128f79152e0b27c06dfc8bad0d577d6d22f98 \
  "libretro-FBNeo-26f11fa")"
(
  export CFLAGS="${COMMON_CFLAGS} ${HWCAP_CFLAGS}"
  export CXXFLAGS="${COMMON_CFLAGS} ${HWCAP_CFLAGS} -fno-rtti"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${FBNEO_SOURCE}/src/burner/libretro" -j"${JOBS}" \
    platform="${PLATFORM}" CC="${CC}" CXX="${CXX}" AR="${AR}" \
    LD="${CXX}" NATIVE_CC=gcc
)
stage_core "${FBNEO_SOURCE}/src/burner/libretro/fbneo_libretro.so" fbneo_libretro.so
stage_licenses fbneo "${FBNEO_SOURCE}"

MAME_COMMIT=21256d24120b04916c5197d95b757635ca880fd9
MAME_SOURCE="$(prepare_source mame2003-plus \
  "${HISTB_WORK_ROOT}/cache/sources/mame2003-plus-libretro-${MAME_COMMIT}.tar.gz" \
  0f55fdb1e64884694cc244b95b28246d2007f1237cf4cfe8c685e9dcc6fdd50f \
  "libretro-mame2003-plus-libretro-21256d2")"
(
  export CPPFLAGS="--sysroot=${HISTB_SYSROOT}"
  export CFLAGS="${HISTB_ARCH_FLAGS} -O3 -fPIC --sysroot=${HISTB_SYSROOT}"
  export CXXFLAGS="${HISTB_ARCH_FLAGS} -O3 -fPIC --sysroot=${HISTB_SYSROOT} -fno-rtti -fno-exceptions"
  export LDFLAGS="${COMMON_LDFLAGS}"
  make -C "${MAME_SOURCE}" -j"${JOBS}" platform="${PLATFORM}" ARCH= \
    CC="${CC}" CXX="${CXX}" AR="${AR}" LD="${CC}" NATIVE_CC=gcc
)
stage_core "${MAME_SOURCE}/mame2003_plus_libretro.so" mame2003_plus_libretro.so
stage_licenses mame2003_plus "${MAME_SOURCE}"

printf 'libretro multicore staging complete: %s\n' "${CORE_DIR}"
