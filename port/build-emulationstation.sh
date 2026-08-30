#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

ES_VERSION="2afe6efec4e09176882d98323bda5d3f664870a7"
PUGIXML_VERSION="7247a823b72259a2b814696838d02f7424a8ce0e"
JOBS="${HISTB_JOBS:-8}"

SOURCE_CACHE="${HISTB_WORK_ROOT}/cache/sources"
BUILD_BASE="${HISTB_WORK_ROOT}/build/emulationstation-${ES_VERSION}-histb-v1"
PREFIX="${HISTB_WORK_ROOT}/build/emulationstation-deps-prefix-v1"
OVERLAY="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec"
SDL_STAGE="${OVERLAY}"
CMAKE_BIN="${HISTB_WORK_ROOT}/host-tools/cmake-3.20.6-linux-x86_64/bin/cmake"

ES_ARCHIVE="${SOURCE_CACHE}/emuelec-emulationstation-${ES_VERSION}.tar.gz"
PUGIXML_ARCHIVE="${SOURCE_CACHE}/pugixml-${PUGIXML_VERSION}.tar.gz"
FREEIMAGE_ARCHIVE="${SOURCE_CACHE}/FreeImage3180.zip"
CURL_ARCHIVE="${SOURCE_CACHE}/curl-7.71.1.tar.xz"
RAPIDJSON_ARCHIVE="${SOURCE_CACHE}/rapidjson-1.1.0.tar.gz"
SDLMIXER_ARCHIVE="${SOURCE_CACHE}/SDL2_mixer-2.0.4.tar.gz"
OGG_ARCHIVE="${SOURCE_CACHE}/libogg-1.3.3.tar.xz"
VORBIS_ARCHIVE="${SOURCE_CACHE}/libvorbis-1.3.6.tar.xz"

verify_source() {
  local file="$1"
  local expected="$2"
  local actual

  if [[ ! -f "${file}" ]]; then
    echo "missing source archive: ${file}" >&2
    exit 1
  fi
  actual="$(sha256sum "${file}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "checksum mismatch: ${file}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
}

reset_build_dir() {
  local path="$1"
  case "${path}" in
    "${HISTB_WORK_ROOT}/build/"*) ;;
    *)
      echo "refusing to reset path outside build root: ${path}" >&2
      exit 1
      ;;
  esac
  rm -rf -- "${path}"
  mkdir -p "${path}"
}

verify_source "${ES_ARCHIVE}" "4d6a119f1d1386c64e49bc55c6092b3dc1f43058fcd70a08488a85e7895499fe"
verify_source "${PUGIXML_ARCHIVE}" "856556015802ec68ed0e8febe577523fd97cf0269650ad0a3648c87f38e103b6"
verify_source "${FREEIMAGE_ARCHIVE}" "f41379682f9ada94ea7b34fe86bf9ee00935a3147be41b6569c9605a53e438fd"
verify_source "${CURL_ARCHIVE}" "40f83eda27cdbeb25cd4da48cefb639af1b9395d6026d2da1825bf059239658c"
verify_source "${RAPIDJSON_ARCHIVE}" "bf7ced29704a1e696fbccf2a2b4ea068e7774fa37f6d7dd4039d0787f8bed98e"
verify_source "${SDLMIXER_ARCHIVE}" "b4cf5a382c061cd75081cf246c2aa2f9df8db04bdda8dcdc6b6cca55bede2419"
verify_source "${OGG_ARCHIVE}" "4f3fc6178a533d392064f14776b23c397ed4b9f48f5de297aba73b643f955c08"
verify_source "${VORBIS_ARCHIVE}" "af00bb5a784e7c9e69f56823de4637c350643deedaf333d0fa86ecdba6fcb415"

if [[ ! -x "${CMAKE_BIN}" ]]; then
  echo "portable CMake missing: ${CMAKE_BIN}" >&2
  exit 1
fi
if [[ ! -f "${SDL_STAGE}/lib/libSDL2.so" ]]; then
  echo "SDL2 stage missing; run tools/histb/build-sdl2.sh first" >&2
  exit 1
fi

reset_build_dir "${BUILD_BASE}"
reset_build_dir "${PREFIX}"
mkdir -p "${PREFIX}/bin" "${PREFIX}/include" "${PREFIX}/lib"

BASE_CPPFLAGS="--sysroot=${HISTB_SYSROOT} -I${PREFIX}/include -I${HISTB_VENDOR_INCLUDE}"
BASE_CFLAGS="${HISTB_ARCH_FLAGS} -O2 -fPIC"
BASE_CXXFLAGS="${HISTB_ARCH_FLAGS} -O2 -fPIC"
BASE_LDFLAGS="--sysroot=${HISTB_SYSROOT} -L${PREFIX}/lib -L${HISTB_VENDOR_LIB} -Wl,-rpath-link,${PREFIX}/lib -Wl,-rpath-link,${HISTB_VENDOR_LIB}"
HOST_TRIPLET="arm-linux-gnueabi"

