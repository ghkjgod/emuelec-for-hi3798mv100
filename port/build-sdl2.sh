#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

SDL_VERSION="2.0.9"
SDL_SHA256="255186dc676ecd0c1dbf10ec8a2cc5d6869b5079d8a38194c2aecdff54b324b1"
ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/SDL2-${SDL_VERSION}.tar.gz"
SOURCE_PARENT="${HISTB_WORK_ROOT}/build/sdl2-${SDL_VERSION}-histb-source"
SOURCE_DIR="${SOURCE_PARENT}/SDL2-${SDL_VERSION}"
BUILD_DIR="${HISTB_WORK_ROOT}/build/sdl2-${SDL_VERSION}-histb-build"
STAGE_ROOT="${HISTB_WORK_ROOT}/artifacts/overlay"
PATCH_DIR="${HISTB_EMUELEC_ROOT}/packages/sx05re/tools/SDL2-git/patches/Amlogic"
JOBS="${HISTB_JOBS:-4}"

if [[ ! -f "${ARCHIVE}" ]]; then
  echo "missing SDL archive: ${ARCHIVE}" >&2
  echo "download https://www.libsdl.org/release/SDL2-${SDL_VERSION}.tar.gz there first" >&2
  exit 1
fi

printf '%s  %s\n' "${SDL_SHA256}" "${ARCHIVE}" | sha256sum --check --status || {
  echo "SDL archive checksum mismatch: ${ARCHIVE}" >&2
  exit 1
}

for reset_path in "${SOURCE_PARENT}" "${BUILD_DIR}"; do
  case "${reset_path}" in
    "${HISTB_WORK_ROOT}/build/"*) rm -rf -- "${reset_path}" ;;
    *) echo "refusing to reset path outside build root: ${reset_path}" >&2; exit 1 ;;
  esac
done
mkdir -p "${SOURCE_PARENT}" "${BUILD_DIR}" "${STAGE_ROOT}"
tar -xzf "${ARCHIVE}" -C "${SOURCE_PARENT}"
patch -d "${SOURCE_DIR}" -p1 --forward --batch \
  < "${PATCH_DIR}/SDL2-git-001-enable_mali.patch"
patch -d "${SOURCE_DIR}" -p1 --forward --batch \
  < "${SCRIPT_DIR}/patches/SDL2-git-HiSTB.patch"

cd "${BUILD_DIR}"

export CPPFLAGS="${CPPFLAGS} -DEGL_API_FBDEV=1 -DEGL_API_UTGARD=1"
export CFLAGS="${CFLAGS} -O2"
export ALSA_CFLAGS="-I${HISTB_VENDOR_INCLUDE} -I${HISTB_VENDOR_INCLUDE}/alsa"
export ALSA_LIBS="-L${HISTB_VENDOR_LIB} -lasound"
export PKG_CONFIG=false

"${SOURCE_DIR}/configure" \
  --host=arm-histbv310-linux \
  --prefix=/opt/emuelec \
  --enable-shared \
  --disable-static \
  --enable-threads \
  --enable-alsa \
  --enable-alsa-shared \
  --disable-oss \
  --disable-diskaudio \
  --disable-dummyaudio \
  --disable-pulseaudio \
  --disable-jack \
  --disable-esd \
  --disable-arts \
  --disable-nas \
  --disable-sndio \
  --disable-dbus \
  --disable-ime \
  --disable-libudev \
  --disable-ibus \
  --disable-fcitx \
  --disable-video-x11 \
  --disable-video-wayland \
  --disable-video-mir \
  --disable-video-directfb \
  --disable-video-kmsdrm \
  --disable-video-vivante \
  --disable-video-vulkan \
  --disable-video-opengles1 \
  --enable-video-opengles2 \
  --enable-video-opengles \
  --enable-video-mali \
  --enable-joystick \
  --disable-haptic \
  --disable-sensor \
  --disable-rpath

make -j"${JOBS}"
make DESTDIR="${STAGE_ROOT}" install

"${STRIP}" --strip-unneeded \
  "${STAGE_ROOT}/opt/emuelec/lib/libSDL2-2.0.so.0.9.0"

mkdir -p "${STAGE_ROOT}/opt/emuelec/bin"
"${CC}" ${CPPFLAGS} ${CFLAGS} \
  -I"${STAGE_ROOT}/opt/emuelec/include/SDL2" -D_REENTRANT \
  "${SCRIPT_DIR}/sdl2-smoke.c" \
  -o "${STAGE_ROOT}/opt/emuelec/bin/histb-sdl2-smoke" \
  ${LDFLAGS} -L"${STAGE_ROOT}/opt/emuelec/lib" \
  -Wl,-rpath,/opt/emuelec/lib -lSDL2 -lEGL -lGLESv2 -ldl -lpthread -lm -lrt

mapfile -t ABI_TARGETS < <(find "${STAGE_ROOT}/opt/emuelec/lib" -maxdepth 1 \
  -type f -name 'libSDL2-*.so.*' -print)
ABI_TARGETS+=("${STAGE_ROOT}/opt/emuelec/bin/histb-sdl2-smoke")
"${SCRIPT_DIR}/check-elf-abi.sh" "${ABI_TARGETS[@]}"

printf 'SDL2 staged under %s/opt/emuelec\n' "${STAGE_ROOT}"
