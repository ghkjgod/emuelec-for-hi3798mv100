#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

RUNTIME_ROOT="${HISTB_WORK_ROOT}/artifacts/overlay/opt/emuelec"
ROOTBOX="${HISTB_TARGET_ROOT}"
missing=0
checked=0

if [[ ! -d "${RUNTIME_ROOT}" || ! -d "${ROOTBOX}" ]]; then
  echo "runtime overlay or composed rootbox is missing" >&2
  exit 1
fi

resolve_library() {
  local name="$1"
  local directory
  for directory in \
      "${RUNTIME_ROOT}/lib" \
      "${ROOTBOX}/lib" \
      "${ROOTBOX}/usr/lib" \
      "${ROOTBOX}/usr/local/lib"; do
    if [[ -e "${directory}/${name}" ]]; then
      return 0
    fi
  done
  return 1
}

while IFS= read -r elf; do
  if ! "${READELF}" -h "${elf}" >/dev/null 2>&1; then
    continue
  fi
  checked=$((checked + 1))
  while IFS= read -r needed; do
    if ! resolve_library "${needed}"; then
      echo "missing ${needed} required by ${elf}" >&2
      missing=$((missing + 1))
    fi
  done < <("${READELF}" -d "${elf}" 2>/dev/null |
    sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
done < <(find "${RUNTIME_ROOT}/bin" "${RUNTIME_ROOT}/lib" -type f | sort)

if (( missing != 0 )); then
  echo "runtime dependency closure failed: ${missing} missing entries" >&2
  exit 1
fi

echo "Runtime dependency closure OK for ${checked} ARM ELF files"
