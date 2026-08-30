#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

RETROARCH_COMMIT="ccbff758b46556407d1b9931a72cfcc46201276d"
CACHE_REPO="${HISTB_WORK_ROOT}/cache/sources/retroarch.git"
SOURCE_DIR="${HISTB_WORK_ROOT}/build/retroarch-${RETROARCH_COMMIT}-histb-minimal-v1"
STAGE_ROOT="${HISTB_WORK_ROOT}/artifacts/overlay"
SDL_PREFIX="${STAGE_ROOT}/opt/emuelec"
JOBS="${HISTB_JOBS:-4}"

if [[ ! -d "${CACHE_REPO}/.git" ]] ||
   ! git -C "${CACHE_REPO}" cat-file -e "${RETROARCH_COMMIT}^{commit}" 2>/dev/null; then
  echo "missing pinned RetroArch checkout: ${CACHE_REPO}" >&2
  echo "fetch commit ${RETROARCH_COMMIT} before building" >&2
  exit 1
fi
if [[ ! -f "${SDL_PREFIX}/lib/libSDL2.so" ]]; then
  echo "SDL2 overlay is missing; run build-sdl2.sh first" >&2
  exit 1
fi

case "${SOURCE_DIR}" in
  "${HISTB_WORK_ROOT}/build/"*) rm -rf -- "${SOURCE_DIR}" ;;
  *) echo "refusing to reset path outside build root: ${SOURCE_DIR}" >&2; exit 1 ;;
esac
mkdir -p "${SOURCE_DIR}"
git -C "${CACHE_REPO}" archive "${RETROARCH_COMMIT}" | tar -x -C "${SOURCE_DIR}"
patch -d "${SOURCE_DIR}" -p1 --forward --batch \
  < "${SCRIPT_DIR}/patches/RetroArch-HiSTB.patch"
patch -d "${SOURCE_DIR}" -p1 --forward --batch \
  < "${SCRIPT_DIR}/patches/RetroArch-Reproducible-Build-Date.patch"

cd "${SOURCE_DIR}"

export CFLAGS="${HISTB_ARCH_FLAGS} -O2 --sysroot=${HISTB_SYSROOT} -I${HISTB_VENDOR_INCLUDE} -I${SDL_PREFIX}/include/SDL2 -DEGL_API_FBDEV=1 -DEGL_API_UTGARD=1"
export CXXFLAGS="${CFLAGS}"
export LDFLAGS="--sysroot=${HISTB_SYSROOT} -L${SDL_PREFIX}/lib -L${HISTB_VENDOR_LIB} -Wl,-rpath-link,${SDL_PREFIX}/lib -Wl,-rpath-link,${HISTB_VENDOR_LIB}"

./configure \
  --host=arm-histbv310-linux \
  --prefix=/opt/emuelec \
  --sysconfdir=/opt/emuelec/etc \
  --enable-threads \
  --enable-thread_storage \
  --disable-neon \
  --enable-floatsoftfp \
  --enable-dynamic \
  --enable-alsa \
  --disable-oss \
  --disable-pulse \
  --disable-jack \
  --disable-al \
  --disable-tinyalsa \
  --enable-sdl2 \
  --disable-sdl \
  --enable-egl \
  --enable-opengles \
  --enable-mali_fbdev \
  --disable-opengl \
  --disable-opengl1 \
  --disable-opengl_core \
  --disable-opengles3 \
  --disable-kms \
  --disable-vulkan \
  --disable-vg \
  --disable-x11 \
  --disable-wayland \
  --disable-xvideo \
  --enable-rgui \
  --disable-xmb \
  --disable-ozone \
  --disable-materialui \
  --disable-gfx_widgets \
  --disable-shaderpipeline \
  --disable-glslang \
  --disable-builtinglslang \
  --disable-slang \
  --disable-freetype \
  --enable-zlib \
  --disable-builtinzlib \
  --disable-7zip \
  --disable-flac \
  --disable-builtinflac \
  --disable-chd \
  --disable-ffmpeg \
  --disable-ssa \
  --disable-networking \
  --disable-networkgamepad \
  --disable-miniupnpc \
  --disable-ssl \
  --disable-udev \
  --disable-libusb \
  --disable-dbus \
  --disable-systemd \
  --disable-hid \
  --disable-libretrodb \
  --disable-video_filter \
  --disable-dsp_filter \
  --disable-online_updater \
  --disable-update_cores \
  --disable-update_assets \
  --disable-cheevos \
  --disable-discord \
  --disable-accessibility \
  --disable-translate \
  --disable-audiomixer \
  --disable-stb_vorbis \
  --disable-ibxm \
  --disable-cdrom \
  --disable-imageviewer \
  --disable-video_layout \
  --disable-v4l2 \
  --disable-parport \
  --disable-blissbox \
  --disable-screenshots \
  --disable-langextra \
  --disable-qt

make -j"${JOBS}" \
  HAVE_UPDATE_ASSETS=0 \
  HAVE_LIBRETRODB=0 \
  HAVE_NETWORKING=0 \
  HAVE_LAKKA=0 \
  HAVE_ZARCH=0 \
  HAVE_QT=0 \
  HAVE_LANGEXTRA=0

mkdir -p "${STAGE_ROOT}/opt/emuelec/bin" "${STAGE_ROOT}/opt/emuelec/etc"
cp retroarch "${STAGE_ROOT}/opt/emuelec/bin/retroarch"
cp "${SCRIPT_DIR}/retroarch-histb.cfg" \
  "${STAGE_ROOT}/opt/emuelec/etc/retroarch.cfg"
"${STRIP}" --strip-unneeded "${STAGE_ROOT}/opt/emuelec/bin/retroarch"

"${SCRIPT_DIR}/check-elf-abi.sh" "${STAGE_ROOT}/opt/emuelec/bin/retroarch"
printf 'RetroArch staged under %s/opt/emuelec\n' "${STAGE_ROOT}"
