#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_CACHE="${WORKSPACE_ROOT}/cache/sources"
HOST_TOOLS="${WORKSPACE_ROOT}/host-tools"
LOCK_FILE="${WORKSPACE_ROOT}/SOURCES.lock"

for tool in curl git sha256sum tar; do
  command -v "${tool}" >/dev/null || {
    echo "missing host tool: ${tool}" >&2
    exit 1
  }
done
mkdir -p "${SOURCE_CACHE}" "${HOST_TOOLS}"

while IFS='|' read -r filename expected url; do
  [[ -n "${filename}" && "${filename}" != \#* ]] || continue
  destination="${SOURCE_CACHE}/${filename}"
  if [[ -f "${destination}" ]]; then
    actual="$(sha256sum "${destination}" | awk '{print $1}')"
    if [[ "${actual}" != "${expected}" ]]; then
      echo "refusing to overwrite cache file with wrong hash: ${destination}" >&2
      echo "  expected: ${expected}" >&2
      echo "  actual:   ${actual}" >&2
      exit 1
    fi
    continue
  fi
  partial="${destination}.partial.$$"
  trap 'rm -f -- "${partial:-}"' EXIT HUP INT TERM
  echo "Downloading ${filename}"
  curl --fail --location --retry 3 --retry-all-errors --retry-delay 2 \
    --connect-timeout 30 --speed-limit 1024 --speed-time 120 --max-time 900 \
    --output "${partial}" "${url}"
  actual="$(sha256sum "${partial}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "download checksum mismatch for ${filename}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
  mv -- "${partial}" "${destination}"
  trap - EXIT HUP INT TERM
done <"${LOCK_FILE}"

fetch_git_commit() {
  local name="$1" path="$2" url="$3" commit="$4"
  if [[ -e "${path}" && ! -d "${path}/.git" ]]; then
    echo "refusing non-Git source cache: ${path}" >&2
    exit 1
  fi
  if [[ ! -d "${path}/.git" ]]; then
    mkdir -p "${path}"
    git -C "${path}" init
    git -C "${path}" remote add origin "${url}"
  fi
  if ! git -C "${path}" cat-file -e "${commit}^{commit}" 2>/dev/null; then
    git -C "${path}" fetch --depth 1 origin "${commit}"
  fi
  git -C "${path}" cat-file -e "${commit}^{commit}"
  echo "Pinned ${name}: ${commit}"
}

fetch_git_commit RetroArch "${SOURCE_CACHE}/retroarch.git" \
  https://github.com/libretro/RetroArch.git \
  ccbff758b46556407d1b9931a72cfcc46201276d
fetch_git_commit retroarch-joypad-autoconfig \
  "${SOURCE_CACHE}/retroarch-joypad-autoconfig.git" \
  https://github.com/libretro/retroarch-joypad-autoconfig.git \
  033151045d378b64e712a92592467800d7924227

cmake_root="${HOST_TOOLS}/cmake-3.20.6-linux-x86_64"
if [[ ! -x "${cmake_root}/bin/cmake" ]]; then
  if [[ -e "${cmake_root}" ]]; then
    echo "refusing incomplete host-tool directory: ${cmake_root}" >&2
    exit 1
  fi
  tar -xzf "${SOURCE_CACHE}/cmake-3.20.6-linux-x86_64.tar.gz" \
    -C "${HOST_TOOLS}"
fi
"${cmake_root}/bin/cmake" --version | head -n 1
echo "Pinned source cache ready: ${SOURCE_CACHE}"
