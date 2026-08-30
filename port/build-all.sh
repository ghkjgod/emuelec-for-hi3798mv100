#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${HISTB_EMUELEC_ROOT}" show -s --format=%ct HEAD)}"

mkdir -p "${HISTB_WORK_ROOT}/logs"
LOG_FILE="${HISTB_WORK_ROOT}/logs/histb-emuelec-build-all.log"
exec > >(tee "${LOG_FILE}") 2>&1

echo "[1/14] SDK integration and full-p9 board configuration"
"${SCRIPT_DIR}/prepare-sdk-integration.sh"

echo "[2/14] Dropbear SSH (clean)"
"${SCRIPT_DIR}/build-dropbear.sh"

echo "[3/14] EGL/GLES2 smoke"
"${SCRIPT_DIR}/build-egl-smoke.sh"

echo "[4/14] EGL/GLES1 smoke"
"${SCRIPT_DIR}/build-egl-gles1-smoke.sh"

echo "[5/14] SDL2 Mali-fbdev (clean)"
"${SCRIPT_DIR}/build-sdl2.sh"

echo "[6/14] RetroArch (clean)"
"${SCRIPT_DIR}/build-retroarch.sh"

echo "[7/14] QuickNES (clean)"
"${SCRIPT_DIR}/build-quicknes.sh"

echo "[8/14] Additional libretro cores (clean)"
"${SCRIPT_DIR}/build-libretro-cores.sh"

echo "[9/14] EmulationStation and dependencies (clean)"
"${SCRIPT_DIR}/build-emulationstation.sh"

echo "[10/14] Runtime staging and configuration tests"
"${SCRIPT_DIR}/tests/test-runtime-exec.sh"
"${SCRIPT_DIR}/tests/test-multicore-config.sh"
"${SCRIPT_DIR}/tests/test-fullflash-config.sh"
"${SCRIPT_DIR}/stage-runtime.sh"

echo "[11/14] BSP rootbox composition"
(
  cd "${HISTB_SDK_ROOT}"
  # shellcheck disable=SC1091
  source ./env.sh
  LC_ALL=C make SHELL=/bin/bash rootbox_compose
)
"${SCRIPT_DIR}/install-dropbear-rootbox.sh"
"${SCRIPT_DIR}/configure-root-account.sh"
"${SCRIPT_DIR}/normalize-rootbox-metadata.sh"

echo "[12/14] Sparse full-p9 rootfs partition image"
(
  cd "${HISTB_SDK_ROOT}"
  # shellcheck disable=SC1091
  source ./env.sh
  LC_ALL=C make SHELL=/bin/bash extfs
)

echo "[13/14] Sparse rootfs normalization and filesystem gate"
"${SCRIPT_DIR}/normalize-rootfs-image.sh"

echo "[14/14] Dependency gate, versioned release, and image payload audit"
"${SCRIPT_DIR}/check-runtime-deps.sh"
"${SCRIPT_DIR}/package-release.sh"

echo "Complete. Log: ${LOG_FILE}"
