#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTB_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MOUNTER="${HISTB_DIR}/rootfs-overlay/usr/bin/histb-tf-storage"
SELECTOR="${HISTB_DIR}/rootfs-overlay/usr/bin/histb-tf-core-select"
TEST_PARENT="$(mktemp -d)"
trap 'rm -rf -- "${TEST_PARENT}"' EXIT HUP INT TERM

mkdir -p \
  "${TEST_PARENT}/sys/class/block/mmcblk0/device" \
  "${TEST_PARENT}/sys/class/block/mmcblk0p9" \
  "${TEST_PARENT}/sys/class/block/mmcblk1/device" \
  "${TEST_PARENT}/sys/class/block/mmcblk1p1" \
  "${TEST_PARENT}/sys/dev/block/179:9" \
  "${TEST_PARENT}/proc/self" "${TEST_PARENT}/dev" \
  "${TEST_PARENT}/run" "${TEST_PARENT}/mock-bin"
printf 'MMC\n' >"${TEST_PARENT}/sys/class/block/mmcblk0/device/type"
printf '9\n' >"${TEST_PARENT}/sys/class/block/mmcblk0p9/partition"
printf 'SD\n' >"${TEST_PARENT}/sys/class/block/mmcblk1/device/type"
printf '1\n' >"${TEST_PARENT}/sys/class/block/mmcblk1p1/partition"
printf 'DEVNAME=mmcblk0p9\n' >"${TEST_PARENT}/sys/dev/block/179:9/uevent"
printf '24 1 179:9 / / rw - ext4 /dev/mmcblk0p9 rw\n' \
  >"${TEST_PARENT}/proc/self/mountinfo"
printf 'nodev\tsysfs\n\text4\n\tvfat\n\texfat\n' \
  >"${TEST_PARENT}/proc/filesystems"
: >"${TEST_PARENT}/proc/mounts"
: >"${TEST_PARENT}/dev/mmcblk0p9"
: >"${TEST_PARENT}/dev/mmcblk1p1"

cat >"${TEST_PARENT}/mock-bin/blkid" <<'EOF'
#!/bin/sh
field=
device=
while [ "$#" -gt 0 ]; do
  case "$1" in -s) field=$2; shift 2 ;; -o) shift 2 ;; *) device=$1; shift ;; esac
done
case "${device##*/}:${field}" in
  mmcblk0p9:TYPE) echo ext4 ;; mmcblk0p9:UUID) echo INTERNAL-UUID ;;
  mmcblk1p1:TYPE) echo "${MOCK_TF_FS:-ext4}" ;; mmcblk1p1:UUID) echo TF-UUID ;;
  mmcblk1p1:LABEL) echo EMUELEC ;;
esac
EOF
cat >"${TEST_PARENT}/mock-bin/mountpoint" <<'EOF'
#!/bin/sh
[ -f "${HISTB_TF_TEST_ROOT}/run/mounted" ]
EOF
cat >"${TEST_PARENT}/mock-bin/mount" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"${HISTB_TF_TEST_ROOT}/run/mount.args"
touch "${HISTB_TF_TEST_ROOT}/run/mounted"
printf '%s %s test rw 0 0\n' "${HISTB_TF_TEST_ROOT}/dev/mmcblk1p1" "${HISTB_TF_MOUNT}" \
  >"${HISTB_TF_TEST_ROOT}/proc/mounts"
EOF
cat >"${TEST_PARENT}/mock-bin/umount" <<'EOF'
#!/bin/sh
rm -f "${HISTB_TF_TEST_ROOT}/run/mounted"
: >"${HISTB_TF_TEST_ROOT}/proc/mounts"
EOF
chmod 0755 "${TEST_PARENT}/mock-bin/"*

# With no external SD device, the helper leaves no state behind.  The init
# wrapper deliberately absorbs this result so the internal eMMC still boots.
rm -f "${TEST_PARENT}/sys/class/block/mmcblk1/device/type"
if HISTB_TF_TEST_ROOT="${TEST_PARENT}" \
  HISTB_TF_MOUNT="${TEST_PARENT}/media/emuelec-tf" \
  PATH="${TEST_PARENT}/mock-bin:${PATH}" \
    "${MOUNTER}" start >/dev/null 2>&1; then
  echo 'missing-card scan unexpectedly succeeded' >&2
  exit 1
fi
[[ ! -e "${TEST_PARENT}/run/histb-tf-storage.env" ]]
printf 'SD\n' >"${TEST_PARENT}/sys/class/block/mmcblk1/device/type"

