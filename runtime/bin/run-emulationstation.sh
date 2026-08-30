#!/bin/sh

set -eu

if [ -n "${HISTB_EE_ROOT:-}" ]; then
    RUNTIME_ROOT=${HISTB_EE_ROOT}
else
    SCRIPT_DIR=$(dirname "$0")
    RUNTIME_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
fi

STORAGE_ROOT=${HISTB_STORAGE_ROOT:-/storage}
STATE_ROOT=${STORAGE_ROOT}/ee
HOME_ROOT=${STATE_ROOT}/config
ES_CONFIG=${HOME_ROOT}/.emulationstation

case "${STORAGE_ROOT}" in
    /|"") echo "refusing unsafe storage root: ${STORAGE_ROOT}" >&2; exit 1 ;;
    /*) ;;
    *) echo "storage root must be absolute: ${STORAGE_ROOT}" >&2; exit 1 ;;
esac
HISTB_STORAGE_ROOT="${STORAGE_ROOT}" \
    /usr/bin/histb-storage-guard --require-marker

mkdir -p "${ES_CONFIG}" "${STATE_ROOT}/logs" "${STATE_ROOT}/diagnostics" \
    "${STORAGE_ROOT}/.config/emuelec/configs" \
    "${STORAGE_ROOT}/.config/emuelec/logs" \
    "${STORAGE_ROOT}/.config/emuelec/scripts" \
    "${STORAGE_ROOT}/.config/emuelec/BGM" \
    "${STORAGE_ROOT}/roms/nes" "${STORAGE_ROOT}/roms/snes" \
    "${STORAGE_ROOT}/roms/gb" "${STORAGE_ROOT}/roms/gba" \
    "${STORAGE_ROOT}/roms/megadrive" "${STORAGE_ROOT}/roms/pce" \
    "${STORAGE_ROOT}/roms/psx" "${STORAGE_ROOT}/roms/arcade" \
    "${STORAGE_ROOT}/roms/bios" \
    "${STORAGE_ROOT}/roms/BGM" "${STORAGE_ROOT}/roms/bezels" \
    "${STORAGE_ROOT}/roms/mplayer" \
    "${STORAGE_ROOT}/savefiles" "${STORAGE_ROOT}/savestates" \
    "${STORAGE_ROOT}/screenshots" "${STORAGE_ROOT}/playlists"
SYSTEM_CONF=${STORAGE_ROOT}/.config/emuelec/configs/emuelec.conf
if [ ! -f "${SYSTEM_CONF}" ]; then
    SYSTEM_CONF_TMP=${SYSTEM_CONF}.new.$$
    trap 'rm -f -- "${SYSTEM_CONF_TMP}"' EXIT HUP INT TERM
    {
        printf '%s\n' 'audio.bgmusic=0'
        printf '%s\n' 'kodi.enabled=0'
        printf '%s\n' 'wifi.enabled=0'
        printf '%s\n' 'system.hostname=emuelec-device'
        printf '%s\n' 'global.retroachievements=0'
    } >"${SYSTEM_CONF_TMP}"
    chmod 0644 "${SYSTEM_CONF_TMP}"
    mv -f "${SYSTEM_CONF_TMP}" "${SYSTEM_CONF}"
    trap - EXIT HUP INT TERM
fi


if [ ! -f "${ES_CONFIG}/es_systems.cfg" ]; then
    cp "${RUNTIME_ROOT}/etc/emulationstation/es_systems.cfg" \
        "${ES_CONFIG}/es_systems.cfg"
fi
if [ ! -f "${ES_CONFIG}/es_input.cfg" ]; then
    cp "${RUNTIME_ROOT}/etc/emulationstation/es_input.cfg" \
        "${ES_CONFIG}/es_input.cfg"
fi

# This EmulationStation revision discovers themes only below its writable
# config directory (or /etc).  Keep a managed link pointed at the theme in the
# selected built-in/A-B runtime so rollback also rolls the theme back.  Never
# replace a user-created real directory at the managed path.
THEME_SOURCE=${RUNTIME_ROOT}/share/emulationstation/themes/HiSTB-EmuELEC-carbon
THEME_ROOT=${ES_CONFIG}/themes
THEME_LINK=${THEME_ROOT}/HiSTB-EmuELEC-carbon
if [ -f "${THEME_SOURCE}/nes/theme.xml" ]; then
    mkdir -p "${THEME_ROOT}"
    if [ -L "${THEME_LINK}" ]; then
        THEME_LINK_NEW=${THEME_LINK}.new.$$
        trap 'rm -f -- "${THEME_LINK_NEW}"' EXIT HUP INT TERM
        ln -s "${THEME_SOURCE}" "${THEME_LINK_NEW}"
        mv -f "${THEME_LINK_NEW}" "${THEME_LINK}"
        trap - EXIT HUP INT TERM
    elif [ ! -e "${THEME_LINK}" ]; then
        ln -s "${THEME_SOURCE}" "${THEME_LINK}"
    fi
fi

for diagnostic in "${RUNTIME_ROOT}"/share/emulationstation/diagnostics/*.sh; do
    [ -f "${diagnostic}" ] || continue
    destination=${STATE_ROOT}/diagnostics/$(basename "${diagnostic}")
    if [ ! -f "${destination}" ]; then
        cp "${diagnostic}" "${destination}"
        chmod 0755 "${destination}"
    fi
done

export HISTB_EE_ROOT=${RUNTIME_ROOT}
export HISTB_STORAGE_ROOT=${STORAGE_ROOT}
export HOME=${HOME_ROOT}
export XDG_CONFIG_HOME=${HOME_ROOT}/.config
export PATH=${RUNTIME_ROOT}/bin:${PATH}
export LD_LIBRARY_PATH=${RUNTIME_ROOT}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-mali}
export SDL_AUDIODRIVER=${SDL_AUDIODRIVER:-alsa}
export HISTB_LOG_ROOT=${STATE_ROOT}/logs

cd "${RUNTIME_ROOT}/bin"
exec "${RUNTIME_ROOT}/bin/histb-runtime-exec" "${RUNTIME_ROOT}" \
    "${RUNTIME_ROOT}/bin/emulationstation" \
    --home "${HOME_ROOT}" --no-splash --log-path "${STATE_ROOT}/logs" "$@"
