#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

ROOTFS_IMAGE="${HISTB_OUT_ROOT}/image/emmc_image/rootfs_6846M.ext4"
IMAGE_INFO="${HISTB_WORK_ROOT}/artifacts/rootfs-image-info.txt"
IMAGE_AUDIT="${HISTB_WORK_ROOT}/artifacts/rootfs-image-audit.txt"
RELEASE_STAGE="${HISTB_WORK_ROOT}/build/release-package"
FLASH_ROOT="${HISTB_WORK_ROOT}/artifacts/flash"
TF_PACKAGE="${HISTB_WORK_ROOT}/artifacts/tf-card"
SPARSE_SPLITTER="${SCRIPT_DIR}/split-android-sparse-raw-chunks.py"
TRANSPORT_RAW_CHUNK_MAX=4194304

for required in "${ROOTFS_IMAGE}" "${IMAGE_INFO}" "${IMAGE_AUDIT}" "${SPARSE_SPLITTER}"; do
  [[ -f "${required}" ]] || { echo "full build did not produce required output: ${required}" >&2; exit 1; }
done
for required in \
    "${TF_PACKAGE}/MANIFEST.sha256" \
    "${TF_PACKAGE}/EmuELEC/cores/cores.sha256" \
    "${TF_PACKAGE}/EmuELEC/config/gamecontrollerdb.sha256"; do
  [[ -f "${required}" ]] || { echo "full build did not produce required TF package output: ${required}" >&2; exit 1; }
done
(
  cd "${TF_PACKAGE}"
  sha256sum --check --status MANIFEST.sha256
)

mapfile -t release_ids < <(
  find "${RELEASE_STAGE}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort
)
[[ "${#release_ids[@]}" = 1 ]] || {
  echo "expected exactly one gated release stage, found ${#release_ids[@]}" >&2
  exit 1
}
release_id="${release_ids[0]}"
expected_sha="$(awk -F= '$1 == "sha256" { print $2; count++ } END { if (count != 1) exit 1 }' "${IMAGE_INFO}")" || {
  echo "rootfs image info does not contain one SHA-256 value" >&2
  exit 1
}
actual_sha="$(sha256sum "${ROOTFS_IMAGE}" | awk '{print $1}')"
[[ "${actual_sha}" = "${expected_sha}" ]] || {
  echo "rootfs image changed after its audit: ${actual_sha} != ${expected_sha}" >&2
  exit 1
}
file "${ROOTFS_IMAGE}" | grep -q 'Android sparse image, version: 1.0' || {
  echo "rootfs image is not the qualified Android sparse format" >&2
  exit 1
}

mkdir -p "${FLASH_ROOT}"
output="${FLASH_ROOT}/${release_id}-p9-rootfs.img"
rm -f "${output}.new"
python3 "${SPARSE_SPLITTER}" \
  --max-raw-bytes "${TRANSPORT_RAW_CHUNK_MAX}" \
  "${ROOTFS_IMAGE}" "${output}.new"
mv -f "${output}.new" "${output}"
transport_sha="$(sha256sum "${output}" | awk '{print $1}')"
(
  cd "${FLASH_ROOT}"
  sha256sum "$(basename "${output}")" >"$(basename "${output}").sha256.new"
  mv -f "$(basename "${output}").sha256.new" "$(basename "${output}").sha256"
)
install -m 0644 "${IMAGE_INFO}" "${FLASH_ROOT}/${release_id}-p9-rootfs.info.txt"
install -m 0644 "${IMAGE_AUDIT}" "${FLASH_ROOT}/${release_id}-p9-rootfs.audit.txt"
cat >>"${FLASH_ROOT}/${release_id}-p9-rootfs.audit.txt" <<EOF
transport_sparse_raw_chunk_split=PASS
transport_sparse_sha256=${transport_sha}
transport_source_sparse_sha256=${actual_sha}
transport_raw_chunk_max_bytes=${TRANSPORT_RAW_CHUNK_MAX}
transport_logical_bytes_unchanged=7178551296
EOF
cat >"${FLASH_ROOT}/FLASH-INSTRUCTIONS.txt.new" <<EOF
artifact=$(basename "${output}")
partition=p9/rootfs only
target=EC6108V9C / Hi3798MV100 / verified nine-partition layout
format=Android sparse ext4
logical_size=7178551296
sha256=${transport_sha}
source_rootfs_sha256=${actual_sha}
transport_raw_chunk_max_bytes=${TRANSPORT_RAW_CHUNK_MAX}
transport_reason=keep every official HiBurn gzip transfer below the target 8 MiB load-to-expand address gap
write_scope=official HiBurn rootfs-only p9 workflow
not_a_complete_disk_image=1
do_not_write_to=p1-p8,partition-table,boot0,boot1,RPMB
EOF
mv -f "${FLASH_ROOT}/FLASH-INSTRUCTIONS.txt.new" "${FLASH_ROOT}/FLASH-INSTRUCTIONS.txt"

printf 'PASS: HiBurn p9/rootfs image is ready\n'
printf '  image:  %s\n' "${output}"
printf '  sha256: %s\n' "${transport_sha}"
printf '  scope:  p9/rootfs only; not a complete-disk image\n'
printf '  TF:     %s (copy EmuELEC to card; add licensed BIOS/ROM)\n' "${TF_PACKAGE}"
