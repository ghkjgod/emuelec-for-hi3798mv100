#!/bin/sh

set -eu

if [ "$#" -lt 1 ]; then
    echo "usage: $0 [CORE] ROM [retroarch arguments...]" >&2
    exit 2
fi

if [ -n "${HISTB_EE_ROOT:-}" ]; then
    RUNTIME_ROOT=${HISTB_EE_ROOT}
else
    SCRIPT_DIR=$(dirname "$0")
    RUNTIME_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
fi

STORAGE_ROOT=${HISTB_STORAGE_ROOT:-/storage}
HOME_ROOT=${STORAGE_ROOT}/ee/config
case "$1" in
    quicknes|snes9x2010|gambatte|vba_next|genesis_plus_gx|mednafen_pce_fast|pcsx_rearmed|mame2003)
        [ "$#" -ge 2 ] || {
            echo "ROM argument is missing for core: $1" >&2
            exit 2
        }
        CORE=$1
        ROM=$2
        shift 2
        ;;
    *)
        # Preserve the original one-argument NES launcher interface.
        CORE=quicknes
        ROM=$1
        shift
        ;;
esac
CORE_FILE=${RUNTIME_ROOT}/lib/libretro/${CORE}_libretro.so

case "${STORAGE_ROOT}" in
    /|"") echo "refusing unsafe storage root: ${STORAGE_ROOT}" >&2; exit 1 ;;
    /*) ;;
    *) echo "storage root must be absolute: ${STORAGE_ROOT}" >&2; exit 1 ;;
esac
HISTB_STORAGE_ROOT="${STORAGE_ROOT}" \
    /usr/bin/histb-storage-guard --require-marker
if [ ! -r "${ROM}" ]; then
    echo "ROM is not readable: ${ROM}" >&2
    exit 1
fi
if [ ! -r "${CORE_FILE}" ]; then
    echo "libretro core is not readable: ${CORE_FILE}" >&2
    exit 1
fi

mkdir -p "${HOME_ROOT}" "${STORAGE_ROOT}/roms/bios" \
    "${STORAGE_ROOT}/savefiles" "${STORAGE_ROOT}/savestates" \
    "${STORAGE_ROOT}/screenshots" "${STORAGE_ROOT}/playlists"

RUNTIME_CONFIG=${HOME_ROOT}/retroarch-histb-runtime.cfg
{
    printf 'joypad_autoconfig_dir = "%s/share/retroarch/autoconfig"\n' "${RUNTIME_ROOT}"
    printf 'libretro_directory = "%s/lib/libretro"\n' "${RUNTIME_ROOT}"
    printf 'libretro_info_path = "%s/share/libretro/info"\n' "${RUNTIME_ROOT}"
    printf 'system_directory = "%s/roms/bios"\n' "${STORAGE_ROOT}"
    printf 'savefile_directory = "%s/savefiles"\n' "${STORAGE_ROOT}"
    printf 'savestate_directory = "%s/savestates"\n' "${STORAGE_ROOT}"
    printf 'screenshot_directory = "%s/screenshots"\n' "${STORAGE_ROOT}"
    printf 'playlist_directory = "%s/playlists"\n' "${STORAGE_ROOT}"
    printf 'content_history_path = "%s/playlists/content_history.lpl"\n' "${STORAGE_ROOT}"
    printf 'content_music_history_path = "%s/playlists/content_music_history.lpl"\n' "${STORAGE_ROOT}"
    printf 'content_video_history_path = "%s/playlists/content_video_history.lpl"\n' "${STORAGE_ROOT}"
    printf 'content_image_history_path = "%s/playlists/content_image_history.lpl"\n' "${STORAGE_ROOT}"
    printf 'content_favorites_path = "%s/playlists/content_favorites.lpl"\n' "${STORAGE_ROOT}"
} >"${RUNTIME_CONFIG}.new"
mv -f "${RUNTIME_CONFIG}.new" "${RUNTIME_CONFIG}"

export HISTB_EE_ROOT=${RUNTIME_ROOT}
export HISTB_STORAGE_ROOT=${STORAGE_ROOT}
export HOME=${HOME_ROOT}
export XDG_CONFIG_HOME=${HOME_ROOT}/.config
export LD_LIBRARY_PATH=${RUNTIME_ROOT}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-mali}
export SDL_AUDIODRIVER=${SDL_AUDIODRIVER:-alsa}
export HISTB_LOG_ROOT=${STORAGE_ROOT}/ee/logs

exec "${RUNTIME_ROOT}/bin/histb-runtime-exec" "${RUNTIME_ROOT}" \
    "${RUNTIME_ROOT}/bin/retroarch" \
    --config "${RUNTIME_ROOT}/etc/retroarch.cfg" \
    --appendconfig "${RUNTIME_CONFIG}" \
    -L "${CORE_FILE}" \
    "$ROM" "$@"
