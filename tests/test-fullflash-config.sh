#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OVERLAY="${HISTB_DIR}/rootfs-overlay"

bash -n \
  "${HISTB_DIR}/build-all.sh" \
  "${HISTB_DIR}/build-dropbear.sh" \
  "${HISTB_DIR}/install-dropbear-rootbox.sh" \
  "${HISTB_DIR}/configure-root-account.sh" \
  "${HISTB_DIR}/prepare-sdk-integration.sh" \
  "${HISTB_DIR}/normalize-rootfs-image.sh" \
  "${HISTB_DIR}/check-rootfs-image.sh" \
  "${HISTB_DIR}/package-release.sh"
sh -n \
  "${OVERLAY}/usr/bin/histb-storage-guard" \
  "${OVERLAY}/usr/bin/histb-storage-init" \
  "${OVERLAY}/usr/bin/histb-release-rollback" \
  "${OVERLAY}/usr/bin/histb-emuelec-stop" \
  "${OVERLAY}/etc/init.d/S81histb-network" \
  "${OVERLAY}/etc/init.d/S82dropbear" \
  "${OVERLAY}/etc/init.d/S95emuelec" \
  "${HISTB_DIR}/runtime/bin/run-emulationstation.sh" \
  "${HISTB_DIR}/runtime/bin/run-retroarch.sh" \
  "${HISTB_DIR}/runtime/bin/emuelec-utils" \
  "${HISTB_DIR}/target/install-release.sh"

grep -Fq "CFG_HI_EMMC_ROOTFS_SIZE=6846" \
  "${HISTB_DIR}/prepare-sdk-integration.sh"
grep -Fq 'ROOTFS_LOGICAL_SIZE=7178551296' \
  "${HISTB_DIR}/normalize-rootfs-image.sh"
grep -Fq 'rootfs_6846M.ext4' "${HISTB_DIR}/normalize-rootfs-image.sh"
grep -Fq 'rootfs_6846M.ext4' "${HISTB_DIR}/check-rootfs-image.sh"
grep -Fq 'rootfs_6846M.ext4' "${HISTB_DIR}/package-release.sh"
grep -Fq -- "-path 'tools/histb/.git' -prune" "${HISTB_DIR}/package-release.sh"
! grep -R -Fq 'rootfs_128M.ext4' \
  "${HISTB_DIR}/normalize-rootfs-image.sh" \
  "${HISTB_DIR}/check-rootfs-image.sh" \
  "${HISTB_DIR}/package-release.sh"

grep -qx 'histb-emuelec-p9-root-storage-v1' \
  "${OVERLAY}/etc/histb-emuelec-p9-root-storage-v1"
grep -qx 'histb-emuelec-storage-v1' \
  "${OVERLAY}/storage/.histb-emuelec-storage-v1"
[[ -f "${OVERLAY}/storage/ee/enable-autostart" ]]
[[ ! -e "${OVERLAY}/storage/ee/disable-autostart" ]]
[[ ! -e "${OVERLAY}/storage/roms/nes/HiSTB AV Input Test.nes" ]]
grep -Fq "DEVNAME=mmcblk0p9" "${OVERLAY}/usr/bin/histb-storage-guard"
grep -Fq "/dev/mmcblk0p13" "${OVERLAY}/usr/bin/histb-storage-guard"
grep -Fq 'refusing a separate /storage mount' \
  "${OVERLAY}/usr/bin/histb-storage-guard"
for launcher in run-emulationstation.sh run-retroarch.sh; do
  grep -Fq '/usr/bin/histb-storage-guard --require-marker' \
    "${HISTB_DIR}/runtime/bin/${launcher}"
done
for state_tool in \
  "${HISTB_DIR}/target/install-release.sh" \
  "${OVERLAY}/usr/bin/histb-release-rollback"; do
  grep -Fq '/usr/bin/histb-storage-guard --require-marker' "${state_tool}"
  ! grep -Fq 'mountpoint -q /storage' "${state_tool}"
done

grep -Fq 'HISTB_ENABLE_NETWORK:=1' \
  "${OVERLAY}/etc/default/histb-network"
