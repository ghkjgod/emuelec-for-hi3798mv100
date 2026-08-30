#!/bin/sh

set -eu
export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-mali}
RUNTIME_ROOT=${HISTB_EE_ROOT:-/opt/emuelec}
exec "${RUNTIME_ROOT}/bin/histb-runtime-exec" "${RUNTIME_ROOT}" \
    "${RUNTIME_ROOT}/bin/histb-sdl2-smoke"
