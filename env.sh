#!/usr/bin/env bash

# Cross-build environment for the Hi3798MV100 application overlay.
# Source this file; it changes only the current shell environment.

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  HISTB_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  echo "env.sh must be sourced from bash" >&2
  return 1
fi

export HISTB_EMUELEC_ROOT="$(cd "${HISTB_TOOLS_DIR}/../.." && pwd)"
export HISTB_WORK_ROOT="$(readlink -m "${HISTB_WORK_ROOT:-$(dirname "${HISTB_EMUELEC_ROOT}")}")"

# Keep source, cache and output on a Linux ext filesystem.  The public recipe
# intentionally does not encode the maintainer's workstation path.
HISTB_WORK_FS="$(stat -f -c %T "${HISTB_WORK_ROOT}" 2>/dev/null || true)"
case "${HISTB_WORK_FS}" in
  ext2/ext3|ext4) ;;
  *)
    echo "work root is not the isolated ext filesystem: ${HISTB_WORK_ROOT} (${HISTB_WORK_FS:-unknown})" >&2
    return 1
    ;;
esac

export HISTB_SDK_ROOT="$(readlink -m "${HISTB_SDK_ROOT:-${HISTB_WORK_ROOT}/sdk}")"
export HISTB_OUT_ROOT="$(readlink -m "${HISTB_OUT_ROOT:-${HISTB_SDK_ROOT}/out/hi3798mv100/hi3798mdmo1g}")"
export HISTB_TOOLCHAIN_ROOT="$(readlink -m "${HISTB_TOOLCHAIN_ROOT:-${HISTB_SDK_ROOT}/tools/linux/toolchains/arm-histbv310-linux}")"
for HISTB_SCOPED_PATH in \
    "${HISTB_EMUELEC_ROOT}" "${HISTB_SDK_ROOT}" \
    "${HISTB_OUT_ROOT}" "${HISTB_TOOLCHAIN_ROOT}"; do
  case "${HISTB_SCOPED_PATH}" in
    "${HISTB_WORK_ROOT}"|"${HISTB_WORK_ROOT}"/*) ;;
    *)
      echo "refusing project path outside ${HISTB_WORK_ROOT}: ${HISTB_SCOPED_PATH}" >&2
      return 1
      ;;
  esac
done
unset HISTB_SCOPED_PATH HISTB_WORK_FS
export HISTB_CROSS_PREFIX="${HISTB_TOOLCHAIN_ROOT}/bin/arm-histbv310-linux-"

export CC="${HISTB_CROSS_PREFIX}gcc"
export CXX="${HISTB_CROSS_PREFIX}g++"
export AR="${HISTB_CROSS_PREFIX}ar"
export AS="${HISTB_CROSS_PREFIX}as"
export LD="${HISTB_CROSS_PREFIX}ld"
export NM="${HISTB_CROSS_PREFIX}nm"
export OBJCOPY="${HISTB_CROSS_PREFIX}objcopy"
export OBJDUMP="${HISTB_CROSS_PREFIX}objdump"
export RANLIB="${HISTB_CROSS_PREFIX}ranlib"
export READELF="${HISTB_CROSS_PREFIX}readelf"
export STRIP="${HISTB_CROSS_PREFIX}strip"
export CROSS_COMPILE="${HISTB_CROSS_PREFIX}"

if [[ ! -x "${CC}" ]]; then
  echo "HiSTB cross compiler not found: ${CC}" >&2
  return 1
fi

export HISTB_SYSROOT="$(${CC} --print-sysroot)"
export HISTB_VENDOR_INCLUDE="${HISTB_OUT_ROOT}/include"
export HISTB_VENDOR_LIB="${HISTB_OUT_ROOT}/lib/share"
export HISTB_TARGET_ROOT="${HISTB_OUT_ROOT}/rootbox"
export HISTB_EXPECTED_INTERPRETER="/lib/ld-linux.so.3"

# The vendor binaries are ARM EABI5 softfp. Do not change this to hard-float.
export HISTB_ARCH_FLAGS="-mcpu=cortex-a7 -mfloat-abi=softfp -mfpu=vfpv3-d16"
export CPPFLAGS="${CPPFLAGS:-} --sysroot=${HISTB_SYSROOT} -I${HISTB_VENDOR_INCLUDE}"
export CFLAGS="${CFLAGS:-} ${HISTB_ARCH_FLAGS}"
export CXXFLAGS="${CXXFLAGS:-} ${HISTB_ARCH_FLAGS}"
export LDFLAGS="${LDFLAGS:-} --sysroot=${HISTB_SYSROOT} -L${HISTB_VENDOR_LIB} -Wl,-rpath-link,${HISTB_VENDOR_LIB}"

export PATH="${HISTB_TOOLCHAIN_ROOT}/bin:${PATH}"

printf 'HiSTB application build environment\n'
printf '  compiler: %s\n' "${CC}"
printf '  sysroot:  %s\n' "${HISTB_SYSROOT}"
printf '  vendor:   %s\n' "${HISTB_OUT_ROOT}"
printf '  ABI:      ARMv7 EABI5 softfp, VFPv3-D16\n'
