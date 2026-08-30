#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

DROPBEAR_VERSION=2026.94
DROPBEAR_SHA256=e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81
SOURCE_ARCHIVE="${HISTB_WORK_ROOT}/cache/sources/dropbear-${DROPBEAR_VERSION}.tar.bz2"
BUILD_ROOT="${HISTB_WORK_ROOT}/build/dropbear-${DROPBEAR_VERSION}"
SOURCE_ROOT="${BUILD_ROOT}/src"
OUTPUT_ROOT="${BUILD_ROOT}/output"
OUTPUT="${OUTPUT_ROOT}/dropbearmulti"
REPORT="${HISTB_WORK_ROOT}/artifacts/dropbear-build-info.txt"

case "${BUILD_ROOT}" in "${HISTB_WORK_ROOT}/build/"*) ;; *)
  echo "unsafe Dropbear build root: ${BUILD_ROOT}" >&2
  exit 1
  ;;
esac
[[ -f "${SOURCE_ARCHIVE}" ]] || {
  echo "pinned Dropbear source archive is missing: ${SOURCE_ARCHIVE}" >&2
  exit 1
}
actual_source_sha="$(sha256sum "${SOURCE_ARCHIVE}" | awk '{print $1}')"
[[ "${actual_source_sha}" = "${DROPBEAR_SHA256}" ]] || {
  echo "Dropbear source checksum mismatch: ${actual_source_sha}" >&2
  exit 1
}

rm -rf -- "${BUILD_ROOT}"
mkdir -p "${SOURCE_ROOT}" "${OUTPUT_ROOT}" "$(dirname "${REPORT}")"
tar -xjf "${SOURCE_ARCHIVE}" -C "${SOURCE_ROOT}" --strip-components=1

(
  cd "${SOURCE_ROOT}"
  ./configure \
    --host=arm-histbv310-linux \
    --prefix=/usr \
    --disable-zlib \
    --disable-harden \
    --disable-syslog \
    --disable-lastlog \
    --disable-utmp \
    --disable-utmpx \
    --disable-wtmp \
    --disable-wtmpx \
    --disable-pututline \
    --disable-pututxline \
    CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" \
    CPPFLAGS="--sysroot=${HISTB_SYSROOT}" \
    CFLAGS="${HISTB_ARCH_FLAGS} -Os" \
    LDFLAGS="--sysroot=${HISTB_SYSROOT}"
  make -s -j"$(nproc)" PROGRAMS='dropbear dropbearkey' MULTI=1
  "${STRIP}" -o "${OUTPUT}" dropbearmulti
)

"${SCRIPT_DIR}/check-elf-abi.sh" "${OUTPUT}"
"${READELF}" -d "${OUTPUT}" | grep -Fq 'Shared library: [libcrypt.so.1]'
"${READELF}" -d "${OUTPUT}" | grep -Fq 'Shared library: [libc.so.6]'
! strings "${OUTPUT}" | grep -Fq "${BUILD_ROOT}"
output_sha="$(sha256sum "${OUTPUT}" | awk '{print $1}')"
cat >"${REPORT}.new" <<EOF
dropbear_version=${DROPBEAR_VERSION}
source_sha256=${DROPBEAR_SHA256}
binary_sha256=${output_sha}
binary_size=$(stat -c %s "${OUTPUT}")
programs=dropbear,dropbearkey
abi=ARMv7_EABI5_softfp
interpreter=/lib/ld-linux.so.3
result=PASS
EOF
mv -f "${REPORT}.new" "${REPORT}"

echo "Dropbear target build: ${OUTPUT}"
echo "Dropbear SHA-256: ${output_sha}"
