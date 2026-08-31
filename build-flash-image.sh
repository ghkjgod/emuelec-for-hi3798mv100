#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/easy-build.sh"

FLASH_ROOT="${SCRIPT_DIR}/artifacts/flash"
TF_PACKAGE="${SCRIPT_DIR}/artifacts/tf-card"
[[ -f "${FLASH_ROOT}/FLASH-INSTRUCTIONS.txt" ]] || {
  echo "full build completed without the gated flash instructions" >&2
  exit 1
}
mapfile -t images < <(find "${FLASH_ROOT}" -maxdepth 1 -type f -name '*-p9-rootfs.img' -print)
[[ "${#images[@]}" = 1 ]] || {
  echo "expected one gated p9/rootfs image, found ${#images[@]}" >&2
  exit 1
}
image="${images[0]}"
[[ -f "${image}.sha256" && -f "${TF_PACKAGE}/MANIFEST.sha256" ]] || {
  echo "flash image or TF package checksum is missing" >&2
  exit 1
}
(
  cd "${FLASH_ROOT}"
  sha256sum --check --status "$(basename "${image}").sha256"
)
(
  cd "${TF_PACKAGE}"
  sha256sum --check --status MANIFEST.sha256
)

printf '\nEverything required for an almost ready-to-play installation is present.\n'
printf '  burnable p9/rootfs image: %s\n' "${image}"
printf '  copy-ready TF directory: %s\n' "${TF_PACKAGE}"
printf '  add your licensed BIOS and ROM files below TF/EmuELEC before use.\n'
