#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

SDK_CONFIG_SOURCE="${HISTB_SDK_ROOT}/configs/hi3798mv100/hi3798mdmo1g_hi3798mv100_cfg.mak"
SDK_CONFIG_SHA256=b73800e5ba039d9e8d67a1c10498e19d69efed24f8801e067ace1b212cdace95
SDK_PATCH="${SCRIPT_DIR}/patches/SDK-rootbox-HiSTB.patch"

actual_config_sha="$(sha256sum "${SDK_CONFIG_SOURCE}" | awk '{print $1}')"
if [[ "${actual_config_sha}" != "${SDK_CONFIG_SHA256}" ]]; then
  echo "pinned SDK configuration checksum mismatch: ${actual_config_sha}" >&2
  exit 1
fi
install -m 0644 "${SDK_CONFIG_SOURCE}" "${HISTB_SDK_ROOT}/cfg.mak"
[[ "$(grep -c '^CFG_HI_EMMC_ROOTFS_SIZE=128$' "${HISTB_SDK_ROOT}/cfg.mak")" = 1 ]] || {
  echo "pinned SDK config no longer has the expected 128 MiB rootfs setting" >&2
  exit 1
}
sed -i 's/^CFG_HI_EMMC_ROOTFS_SIZE=128$/CFG_HI_EMMC_ROOTFS_SIZE=6846/' \
  "${HISTB_SDK_ROOT}/cfg.mak"
grep -qx 'CFG_HI_EMMC_ROOTFS_SIZE=6846' "${HISTB_SDK_ROOT}/cfg.mak"

if git -C "${HISTB_SDK_ROOT}" apply --reverse --check "${SDK_PATCH}" >/dev/null 2>&1; then
  :
elif git -C "${HISTB_SDK_ROOT}" apply --check "${SDK_PATCH}" >/dev/null 2>&1; then
  git -C "${HISTB_SDK_ROOT}" apply "${SDK_PATCH}"
else
  echo "SDK rootbox.mak is neither the pinned base nor the expected HiSTB patch state" >&2
  exit 1
fi

grep -Fq 'HISTB_EMUELEC_ROOTFS_OVERLAY ?= $(HISTB_EMUELEC_TOOL_ROOT)/rootfs-overlay' \
  "${HISTB_SDK_ROOT}/rootbox.mak"
grep -Fq '$(AT)cp -arf $(HISTB_EMUELEC_ROOTFS_OVERLAY)/. $(HI_ROOTBOX_DIR)/' \
  "${HISTB_SDK_ROOT}/rootbox.mak"
for required in \
  rootfs-overlay/etc/init.d/S90modules \
  rootfs-overlay/etc/init.d/S81histb-network \
  rootfs-overlay/etc/init.d/S82dropbear \
  rootfs-overlay/etc/init.d/S95emuelec \
  rootfs-overlay/usr/bin/histb-emuelec-supervisor \
  rootfs-overlay/usr/bin/histb-emuelec-stop \
  rootfs-overlay/usr/bin/histb-storage-init \
  rootfs-overlay/usr/bin/histb-storage-guard \
  rootfs-overlay/emuelec/scripts/emuelec-utils \
  target/install-release.sh; do
  [[ -x "${SCRIPT_DIR}/${required}" ]] || {
    echo "missing executable SDK integration input: ${SCRIPT_DIR}/${required}" >&2
    exit 1
  }
done
git -C "${HISTB_SDK_ROOT}" diff --check -- rootbox.mak

echo "SDK integration ready: hi3798mdmo1g config ${SDK_CONFIG_SHA256}, p9 rootfs 6846 MiB"
