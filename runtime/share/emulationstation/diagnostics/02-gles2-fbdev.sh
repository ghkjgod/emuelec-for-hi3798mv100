#!/bin/sh

set -eu
RUNTIME_ROOT=${HISTB_EE_ROOT:-/opt/emuelec}
exec "${RUNTIME_ROOT}/bin/histb-runtime-exec" "${RUNTIME_ROOT}" \
    "${RUNTIME_ROOT}/bin/histb-egl-smoke" \
    --frames 300 --use-fb-size
