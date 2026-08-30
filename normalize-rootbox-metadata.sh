#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "${HISTB_EMUELEC_ROOT}" show -s --format=%ct HEAD)}"
case "${SOURCE_DATE_EPOCH}" in *[!0-9]*|'')
  echo "invalid SOURCE_DATE_EPOCH: ${SOURCE_DATE_EPOCH}" >&2
  exit 1
  ;;
esac
case "${HISTB_TARGET_ROOT}" in
  "${HISTB_OUT_ROOT}/rootbox") ;;
  *) echo "unsafe rootbox path: ${HISTB_TARGET_ROOT}" >&2; exit 1 ;;
esac
[[ -d "${HISTB_TARGET_ROOT}" ]] || {
  echo "rootbox is missing: ${HISTB_TARGET_ROOT}" >&2
  exit 1
}

find "${HISTB_TARGET_ROOT}" -xdev -print0 | LC_ALL=C sort -z |
  xargs -0r touch -h -d "@${SOURCE_DATE_EPOCH}"
while IFS= read -r -d '' path; do
  actual_mtime="$(stat -c %Y "${path}")"
  if [[ "${actual_mtime}" != "${SOURCE_DATE_EPOCH}" ]]; then
    echo "rootbox mtime normalization failed: ${path} (${actual_mtime})" >&2
    exit 1
  fi
done < <(find "${HISTB_TARGET_ROOT}" -xdev -print0)

echo "Rootbox mtimes normalized to SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"
