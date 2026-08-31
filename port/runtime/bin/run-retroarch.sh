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
    fceumm|gambatte|gpsp|mgba|picodrive|snes9x2010|mednafen_pce_fast|pcsx_rearmed|fbneo|mame2003_plus)
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
        CORE=fceumm
        ROM=$1
        shift
        ;;
esac
CORE_FILE=${RUNTIME_ROOT}/lib/libretro/${CORE}_libretro.so
CORE_SOURCE=builtin
TF_STATE=/var/run/histb-tf-storage.env
TF_MOUNT=/media/emuelec-tf
if [ -r "${TF_STATE}" ]; then
    state_mount=$(awk -F= '$1 == "mount" { sub(/^[^=]*=/, ""); print; exit }' "${TF_STATE}")
    case "${state_mount}" in /media/*|/mnt/*) TF_MOUNT=${state_mount} ;; esac
fi

case "${STORAGE_ROOT}" in
    /|"") echo "refusing unsafe storage root: ${STORAGE_ROOT}" >&2; exit 1 ;;
    /*) ;;
    *) echo "storage root must be absolute: ${STORAGE_ROOT}" >&2; exit 1 ;;
esac
HISTB_STORAGE_ROOT="${STORAGE_ROOT}" \
    /usr/bin/histb-storage-guard --require-marker
if [ ! -r "${ROM}" ]; then
    case "${ROM}" in
        "${TF_MOUNT}"/*) echo "TF card game is unavailable. Reinsert the card, rescan storage, and restart EmulationStation: ${ROM}" >&2 ;;
        *) echo "ROM is not readable: ${ROM}" >&2 ;;
    esac
    exit 1
fi
case "${ROM}" in
    "${TF_MOUNT}"/EmuELEC/roms/*) ROM_SOURCE=tf ;;
    *) ROM_SOURCE=internal ;;
esac
if [ -x /usr/bin/histb-tf-core-select ]; then
    if selected_core=$(HISTB_EE_ROOT="${RUNTIME_ROOT}" HISTB_STORAGE_ROOT="${STORAGE_ROOT}" \
        /usr/bin/histb-tf-core-select "${CORE}"); then
        CORE_FILE=${selected_core}
        case "${CORE_FILE}" in
            "${TF_MOUNT}"/*) CORE_SOURCE=direct-tf ;;
            "${STORAGE_ROOT}"/ee/core-cache/*) CORE_SOURCE=tf-cache ;;
        esac
    else
        echo "TF core unavailable or incompatible; using the built-in ${CORE} core" >&2
    fi
fi
if [ ! -r "${CORE_FILE}" ]; then
    echo "libretro core is not readable: ${CORE_FILE}" >&2
    exit 1
fi

mkdir -p "${HOME_ROOT}" "${STORAGE_ROOT}/roms/bios" \
    "${STORAGE_ROOT}/savefiles" "${STORAGE_ROOT}/savestates" \
    "${STORAGE_ROOT}/screenshots" "${STORAGE_ROOT}/playlists"

BIOS_ROOT=${STORAGE_ROOT}/roms/bios
if [ "${ROM_SOURCE}" = tf ] && [ -d "${TF_MOUNT}/EmuELEC/bios" ]; then
    BIOS_ROOT=${TF_MOUNT}/EmuELEC/bios
fi
RUNTIME_CONFIG=${HOME_ROOT}/retroarch-histb-runtime.cfg
{
    printf 'joypad_autoconfig_dir = "%s/share/retroarch/autoconfig"\n' "${RUNTIME_ROOT}"
    printf 'libretro_directory = "%s/lib/libretro"\n' "${RUNTIME_ROOT}"
    printf 'libretro_info_path = "%s/share/libretro/info"\n' "${RUNTIME_ROOT}"
    printf 'system_directory = "%s"\n' "${BIOS_ROOT}"
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
HISTB_GAMECONTROLLERDB=$(HISTB_EE_ROOT="${RUNTIME_ROOT}" \
    "${RUNTIME_ROOT}/bin/histb-controller-db-select")
export HISTB_GAMECONTROLLERDB

echo "HiSTB launch ROM source=${ROM_SOURCE} path=${ROM}" >&2
echo "HiSTB launch core source=${CORE_SOURCE} path=${CORE_FILE}" >&2
echo "HiSTB launch BIOS path=${BIOS_ROOT}" >&2
echo "HiSTB controller database path=${HISTB_GAMECONTROLLERDB}" >&2

"${RUNTIME_ROOT}/bin/histb-runtime-exec" "${RUNTIME_ROOT}" \
    "${RUNTIME_ROOT}/bin/retroarch" \
    --config "${RUNTIME_ROOT}/etc/retroarch.cfg" \
    --appendconfig "${RUNTIME_CONFIG}" \
    -L "${CORE_FILE}" \
    "$ROM" "$@" &
retroarch_pid=$!
trap 'kill "${retroarch_pid}" 2>/dev/null || true' HUP INT TERM
set +e
wait "${retroarch_pid}"
status=$?
set -e
trap - HUP INT TERM
if [ "${ROM_SOURCE}" = tf ] && ! mountpoint -q "${TF_MOUNT}"; then
    echo "TF card was removed while the game was running. The internal system is intact; reinsert the card and restart EmulationStation." >&2
fi
exit "${status}"
