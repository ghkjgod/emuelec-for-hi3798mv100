#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=../WORKSPACE.lock
source "${WORKSPACE_ROOT}/WORKSPACE.lock"

JOBS="${HISTB_JOBS:-2}"
case "${JOBS}" in
  ''|*[!0-9]*|0) echo "HISTB_JOBS must be a positive integer" >&2; exit 2 ;;
esac

for tool in git rsync sha256sum stat python3; do
  command -v "${tool}" >/dev/null || {
    echo "Setup cannot continue because '${tool}' is missing." >&2
    echo "On Ubuntu, install the packages shown in README, then run ./easy-build.sh again." >&2
    exit 1
  }
done

work_fs="$(stat -f -c %T "${WORKSPACE_ROOT}" 2>/dev/null || true)"
case "${work_fs}" in
  ext2/ext3|ext4) ;;
  *)
    echo "Setup cannot continue: this folder is on ${work_fs:-an unknown filesystem}, not Linux ext4: ${WORKSPACE_ROOT}" >&2
    echo "On Windows, open the Ubuntu WSL terminal and clone into your Linux home folder, for example ~/emuelec-for-hi3798mv100." >&2
    echo "Do not build below /mnt/c, /mnt/d, or /mnt/e." >&2
    exit 1
    ;;
esac

clone_locked_checkout() {
  local name="$1" url="$2" branch="$3" path="$4" commit="$5"
  if [[ ! -d "${path}/.git" && ! -f "${path}/.git" ]]; then
    if [[ -e "${path}" && -n "$(find "${path}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
      echo "refusing to replace non-Git ${name} directory: ${path}" >&2
      exit 1
    fi
    rm -d "${path}" 2>/dev/null || true
    git clone --depth 1 --single-branch --branch "${branch}" "${url}" "${path}"
  fi
  git -C "${path}" checkout --detach "${commit}"
}

if git -C "${WORKSPACE_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "${WORKSPACE_ROOT}" submodule sync --recursive
  git -C "${WORKSPACE_ROOT}" submodule update \
    --init --recursive --jobs "${JOBS}" --depth 1 -- sdk emuelec
else
  # GitHub source archives do not contain submodule worktrees.  Keep the same
  # one-command setup by cloning the exact locked tips ourselves.
  clone_locked_checkout SDK "${HISTB_SDK_URL}" master \
    "${WORKSPACE_ROOT}/sdk" "${HISTB_SDK_COMMIT}"
  clone_locked_checkout EmuELEC "${HISTB_EMUELEC_URL}" master_32bit \
    "${WORKSPACE_ROOT}/emuelec" "${HISTB_EMUELEC_COMMIT}"
fi

verify_checkout() {
  local name="$1" path="$2" expected="$3" actual
  actual="$(git -C "${path}" rev-parse HEAD)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "${name} checkout mismatch: expected ${expected}, got ${actual}" >&2
    exit 1
  fi
}

verify_checkout SDK "${WORKSPACE_ROOT}/sdk" "${HISTB_SDK_COMMIT}"
verify_checkout EmuELEC "${WORKSPACE_ROOT}/emuelec" "${HISTB_EMUELEC_COMMIT}"

sdk_config="${WORKSPACE_ROOT}/sdk/configs/hi3798mv100/hi3798mdmo1g_hi3798mv100_cfg.mak"
actual_config_sha="$(sha256sum "${sdk_config}" | awk '{print $1}')"
if [[ "${actual_config_sha}" != "${HISTB_SDK_CONFIG_SHA256}" ]]; then
  echo "SDK board config mismatch: ${actual_config_sha}" >&2
  exit 1
fi

port_source="${WORKSPACE_ROOT}/port"
port_target="${WORKSPACE_ROOT}/emuelec/tools/histb"
managed_marker="${port_target}/.histb-workspace-managed"
if [[ -e "${port_target}" && ! -f "${managed_marker}" ]]; then
  if [[ -n "$(find "${port_target}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
    echo "refusing to overwrite unmanaged EmuELEC tools/histb: ${port_target}" >&2
    exit 1
  fi
fi
mkdir -p "${port_target}"
rsync -a --delete --exclude='.histb-workspace-managed' \
  "${port_source}/" "${port_target}/"
printf '%s\n' "managed-by=${WORKSPACE_ROOT}" >"${managed_marker}"

python3 "${port_target}/tests/test-es-command-argv.py" \
  "${port_target}/runtime/etc/emulationstation/es_systems.cfg"
"${port_target}/tests/test-fullflash-config.sh"
"${port_target}/tests/test-runtime-exec.sh"
"${port_target}/tests/test-es-systems-upgrade.sh"
"${port_target}/tests/test-supervisor-state.sh"
"${port_target}/tests/test-tf-storage.sh"
"${port_target}/tests/test-controller-db.sh"
"${WORKSPACE_ROOT}/scripts/check-tf-card-tree.sh" "${WORKSPACE_ROOT}/tf-card"

cat <<EOF
Workspace ready.
  SDK:      ${HISTB_SDK_COMMIT}
  EmuELEC:  ${HISTB_EMUELEC_COMMIT}
  Port:     ${port_target}

Build everything with:
  ./scripts/build-workspace.sh
EOF
