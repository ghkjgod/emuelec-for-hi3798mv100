#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SELECTOR="${HISTB_DIR}/runtime/bin/histb-controller-db-select"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT HUP INT TERM

RUNTIME="${TEST_ROOT}/runtime"
TF_MOUNT="${TEST_ROOT}/media/emuelec-tf"
STATE="${TEST_ROOT}/tf-state.env"
BUILTIN="${RUNTIME}/share/sdl/gamecontrollerdb.txt"
CANDIDATE="${TF_MOUNT}/EmuELEC/config/gamecontrollerdb.txt"
MANIFEST="${TF_MOUNT}/EmuELEC/config/gamecontrollerdb.sha256"
mkdir -p "$(dirname "${BUILTIN}")" "$(dirname "${CANDIDATE}")"

make_db()
{
  local output=$1 name=$2
  : >"${output}"
  for index in $(seq 1 20); do
    printf '030000004c050000cc09000011010000,%s %s,a:b1,b:b2,platform:Linux,\n' \
      "${name}" "${index}" >>"${output}"
  done
}

make_db "${BUILTIN}" Builtin
make_db "${CANDIDATE}" TF
printf 'mount=%s\n' "${TF_MOUNT}" >"${STATE}"

run_selector()
{
  HISTB_EE_ROOT="${RUNTIME}" HISTB_TF_STATE="${STATE}" \
    HISTB_TF_MOUNT="${TF_MOUNT}" "${SELECTOR}"
}

[[ "$(run_selector)" = "${BUILTIN}" ]]
(
  cd "$(dirname "${CANDIDATE}")"
  sha256sum gamecontrollerdb.txt > gamecontrollerdb.sha256
)
[[ "$(run_selector)" = "${CANDIDATE}" ]]
printf '%064d  gamecontrollerdb.txt\n' 0 >"${MANIFEST}"
[[ "$(run_selector 2>/dev/null)" = "${BUILTIN}" ]]
printf '%s\n' 'not a controller mapping' >"${CANDIDATE}"
(
  cd "$(dirname "${CANDIDATE}")"
  sha256sum gamecontrollerdb.txt > gamecontrollerdb.sha256
)
[[ "$(run_selector 2>/dev/null)" = "${BUILTIN}" ]]

printf '%s\n' 'PASS: TF controller database selection, checksum gate, and built-in fallback'