run_mount_test()
{
  fs=$1
  expected_mode=$2
  rm -f "${TEST_PARENT}/run/mounted" "${TEST_PARENT}/run/mount.args" \
    "${TEST_PARENT}/run/histb-tf-storage.env"
  : >"${TEST_PARENT}/proc/mounts"
  HISTB_TF_TEST_ROOT="${TEST_PARENT}" \
  HISTB_TF_MOUNT="${TEST_PARENT}/media/emuelec-tf" \
  HISTB_TF_UUID=TF-UUID MOCK_TF_FS="${fs}" \
  PATH="${TEST_PARENT}/mock-bin:${PATH}" \
    "${MOUNTER}" start >/dev/null
  grep -Fxq "device=${TEST_PARENT}/dev/mmcblk1p1" \
    "${TEST_PARENT}/run/histb-tf-storage.env"
  grep -Fxq "core_mode=${expected_mode}" \
    "${TEST_PARENT}/run/histb-tf-storage.env"
  if [ "${fs}" = ext4 ]; then
    grep -Fq 'nodev,nosuid,noatime,exec' "${TEST_PARENT}/run/mount.args"
    ! grep -Fq 'noexec' "${TEST_PARENT}/run/mount.args"
  else
    grep -Fq 'nodev,nosuid,noatime,noexec' "${TEST_PARENT}/run/mount.args"
  fi
}

run_mount_test ext4 direct
run_mount_test vfat cache
run_mount_test exfat cache

mkdir -p "${TEST_PARENT}/media/emuelec-tf/EmuELEC/cores" \
  "${TEST_PARENT}/storage/ee" "${TEST_PARENT}/runtime/bin"
core="${TEST_PARENT}/media/emuelec-tf/EmuELEC/cores/fceumm_libretro.so"
dd if=/dev/zero of="${core}" bs=1 count=64 status=none
printf '\177ELF\001\001' | dd of="${core}" bs=1 seek=0 conv=notrunc status=none
printf '\050\000' | dd of="${core}" bs=1 seek=18 conv=notrunc status=none
core_sha=$(sha256sum "${core}" | awk '{print $1}')
printf '%s  fceumm_libretro.so\n' "${core_sha}" \
  >"${TEST_PARENT}/media/emuelec-tf/EmuELEC/cores/cores.sha256"
cat >"${TEST_PARENT}/runtime/bin/histb-runtime-exec" <<'EOF'
#!/bin/sh
exit 0
EOF
cp "${TEST_PARENT}/runtime/bin/histb-runtime-exec" \
  "${TEST_PARENT}/runtime/bin/histb-core-probe"
chmod 0755 "${TEST_PARENT}/runtime/bin/"*

# ext4 direct mode returns the TF path after the same hash/ELF/dlopen probe.
sed -i 's/^core_mode=.*/core_mode=direct/' \
  "${TEST_PARENT}/run/histb-tf-storage.env"
direct_selected=$(HISTB_TF_STATE_FILE="${TEST_PARENT}/run/histb-tf-storage.env" \
  HISTB_EE_ROOT="${TEST_PARENT}/runtime" HISTB_STORAGE_ROOT="${TEST_PARENT}/storage" \
  HISTB_TF_TEST_ROOT="${TEST_PARENT}" PATH="${TEST_PARENT}/mock-bin:${PATH}" \
  "${SELECTOR}" fceumm)
[ "${direct_selected}" = "${core}" ]

sed -i 's/^core_mode=.*/core_mode=cache/' \
  "${TEST_PARENT}/run/histb-tf-storage.env"
selected=$(HISTB_TF_STATE_FILE="${TEST_PARENT}/run/histb-tf-storage.env" \
  HISTB_EE_ROOT="${TEST_PARENT}/runtime" HISTB_STORAGE_ROOT="${TEST_PARENT}/storage" \
  HISTB_TF_TEST_ROOT="${TEST_PARENT}" PATH="${TEST_PARENT}/mock-bin:${PATH}" \
  "${SELECTOR}" fceumm)
case "${selected}" in "${TEST_PARENT}/storage/ee/core-cache/fceumm/${core_sha}.so") ;; *) exit 1 ;; esac
cmp "${core}" "${selected}"

# Setting the ARM hard-float flag must reject the candidate without removing
# the previously imported, content-addressed rollback copy.
printf '\004' | dd of="${core}" bs=1 seek=37 conv=notrunc status=none
hard_sha=$(sha256sum "${core}" | awk '{print $1}')
printf '%s  fceumm_libretro.so\n' "${hard_sha}" \
  >"${TEST_PARENT}/media/emuelec-tf/EmuELEC/cores/cores.sha256"
if HISTB_TF_STATE_FILE="${TEST_PARENT}/run/histb-tf-storage.env" \
  HISTB_EE_ROOT="${TEST_PARENT}/runtime" HISTB_STORAGE_ROOT="${TEST_PARENT}/storage" \
  HISTB_TF_TEST_ROOT="${TEST_PARENT}" PATH="${TEST_PARENT}/mock-bin:${PATH}" \
  "${SELECTOR}" fceumm >/dev/null 2>&1; then
  echo 'hard-float TF core was not rejected' >&2
  exit 1
fi
[ -f "${selected}" ]

echo 'PASS: no-card fallback, external-SD selection, filesystem mount modes, verified TF core cache, and ABI rejection'
