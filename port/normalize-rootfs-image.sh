#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null
# shellcheck source=rootfs-image-lib.sh
source "${SCRIPT_DIR}/rootfs-image-lib.sh"

histb_prepare_sparse_tools
for command_name in e2fsck dumpe2fs dd od cmp stat file sha256sum; do
  command -v "${command_name}" >/dev/null || {
    echo "missing rootfs normalization command: ${command_name}" >&2
    exit 1
  }
done

ROOTFS_LOGICAL_SIZE=7178551296
ROOTFS_BLOCK_SIZE=4096
ROOTFS_BLOCK_COUNT=1752576
SPARSE_IMAGE="${HISTB_OUT_ROOT}/image/emmc_image/rootfs_6846M.ext4"
WORK_DIR="${HISTB_WORK_ROOT}/build/rootfs-normalize"
RAW_IMAGE="${WORK_DIR}/rootfs.raw.ext4"
CANDIDATE_IMAGE="${WORK_DIR}/rootfs.normalized.sparse.ext4"
VERIFY_RAW="${WORK_DIR}/rootfs.verify.raw.ext4"
INFO_FILE="${HISTB_WORK_ROOT}/artifacts/rootfs-image-info.txt"

case "${WORK_DIR}" in "${HISTB_WORK_ROOT}/build/"*) ;; *)
  echo "unsafe rootfs normalization directory: ${WORK_DIR}" >&2
  exit 1
  ;;
esac
[[ -f "${SPARSE_IMAGE}" ]] || {
  echo "sparse rootfs image is missing: ${SPARSE_IMAGE}" >&2
  exit 1
}
rm -rf -- "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "$(dirname "${INFO_FILE}")"
cleanup()
{
  rm -rf -- "${WORK_DIR}"
}
trap cleanup EXIT HUP INT TERM

"${HISTB_SIMG2IMG}" "${SPARSE_IMAGE}" "${RAW_IMAGE}"
[[ "$(stat -c %s "${RAW_IMAGE}")" = "${ROOTFS_LOGICAL_SIZE}" ]] || {
  echo "unexpected rootfs logical size: $(stat -c %s "${RAW_IMAGE}")" >&2
  exit 1
}
magic="$(od -An -tx2 -j 1080 -N 2 "${RAW_IMAGE}" | tr -d '[:space:]')"
[[ "${magic}" = ef53 ]] || {
  echo "invalid ext filesystem magic: ${magic}" >&2
  exit 1
}

set +e
e2fsck -fy "${RAW_IMAGE}"
fsck_repair_rc=$?
set -e
case "${fsck_repair_rc}" in 0|1) ;; *)
  echo "e2fsck repair failed with status ${fsck_repair_rc}" >&2
  exit "${fsck_repair_rc}"
  ;;
esac

# e2fsck fixes old make_ext4fs inode-bitmap padding but stamps wall-clock
# fields. The full 6846 MiB filesystem has backup superblocks, so normalize
# s_wtime (0x30) and s_lastcheck (0x40) in the primary and every backup.
mapfile -t backup_superblocks < <(
  dumpe2fs "${RAW_IMAGE}" 2>/dev/null |
    sed -n 's/.*Backup superblock at \([0-9][0-9]*\).*/\1/p'
)
superblocks=(0 "${backup_superblocks[@]}")
for superblock in "${superblocks[@]}"; do
  if [[ "${superblock}" = 0 ]]; then
    super_offset=1024
  else
    super_offset=$((superblock * ROOTFS_BLOCK_SIZE))
  fi
  dd if=/dev/zero of="${RAW_IMAGE}" bs=1 seek=$((super_offset + 48)) \
    count=4 conv=notrunc status=none
  dd if=/dev/zero of="${RAW_IMAGE}" bs=1 seek=$((super_offset + 64)) \
    count=4 conv=notrunc status=none
  [[ "$(od -An -tu4 -j $((super_offset + 48)) -N 4 "${RAW_IMAGE}" | tr -d '[:space:]')" = 0 ]]
  [[ "$(od -An -tu4 -j $((super_offset + 64)) -N 4 "${RAW_IMAGE}" | tr -d '[:space:]')" = 0 ]]
done
e2fsck -fn "${RAW_IMAGE}"

fs_header="$(dumpe2fs -h "${RAW_IMAGE}" 2>/dev/null)"
grep -Eq '^Filesystem state:[[:space:]]+clean$' <<<"${fs_header}"
inode_count="$(awk -F: '/^Inode count:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' <<<"${fs_header}")"
block_count="$(awk -F: '/^Block count:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' <<<"${fs_header}")"
block_size="$(awk -F: '/^Block size:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' <<<"${fs_header}")"
[[ "${inode_count}" =~ ^[0-9]+$ && "${inode_count}" -gt 8192 ]]
[[ "${block_count}" = "${ROOTFS_BLOCK_COUNT}" ]]
[[ "${block_size}" = "${ROOTFS_BLOCK_SIZE}" ]]

"${HISTB_IMG2SIMG}" "${RAW_IMAGE}" "${CANDIDATE_IMAGE}"
file "${CANDIDATE_IMAGE}" | grep -q 'Android sparse image, version: 1.0'
"${HISTB_SIMG2IMG}" "${CANDIDATE_IMAGE}" "${VERIFY_RAW}"
cmp "${RAW_IMAGE}" "${VERIFY_RAW}"
e2fsck -fn "${VERIFY_RAW}"

mv -f "${CANDIDATE_IMAGE}" "${SPARSE_IMAGE}"
image_sha="$(sha256sum "${SPARSE_IMAGE}" | awk '{print $1}')"
cat >"${INFO_FILE}.new" <<EOF
format=Android sparse 1.0
logical_size=${ROOTFS_LOGICAL_SIZE}
sparse_size=$(stat -c %s "${SPARSE_IMAGE}")
sha256=${image_sha}
filesystem=ext4
inode_count=${inode_count}
block_count=${block_count}
block_size=${block_size}
normalized_superblocks=${#superblocks[@]}
fsck_repair_exit=${fsck_repair_rc}
fsck_read_only=clean
superblock_wtime=0
superblock_lastcheck=0
raw_round_trip=identical
EOF
mv -f "${INFO_FILE}.new" "${INFO_FILE}"

echo "Normalized rootfs image: ${SPARSE_IMAGE}"
echo "Rootfs SHA-256: ${image_sha}"