# Seed the private dependency prefix with the already verified HiSTB SDL2
# development files. Rewrite only the build-time prefix; the target SONAME and
# runtime libraries remain under /opt/emuelec/lib.
cp -a "${SDL_STAGE}/include/SDL2" "${PREFIX}/include/"
cp -a "${SDL_STAGE}/lib/libSDL2-2.0.so.0.9.0" "${PREFIX}/lib/"
ln -sfn libSDL2-2.0.so.0.9.0 "${PREFIX}/lib/libSDL2-2.0.so.0"
ln -sfn libSDL2-2.0.so.0.9.0 "${PREFIX}/lib/libSDL2.so"
sed "s#^prefix=.*#prefix=${PREFIX}#" "${SDL_STAGE}/bin/sdl2-config" > "${PREFIX}/bin/sdl2-config"
chmod +x "${PREFIX}/bin/sdl2-config"

echo "[1/7] libogg"
OGG_SRC="${BUILD_BASE}/libogg"
mkdir -p "${OGG_SRC}"
tar -xJf "${OGG_ARCHIVE}" --strip-components=1 -C "${OGG_SRC}"
(
  cd "${OGG_SRC}"
  env CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" \
    CPPFLAGS="${BASE_CPPFLAGS}" CFLAGS="${BASE_CFLAGS}" \
    CXXFLAGS="${BASE_CXXFLAGS}" LDFLAGS="${BASE_LDFLAGS}" \
    ./configure --host="${HOST_TRIPLET}" --prefix="${PREFIX}" \
      --enable-shared --disable-static
  sed -i \
    -e 's/^hardcode_into_libs=.*/hardcode_into_libs=no/' \
    -e 's/^hardcode_libdir_flag_spec=.*/hardcode_libdir_flag_spec=""/' \
    -e 's/^runpath_var=.*/runpath_var=/' libtool
  make -j"${JOBS}"
  make install
)

echo "[2/7] libvorbis"
VORBIS_SRC="${BUILD_BASE}/libvorbis"
mkdir -p "${VORBIS_SRC}"
tar -xJf "${VORBIS_ARCHIVE}" --strip-components=1 -C "${VORBIS_SRC}"
(
  cd "${VORBIS_SRC}"
  env PATH="${PREFIX}/bin:${PATH}" CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" \
    CPPFLAGS="${BASE_CPPFLAGS}" CFLAGS="${BASE_CFLAGS}" \
    CXXFLAGS="${BASE_CXXFLAGS}" LDFLAGS="${BASE_LDFLAGS}" \
    OGG_CFLAGS="-I${PREFIX}/include" OGG_LIBS="-L${PREFIX}/lib -logg" \
    ./configure --host="${HOST_TRIPLET}" --prefix="${PREFIX}" \
      --with-ogg="${PREFIX}" --enable-shared --disable-static \
      --disable-docs --disable-examples --disable-oggtest
  sed -i \
    -e 's/^hardcode_into_libs=.*/hardcode_into_libs=no/' \
    -e 's/^hardcode_libdir_flag_spec=.*/hardcode_libdir_flag_spec=""/' \
    -e 's/^runpath_var=.*/runpath_var=/' libtool
  make -j"${JOBS}"
  make install
)

echo "[3/7] SDL2_mixer"
SDLMIXER_SRC="${BUILD_BASE}/sdl2-mixer"
mkdir -p "${SDLMIXER_SRC}"
tar -xzf "${SDLMIXER_ARCHIVE}" --strip-components=1 -C "${SDLMIXER_SRC}"
(
  cd "${SDLMIXER_SRC}"
  env PATH="${PREFIX}/bin:${PATH}" CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" \
    SDL2_CONFIG="${PREFIX}/bin/sdl2-config" PKG_CONFIG=/bin/false \
    CPPFLAGS="${BASE_CPPFLAGS} -I${PREFIX}/include/SDL2" CFLAGS="${BASE_CFLAGS}" \
    CXXFLAGS="${BASE_CXXFLAGS}" LDFLAGS="${BASE_LDFLAGS}" \
    OGG_CFLAGS="-I${PREFIX}/include" OGG_LIBS="-L${PREFIX}/lib -logg" \
    VORBIS_CFLAGS="-I${PREFIX}/include" VORBIS_LIBS="-L${PREFIX}/lib -lvorbisfile -lvorbis -logg" \
    ./configure --host="${HOST_TRIPLET}" --prefix="${PREFIX}" \
      --enable-shared --disable-static --disable-sdltest \
      --disable-music-mod --disable-music-flac --disable-music-mp3 \
      --enable-music-ogg --disable-music-ogg-shared \
      --disable-music-midi --disable-music-opus
  sed -i \
    -e 's/^hardcode_into_libs=.*/hardcode_into_libs=no/' \
    -e 's/^hardcode_libdir_flag_spec=.*/hardcode_libdir_flag_spec=""/' \
    -e 's/^runpath_var=.*/runpath_var=/' libtool
  make -j"${JOBS}"
  make install
)

