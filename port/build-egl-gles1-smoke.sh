#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

OUTPUT_DIR="${HISTB_WORK_ROOT}/artifacts/egl-smoke"
OUTPUT="${OUTPUT_DIR}/histb-egl-gles1-smoke"

mkdir -p "${OUTPUT_DIR}"

"${CC}" ${CPPFLAGS} ${CFLAGS} \
  -DEGL_API_FBDEV=1 -DEGL_API_UTGARD=1 \
  -DEGL_EGLEXT_PROTOTYPES -DGL_GLEXT_PROTOTYPES \
  "${SCRIPT_DIR}/egl-gles1-smoke.c" \
  -o "${OUTPUT}" \
  ${LDFLAGS} -Wl,--no-as-needed -lEGL -lGLESv1_CM -ldl -lpthread -lm -lrt

"${SCRIPT_DIR}/check-elf-abi.sh" "${OUTPUT}"
printf 'built %s\n' "${OUTPUT}"
