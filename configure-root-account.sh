#!/usr/bin/env bash

# Player-friendly public default: root/emuelec. Builders can inject a different
# modular-crypt hash, lock root with !, or install authorized_keys. Never print
# a password hash.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

SHADOW="${HISTB_TARGET_ROOT}/etc/shadow"
[[ -f "${SHADOW}" ]] || {
  echo "rootbox shadow file is missing" >&2
  exit 1
}
[[ "$(awk -F: '$1 == "root" { count++ } END { print count + 0 }' "${SHADOW}")" = 1 ]] || {
  echo "rootbox must contain exactly one root shadow entry" >&2
  exit 1
}

if [[ -v HISTB_ROOT_PASSWORD_HASH ]]; then
  password_hash="${HISTB_ROOT_PASSWORD_HASH}"
  account_mode=builder-supplied
else
  command -v openssl >/dev/null 2>&1 || {
    echo "openssl is required to generate the public development password" >&2
    exit 1
  }
  password_hash="$(openssl passwd -6 -salt histbemuelec emuelec)"
  account_mode=public-development-default
fi
case "${password_hash}" in
  '!') account_mode=locked ;;
  *:*|*[$'\r\n\t ']*|'')
    echo "HISTB_ROOT_PASSWORD_HASH has an invalid form" >&2
    exit 1
    ;;
  '$'*'$'*) ;;
  *)
    echo "HISTB_ROOT_PASSWORD_HASH must be a modular crypt hash or !" >&2
    exit 1
    ;;
esac

temp="${SHADOW}.histb-new"
trap 'rm -f "${temp}"' EXIT
awk -F: -v OFS=: -v replacement="${password_hash}" '
  $1 == "root" { $2 = replacement }
  { print }
' "${SHADOW}" >"${temp}"
chmod --reference="${SHADOW}" "${temp}"
chown --reference="${SHADOW}" "${temp}" 2>/dev/null || true
mv -f "${temp}" "${SHADOW}"
trap - EXIT

if [[ "${account_mode}" = public-development-default ]]; then
  mkdir -p "${HISTB_TARGET_ROOT}/etc"
  cat >"${HISTB_TARGET_ROOT}/etc/motd" <<'EOF'
Hi3798MV100 EmuELEC player build
Default development login is enabled. Run `passwd` after the first SSH login.
EOF
fi

key_mode=none
if [[ -n "${HISTB_ROOT_AUTHORIZED_KEYS_FILE:-}" ]]; then
  key_source="$(readlink -f "${HISTB_ROOT_AUTHORIZED_KEYS_FILE}")"
  [[ -f "${key_source}" && -s "${key_source}" ]] || {
    echo "HISTB_ROOT_AUTHORIZED_KEYS_FILE is not a non-empty file" >&2
    exit 1
  }
  install -d -m 0700 "${HISTB_TARGET_ROOT}/root/.ssh"
  install -m 0600 "${key_source}" \
    "${HISTB_TARGET_ROOT}/root/.ssh/authorized_keys"
  key_mode=injected
fi

mkdir -p "${HISTB_WORK_ROOT}/artifacts"
printf 'root_account=%s\nauthorized_keys=%s\n' "${account_mode}" "${key_mode}" \
  >"${HISTB_WORK_ROOT}/artifacts/root-account-policy.txt"
echo "Root account policy applied: ${account_mode}; authorized keys: ${key_mode}"
