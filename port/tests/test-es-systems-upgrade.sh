#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="${SCRIPT_DIR}/../runtime/bin/histb-sync-es-systems"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT HUP INT TERM

packaged="${TEST_ROOT}/packaged.cfg"
target="${TEST_ROOT}/target.cfg"
marker="${target}.histb-managed-sha256"
printf '%s\n' '<systemList><system><name>tf-nes</name></system></systemList>' >"${packaged}"
packaged_sha="$(sha256sum "${packaged}" | awk '{print $1}')"

# A first boot installs and marks the packaged file.
"${SYNC}" "${packaged}" "${target}" >/dev/null
cmp "${packaged}" "${target}"
grep -Fxq "${packaged_sha}" "${marker}"

# A previously managed, unchanged file advances to the next package.
printf '%s\n' '<systemList><system><name>tf-snes</name></system></systemList>' >"${packaged}"
"${SYNC}" "${packaged}" "${target}" >/dev/null
cmp "${packaged}" "${target}"

# A user edit never gets overwritten, even when a stale marker exists.
printf '%s\n' '<systemList><system><name>my-custom-system</name></system></systemList>' >"${target}"
cp "${packaged}" "${TEST_ROOT}/expected-custom.cfg"
printf '%s\n' '<systemList><system><name>tf-gb</name></system></systemList>' >"${packaged}"
"${SYNC}" "${packaged}" "${target}" >/dev/null
grep -Fq 'my-custom-system' "${target}"

# An unmarked exact legacy file is migrated; other unmarked files are kept.
rm -f "${marker}"
printf '%s\n' '<systemList><system><name>legacy</name></system></systemList>' >"${target}"
legacy_sha="$(sha256sum "${target}" | awk '{print $1}')"
HISTB_ES_LEGACY_SHA256="${legacy_sha}" "${SYNC}" "${packaged}" "${target}" >/dev/null
cmp "${packaged}" "${target}"

rm -f "${marker}"
printf '%s\n' '<systemList><system><name>unmanaged-custom</name></system></systemList>' >"${target}"
HISTB_ES_LEGACY_SHA256="${legacy_sha}" "${SYNC}" "${packaged}" "${target}" >/dev/null
grep -Fq 'unmanaged-custom' "${target}"

printf '%s\n' 'PASS: managed ES systems upgrades preserve every user-modified configuration'
