#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/../runtime/bin/histb-runtime-exec"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT HUP INT TERM

mkdir -p "${TEST_ROOT}/runtime/bin"
cat >"${TEST_ROOT}/runtime/bin/program" <<'EOF'
#!/bin/sh
printf 'direct:%s\n' "$*"
EOF
chmod 0755 "${TEST_ROOT}/runtime/bin/program"

mkdir -p "${TEST_ROOT}/system/lib" "${TEST_ROOT}/system/usr/lib" \
    "${TEST_ROOT}/system/usr/share/alsa"
touch "${TEST_ROOT}/system/lib/libc.so.6" \
    "${TEST_ROOT}/system/usr/lib/libMali.so" \
    "${TEST_ROOT}/system/usr/share/alsa/alsa.conf"
cat >"${TEST_ROOT}/system/lib/ld-linux.so.3" <<'EOF'
#!/bin/sh
printf 'system-loader:%s\n' "$*"
printf 'alsa:%s\n' "${ALSA_CONFIG_PATH:-unset}"
EOF
chmod 0755 "${TEST_ROOT}/system/lib/ld-linux.so.3"

system_output="$(HISTB_SYSTEM_LOADER="${TEST_ROOT}/system/lib/ld-linux.so.3" \
    HISTB_SYSTEM_USR_LIB="${TEST_ROOT}/system/usr/lib" \
    HISTB_SYSTEM_LIB="${TEST_ROOT}/system/lib" \
    HISTB_SYSTEM_ALSA_CONFIG="${TEST_ROOT}/system/usr/share/alsa/alsa.conf" \
    "${RUNNER}" "${TEST_ROOT}/runtime" \
    "${TEST_ROOT}/runtime/bin/program" alpha beta)"
expected_system_loader="system-loader:--library-path ${TEST_ROOT}/runtime/lib:${TEST_ROOT}/system/usr/lib:${TEST_ROOT}/system/lib ${TEST_ROOT}/runtime/bin/program alpha beta"
expected_system_alsa="alsa:${TEST_ROOT}/system/usr/share/alsa/alsa.conf"
grep -Fxq "${expected_system_loader}" <<<"${system_output}"
grep -Fxq "${expected_system_alsa}" <<<"${system_output}"

ln -s runtime "${TEST_ROOT}/current"
linked_output="$(HISTB_SYSTEM_LOADER="${TEST_ROOT}/system/lib/ld-linux.so.3" \
    HISTB_SYSTEM_USR_LIB="${TEST_ROOT}/system/usr/lib" \
    HISTB_SYSTEM_LIB="${TEST_ROOT}/system/lib" \
    HISTB_SYSTEM_ALSA_CONFIG="${TEST_ROOT}/system/usr/share/alsa/alsa.conf" \
    "${RUNNER}" "${TEST_ROOT}/current" \
    "${TEST_ROOT}/current/bin/program" linked path)"
expected_linked="system-loader:--library-path ${TEST_ROOT}/runtime/lib:${TEST_ROOT}/system/usr/lib:${TEST_ROOT}/system/lib ${TEST_ROOT}/runtime/bin/program linked path"
grep -Fxq "${expected_linked}" <<<"${linked_output}"

rm -f "${TEST_ROOT}/system/usr/lib/libMali.so"
set +e
system_incomplete_output="$(HISTB_SYSTEM_LOADER="${TEST_ROOT}/system/lib/ld-linux.so.3" \
    HISTB_SYSTEM_USR_LIB="${TEST_ROOT}/system/usr/lib" \
    HISTB_SYSTEM_LIB="${TEST_ROOT}/system/lib" \
    "${RUNNER}" "${TEST_ROOT}/runtime" \
    "${TEST_ROOT}/runtime/bin/program" 2>&1)"
system_incomplete_rc=$?
set -e
[[ "${system_incomplete_rc}" = 1 ]]
grep -Fq 'incomplete system runtime' <<<"${system_incomplete_output}"
touch "${TEST_ROOT}/system/usr/lib/libMali.so"

mkdir -p "${TEST_ROOT}/runtime/compat/lib" \
    "${TEST_ROOT}/runtime/compat/usr/lib" \
    "${TEST_ROOT}/runtime/compat/usr/share/alsa"
touch "${TEST_ROOT}/runtime/compat/lib/libc.so.6" \
    "${TEST_ROOT}/runtime/compat/usr/lib/libMali.so" \
    "${TEST_ROOT}/runtime/compat/usr/share/alsa/alsa.conf"
cat >"${TEST_ROOT}/runtime/compat/lib/ld-linux.so.3" <<'EOF'
#!/bin/sh
printf 'loader:%s\n' "$*"
printf 'alsa:%s\n' "${ALSA_CONFIG_PATH:-unset}"
EOF
chmod 0755 "${TEST_ROOT}/runtime/compat/lib/ld-linux.so.3"

compat_output="$("${RUNNER}" "${TEST_ROOT}/runtime" \
    "${TEST_ROOT}/runtime/bin/program" gamma delta)"
expected_loader="loader:--library-path ${TEST_ROOT}/runtime/lib:${TEST_ROOT}/runtime/compat/usr/lib:${TEST_ROOT}/runtime/compat/lib ${TEST_ROOT}/runtime/bin/program gamma delta"
expected_alsa="alsa:${TEST_ROOT}/runtime/compat/usr/share/alsa/alsa.conf"
grep -Fxq "${expected_loader}" <<<"${compat_output}"
grep -Fxq "${expected_alsa}" <<<"${compat_output}"

rm -f "${TEST_ROOT}/runtime/compat/usr/lib/libMali.so"
set +e
incomplete_output="$("${RUNNER}" "${TEST_ROOT}/runtime" \
    "${TEST_ROOT}/runtime/bin/program" 2>&1)"
incomplete_rc=$?
set -e
[[ "${incomplete_rc}" = 1 ]]
grep -Fq 'incomplete compatibility runtime' <<<"${incomplete_output}"

set +e
unsafe_output="$("${RUNNER}" "${TEST_ROOT}/runtime" /bin/true 2>&1)"
unsafe_rc=$?
set -e
[[ "${unsafe_rc}" = 2 ]]
grep -Fq 'program is outside runtime root' <<<"${unsafe_output}"

cp "${TEST_ROOT}/runtime/bin/program" "${TEST_ROOT}/outside"
chmod 0755 "${TEST_ROOT}/outside"
set +e
escape_output="$("${RUNNER}" "${TEST_ROOT}/runtime" \
    "${TEST_ROOT}/runtime/bin/../../outside" 2>&1)"
escape_rc=$?
set -e
[[ "${escape_rc}" = 2 ]]
grep -Fq 'program is outside runtime root' <<<"${escape_output}"

printf '%s\n' 'PASS: explicit bundled/system loaders and runtime path guards'