echo "[4/7] FreeImage"
FREEIMAGE_PARENT="${BUILD_BASE}/freeimage"
mkdir -p "${FREEIMAGE_PARENT}"
unzip -q "${FREEIMAGE_ARCHIVE}" -d "${FREEIMAGE_PARENT}"
FREEIMAGE_SRC="${FREEIMAGE_PARENT}/FreeImage"
(
  cd "${FREEIMAGE_SRC}"
  # Keep CFLAGS/CXXFLAGS in the environment rather than on the make command
  # line.  FreeImage's Makefile appends its bundled codec include paths; GNU
  # make would suppress those appends for command-line variable overrides.
  env CC="${CC}" CXX="${CXX}" AR="${AR}" \
    CFLAGS="${BASE_CFLAGS} -fexceptions -fvisibility=hidden -DPNG_ARM_NEON_OPT=0" \
    CXXFLAGS="${BASE_CXXFLAGS} -fexceptions -fvisibility=hidden -Wno-ctor-dtor-privacy -Wno-narrowing -DPNG_ARM_NEON_OPT=0" \
    LDFLAGS="${BASE_LDFLAGS}" \
    make -f Makefile.gnu -j"${JOBS}" LIBRARIES="-lstdc++ -lm -lpthread"
)
install -m 0644 "${FREEIMAGE_SRC}/Dist/FreeImage.h" "${PREFIX}/include/FreeImage.h"
install -m 0755 "${FREEIMAGE_SRC}/Dist/libfreeimage-3.18.0.so" "${PREFIX}/lib/libfreeimage-3.18.0.so"
ln -sfn libfreeimage-3.18.0.so "${PREFIX}/lib/libfreeimage.so.3"
ln -sfn libfreeimage.so.3 "${PREFIX}/lib/libfreeimage.so"

echo "[5/7] curl"
CURL_SRC="${BUILD_BASE}/curl"
mkdir -p "${CURL_SRC}"
tar -xJf "${CURL_ARCHIVE}" --strip-components=1 -C "${CURL_SRC}"
(
  cd "${CURL_SRC}"
  env CC="${CC}" CXX="${CXX}" AR="${AR}" RANLIB="${RANLIB}" PKG_CONFIG=/bin/false \
    CPPFLAGS="${BASE_CPPFLAGS}" CFLAGS="${BASE_CFLAGS}" CXXFLAGS="${BASE_CXXFLAGS}" \
    LDFLAGS="${BASE_LDFLAGS}" LIBS="-lssl -lcrypto -lz -ldl -lpthread -lrt" \
    ./configure --host="${HOST_TRIPLET}" --prefix="${PREFIX}" \
      --enable-shared --disable-static --disable-debug --disable-curldebug \
      --enable-http --enable-file --disable-ftp --disable-ldap --disable-ldaps \
      --disable-rtsp --disable-dict --disable-telnet --disable-tftp \
      --disable-pop3 --disable-imap --disable-smb --disable-smtp --disable-gopher \
      --disable-manual --disable-threaded-resolver --disable-ipv6 \
      --with-ssl --with-zlib --without-libpsl --without-libssh2 \
      --without-nghttp2 --without-brotli --without-zstd --without-libidn2 \
      --with-ca-bundle=/storage/ee/config/cacert.pem --without-ca-path
  sed -i \
    -e 's/^hardcode_into_libs=.*/hardcode_into_libs=no/' \
    -e 's/^hardcode_libdir_flag_spec=.*/hardcode_libdir_flag_spec=""/' \
    -e 's/^runpath_var=.*/runpath_var=/' libtool
  make -j"${JOBS}"
  make install
)

echo "[6/7] RapidJSON, pugixml, and EmulationStation source"
RAPIDJSON_SRC="${BUILD_BASE}/rapidjson"
mkdir -p "${RAPIDJSON_SRC}"
tar -xzf "${RAPIDJSON_ARCHIVE}" --strip-components=1 -C "${RAPIDJSON_SRC}"
cp -a "${RAPIDJSON_SRC}/include/rapidjson" "${PREFIX}/include/"

