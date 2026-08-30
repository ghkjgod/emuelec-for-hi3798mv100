#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

DROPBEAR_VERSION=2026.94
SOURCE="${HISTB_WORK_ROOT}/build/dropbear-${DROPBEAR_VERSION}/output/dropbearmulti"
REPORT="${HISTB_WORK_ROOT}/artifacts/dropbear-build-info.txt"

[[ -x "${SOURCE}" && -f "${REPORT}" ]] || {
  echo "built Dropbear payload or report is missing" >&2
  exit 1
}
expected_sha="$(awk -F= '$1 == "binary_sha256" { print $2; exit }' "${REPORT}")"
actual_sha="$(sha256sum "${SOURCE}" | awk '{print $1}')"
[[ -n "${expected_sha}" && "${actual_sha}" = "${expected_sha}" ]] || {
  echo "built Dropbear checksum mismatch: ${actual_sha}" >&2
  exit 1
}
case "${HISTB_TARGET_ROOT}" in "${HISTB_OUT_ROOT}/rootbox") ;; *)
  echo "unsafe rootbox path: ${HISTB_TARGET_ROOT}" >&2
  exit 1
  ;;
esac

install -D -m 0755 "${SOURCE}" "${HISTB_TARGET_ROOT}/usr/sbin/dropbear"
mkdir -p "${HISTB_TARGET_ROOT}/usr/bin" "${HISTB_TARGET_ROOT}/etc/dropbear"
ln -sfn ../sbin/dropbear "${HISTB_TARGET_ROOT}/usr/bin/dropbearkey"
chmod 0700 "${HISTB_TARGET_ROOT}/etc/dropbear"

cmp "${SOURCE}" "${HISTB_TARGET_ROOT}/usr/sbin/dropbear"
[[ "$(readlink "${HISTB_TARGET_ROOT}/usr/bin/dropbearkey")" = ../sbin/dropbear ]]
echo "Installed Dropbear into BSP rootbox: ${actual_sha}"