grep -Fq 'HISTB_ENABLE_NETWORK' \
  "${OVERLAY}/etc/init.d/S81histb-network"
! grep -Eq '^[[:space:]]*(route|ip route)[[:space:]]' \
  "${OVERLAY}/etc/init.d/S81histb-network"
grep -Fq 'HISTB_ENABLE_SSH:=1' \
  "${OVERLAY}/etc/default/histb-ssh"
grep -Fq 'HISTB_SSH_BIND_ADDRESS:=0.0.0.0' \
  "${OVERLAY}/etc/default/histb-ssh"
grep -Fq 'HISTB_SSH_ALLOW_PASSWORD:=1' \
  "${OVERLAY}/etc/default/histb-ssh"
grep -Fq 'HISTB_ENABLE_SSH' \
  "${OVERLAY}/etc/init.d/S82dropbear"
grep -Fq 'HISTB_SSH_ALLOW_PASSWORD' \
  "${OVERLAY}/etc/init.d/S82dropbear"
grep -Fq 'PASSWORD_ARGS=-s' \
  "${OVERLAY}/etc/init.d/S82dropbear"
! grep -Eq '(^|[[:space:]])-E([[:space:]]|$)' \
  "${OVERLAY}/etc/init.d/S82dropbear"
grep -Fq 'Dropbear failed to start' \
  "${OVERLAY}/etc/init.d/S82dropbear"
grep -Fq 'Dropbear did not remain running' \
  "${OVERLAY}/etc/init.d/S82dropbear"
grep -Fq 'kill -0 "$(cat "${PID_FILE}")"' \
  "${OVERLAY}/etc/init.d/S82dropbear"
grep -Fq 'DROPBEAR_VERSION=2026.94' "${HISTB_DIR}/build-dropbear.sh"
grep -Fq 'e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81' \
  "${HISTB_DIR}/build-dropbear.sh"

grep -Fq '62509737c2f732b81ce7bf37f6c4c3b82dafae28' \
  "${HISTB_DIR}/stage-runtime.sh"
grep -Fq '214bb1bb7245caa1a31cf6c28ffebb8c0bce24fd3b656890a5e9ea2428bdf97e' \
  "${HISTB_DIR}/stage-runtime.sh"
grep -Fq 'HiSTB-EmuELEC-carbon/nes/theme.xml' \
  "${HISTB_DIR}/package-release.sh"
grep -Fq 'THEME_LINK=${THEME_ROOT}/HiSTB-EmuELEC-carbon' \
  "${HISTB_DIR}/runtime/bin/run-emulationstation.sh"
grep -Fq '/proc/[0-9]*' "${OVERLAY}/usr/bin/histb-emuelec-stop"
grep -Fq "tr '\\000' '\\n'" "${OVERLAY}/usr/bin/histb-emuelec-stop"
grep -Fq '/opt/emuelec/bin/retroarch' \
  "${OVERLAY}/usr/bin/histb-emuelec-stop"
! grep -Fq 'killall retroarch' "${OVERLAY}/usr/bin/histb-emuelec-stop"
grep -Fq 'HISTB_XPAD_NEW_ID' "${OVERLAY}/etc/init.d/S95emuelec"
grep -Fq '/sys/bus/usb/drivers/xpad/new_id' \
  "${OVERLAY}/etc/init.d/S95emuelec"
grep -Fq 'HISTB_ROOT_PASSWORD_HASH' \
  "${HISTB_DIR}/configure-root-account.sh"
grep -Fq 'HISTB_ROOT_AUTHORIZED_KEYS_FILE' \
  "${HISTB_DIR}/configure-root-account.sh"
! grep -Eq 'root:[^!:*][^:]*:' \
  "${HISTB_DIR}/configure-root-account.sh"
grep -Fq 'openssl passwd -6 -salt histbemuelec emuelec' \
  "${HISTB_DIR}/configure-root-account.sh"

printf '%s\n' 'PASS: storage guard, default autostart, player-default network/SSH, and controller compatibility recipe'