ES_SRC="${BUILD_BASE}/source"
mkdir -p "${ES_SRC}"
tar -xzf "${ES_ARCHIVE}" --strip-components=1 -C "${ES_SRC}"
mkdir -p "${ES_SRC}/external/pugixml"
tar -xzf "${PUGIXML_ARCHIVE}" --strip-components=1 -C "${ES_SRC}/external/pugixml"
patch -d "${ES_SRC}" -p1 < "${SCRIPT_DIR}/patches/EmulationStation-HiSTB.patch"
patch -d "${ES_SRC}" -p1 < "${SCRIPT_DIR}/patches/EmulationStation-OptionalSplash-HiSTB.patch"

echo "[7/7] EmulationStation GLES1 / Mali-fbdev"
ES_BUILD="${BUILD_BASE}/cmake-build"
mkdir -p "${ES_BUILD}"
export HISTB_ES_PREFIX="${PREFIX}"
"${CMAKE_BIN}" -S "${ES_SRC}" -B "${ES_BUILD}" \
  -DCMAKE_TOOLCHAIN_FILE="${SCRIPT_DIR}/histb-toolchain.cmake" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/emuelec \
  -DCMAKE_C_FLAGS="${BASE_CFLAGS} -I${HISTB_VENDOR_INCLUDE}" \
  -DCMAKE_CXX_FLAGS="${BASE_CXXFLAGS} -Wno-unused-local-typedefs -Wno-deprecated-declarations -I${HISTB_VENDOR_INCLUDE}" \
  -DCMAKE_EXE_LINKER_FLAGS="${BASE_LDFLAGS}" \
  -DCMAKE_SKIP_RPATH=ON \
  -DGLES=ON -DGL=OFF -DRPI=OFF -DBCM=OFF -DCEC=OFF \
  -DENABLE_VLC=OFF -DENABLE_EMUELEC=1 -DDISABLE_KODI=1 -DENABLE_FILEMANAGER=0 \
  -DSDL2_BUILDING_LIBRARY=ON \
  -DSDL2_INCLUDE_DIR="${PREFIX}/include/SDL2" \
  -DSDL2_LIBRARY_TEMP="${PREFIX}/lib/libSDL2.so" \
  -DSDLMIXER_INCLUDE_DIR="${PREFIX}/include/SDL2" \
  -DSDLMIXER_LIBRARY="${PREFIX}/lib/libSDL2_mixer.so" \
  -DFreeImage_INCLUDE_DIR="${PREFIX}/include" \
  -DFreeImage_LIBRARY_REL="${PREFIX}/lib/libfreeimage.so" \
  -DCURL_INCLUDE_DIR="${PREFIX}/include" \
  -DCURL_LIBRARY="${PREFIX}/lib/libcurl.so" \
  -DRapidjson_ROOT="${PREFIX}" \
  -DFREETYPE_INCLUDE_DIR_ft2build="${HISTB_VENDOR_INCLUDE}/freetype2" \
  -DFREETYPE_INCLUDE_DIR_freetype2="${HISTB_VENDOR_INCLUDE}/freetype2" \
  -DFREETYPE_LIBRARY_RELEASE="${HISTB_VENDOR_LIB}/libfreetype.so" \
  -DALSA_INCLUDE_DIR="${HISTB_VENDOR_INCLUDE}" \
  -DALSA_LIBRARY="${HISTB_VENDOR_LIB}/libasound.so" \
  -DOPENGLES_INCLUDE_DIR="${HISTB_VENDOR_INCLUDE}" \
  -DOPENGLES_gl_LIBRARY="${HISTB_VENDOR_LIB}/libGLESv1_CM.so"
"${CMAKE_BIN}" --build "${ES_BUILD}" --parallel "${JOBS}"

install -d "${OVERLAY}/bin" "${OVERLAY}/lib"
install -m 0755 "${ES_SRC}/emulationstation" "${OVERLAY}/bin/emulationstation"
rm -rf -- "${OVERLAY}/bin/resources"
cp -a "${ES_SRC}/resources" "${OVERLAY}/bin/resources"

for pattern in 'libogg.so*' 'libvorbis.so*' 'libvorbisenc.so*' 'libvorbisfile.so*' \
               'libSDL2_mixer*.so*' 'libfreeimage*.so*' 'libcurl.so*'; do
  matches=("${PREFIX}/lib/"${pattern})
  cp -a "${matches[@]}" "${OVERLAY}/lib/"
done

"${SCRIPT_DIR}/check-elf-abi.sh" "${OVERLAY}/bin/emulationstation"
while IFS= read -r library; do
  "${SCRIPT_DIR}/check-elf-abi.sh" "${library}"
done < <(find "${OVERLAY}/lib" -maxdepth 1 -type f \
  \( -name 'libogg.so*' -o -name 'libvorbis*.so*' -o -name 'libSDL2_mixer*.so*' \
     -o -name 'libfreeimage*.so*' -o -name 'libcurl.so*' \) | sort)

echo "EmulationStation staged at ${OVERLAY}/bin/emulationstation"
