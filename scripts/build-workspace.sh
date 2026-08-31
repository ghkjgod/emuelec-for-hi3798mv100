#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
JOBS="${HISTB_JOBS:-2}"

"${SCRIPT_DIR}/bootstrap-workspace.sh"
"${SCRIPT_DIR}/fetch-sources.sh"

export HISTB_WORK_ROOT="${WORKSPACE_ROOT}"
export HISTB_SDK_ROOT="${WORKSPACE_ROOT}/sdk"
export HISTB_EMUELEC_ROOT="${WORKSPACE_ROOT}/emuelec"
PORT_ROOT="${HISTB_EMUELEC_ROOT}/tools/histb"

"${PORT_ROOT}/prepare-sdk-integration.sh"

if [[ "${HISTB_SKIP_SDK_BUILD:-0}" != 1 ]]; then
  echo "Building the pinned HiSTBLinux SDK with ${JOBS} job(s)..."
  (
    cd "${HISTB_SDK_ROOT}"
    # shellcheck disable=SC1091
    source ./env.sh
    # The first SDK pass creates vendor include/lib/rootbox inputs before the
    # EmuELEC application overlay exists.  The second pass in port/build-all.sh
    # composes the completed overlay into rootbox.
    # The board configuration enables both SquashFS and ext4, but this port
    # ships and flashes only the full-p9 ext4 image.  The SDK's bundled,
    # vendor-modified mksquashfs 4.3 crashes after reaching 100% on current
    # Linux hosts.  Keep the complete SDK `build` target while limiting its
    # image step to the format that is actually delivered.
    LC_ALL=C make SHELL=/bin/bash HISTB_EMUELEC_DISABLE=y IMAGES=extfs \
      build -j"${JOBS}"
  )
else
  echo "HISTB_SKIP_SDK_BUILD=1: using an existing SDK output tree"
fi

"${PORT_ROOT}/build-all.sh"

echo "Build complete. Outputs and logs are under ${WORKSPACE_ROOT}/artifacts and ${WORKSPACE_ROOT}/logs."
