#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env.sh
source "${SCRIPT_DIR}/env.sh" >/dev/null

if [[ "$#" -eq 0 ]]; then
  echo "usage: $0 ELF_FILE [ELF_FILE ...]" >&2
  exit 2
fi

status=0

version_gt() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" && "$1" != "$2" ]]
}

for elf in "$@"; do
  if [[ ! -f "${elf}" ]]; then
    echo "[FAIL] missing file: ${elf}" >&2
    status=1
    continue
  fi

  header="$(${READELF} -h "${elf}" 2>/dev/null)" || {
    echo "[FAIL] not an ELF file: ${elf}" >&2
    status=1
    continue
  }

  class="$(sed -n 's/^[[:space:]]*Class:[[:space:]]*//p' <<<"${header}")"
  machine="$(sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p' <<<"${header}")"
  flags="$(sed -n 's/^[[:space:]]*Flags:[[:space:]]*//p' <<<"${header}")"
  attributes="$(${READELF} -A "${elf}" 2>/dev/null || true)"
  cpu_arch="$(sed -n 's/^[[:space:]]*Tag_CPU_arch:[[:space:]]*//p' <<<"${attributes}" | head -n 1)"
  fp_arch="$(sed -n 's/^[[:space:]]*Tag_FP_arch:[[:space:]]*//p' <<<"${attributes}" | head -n 1)"
  vfp_args="$(sed -n 's/^[[:space:]]*Tag_ABI_VFP_args:[[:space:]]*//p' <<<"${attributes}" | head -n 1)"

  file_status=0
  if [[ "${class}" != "ELF32" || "${machine}" != "ARM" ]]; then
    echo "[FAIL] ${elf}: expected ELF32/ARM, got ${class}/${machine}" >&2
    file_status=1
  fi
  if [[ "${flags}" == *"hard-float ABI"* ]]; then
    echo "[FAIL] ${elf}: hard-float ABI is incompatible with the vendor userland" >&2
    file_status=1
  elif [[ "${elf}" != *.ko && "${flags}" != *"soft-float ABI"* ]]; then
    echo "[FAIL] ${elf}: expected soft-float ABI, flags=${flags}" >&2
    file_status=1
  fi
  if [[ "${elf}" != *.ko && "${cpu_arch}" != "v7" ]]; then
    echo "[FAIL] ${elf}: expected ARM architecture attribute v7, got ${cpu_arch:-missing}" >&2
    file_status=1
  fi
  if [[ -n "${fp_arch}" && "${fp_arch}" != "VFPv3-D16" ]]; then
    echo "[FAIL] ${elf}: expected VFPv3-D16 or no FP attribute, got ${fp_arch}" >&2
    file_status=1
  fi
  if [[ -n "${vfp_args}" ]]; then
    echo "[FAIL] ${elf}: Tag_ABI_VFP_args=${vfp_args}; softfp must use base AAPCS" >&2
    file_status=1
  fi

  interpreter="$(${READELF} -l "${elf}" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p')"
  if [[ -n "${interpreter}" && "${interpreter}" != "${HISTB_EXPECTED_INTERPRETER}" ]]; then
    echo "[FAIL] ${elf}: interpreter ${interpreter}, expected ${HISTB_EXPECTED_INTERPRETER}" >&2
    file_status=1
  fi

  host_rpath="$(${READELF} -d "${elf}" 2>/dev/null |
    sed -n 's/.*\(RPATH\|RUNPATH\).*\[\([^]]*\)\].*/\2/p' |
    grep -E '(^|:)(/home/|/mnt/[a-z]/)' | head -n 1 || true)"
  if [[ -n "${host_rpath}" ]]; then
    echo "[FAIL] ${elf}: build-host path leaked into RPATH/RUNPATH: ${host_rpath}" >&2
    file_status=1
  fi

  max_glibc="$(${READELF} --version-info "${elf}" 2>/dev/null | grep -oE 'GLIBC_[0-9]+([.][0-9]+)*' | sed 's/^GLIBC_//' | sort -Vu | tail -n 1 || true)"
  if [[ -n "${max_glibc}" ]] && version_gt "${max_glibc}" "2.24"; then
    echo "[FAIL] ${elf}: requires GLIBC_${max_glibc}, target is glibc 2.24" >&2
    file_status=1
  fi

  if [[ "${file_status}" -eq 0 ]]; then
    if [[ "${elf}" == *.ko ]]; then
      echo "[OK] ${elf}: ELF32 ARM kernel module, no hard-float ABI"
    else
      echo "[OK] ${elf}: ELF32 ARM softfp${interpreter:+, ${interpreter}}${max_glibc:+, GLIBC_${max_glibc}}"
    fi
  else
    status=1
  fi
done

exit "${status}"
