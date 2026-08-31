#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE=build
case "${1:-}" in
  '') ;;
  --check) MODE=check ;;
  --setup-only) MODE=setup ;;
  -h|--help)
    cat <<'EOF'
Usage: ./easy-build.sh [--check|--setup-only]

  no option      check the computer, prepare fixed sources, then build
  --check        only check tools, filesystem, and free space
  --setup-only   check and prepare fixed SDK/EmuELEC sources without building
EOF
    exit 0
    ;;
  *) echo "Unknown option: $1. Run ./easy-build.sh --help." >&2; exit 2 ;;
esac

REQUIRED_COMMANDS=(
  awk bash bc bison bzip2 cmake curl file flex g++ gawk gcc gettext git gzip
  make ninja openssl patch perl pkg-config python3 rsync sha256sum tar texi2any
  unzip wget xz
)
APT_PACKAGES=(
  build-essential git patch make ninja-build cmake pkg-config python3 perl
  gawk bison flex gettext texinfo autoconf automake libtool rsync file bc curl
  wget libncurses-dev tar gzip bzip2 xz-utils unzip e2fsprogs zlib1g-dev
  libssl-dev openssl libc6-i386 lib32z1
)

say_error()
{
  echo >&2
  echo "Build check failed: $1" >&2
  echo "Next step: $2" >&2
}

if [[ "$(uname -s 2>/dev/null || true)" != Linux ]]; then
  say_error "this script is running outside Linux" \
    "On Windows, open the Ubuntu app (WSL terminal), enter the project folder, and run ./easy-build.sh there."
  exit 1
fi

case "${SCRIPT_DIR}" in
  *[[:space:]]*)
    say_error "the project path contains spaces: ${SCRIPT_DIR}" \
      "Move or clone the repository to a path without spaces, then try again."
    exit 1
    ;;
esac

filesystem="$(stat -f -c %T "${SCRIPT_DIR}" 2>/dev/null || true)"
case "${filesystem}" in
  ext2/ext3|ext4) ;;
  *)
    say_error "the project is on ${filesystem:-an unknown filesystem}, not Linux ext4" \
      "Move it into your Linux home folder (for example ~/emuelec-for-hi3798mv100). Do not build below /mnt/c, /mnt/d, or /mnt/e."
    exit 1
    ;;
esac

missing=()
for command_name in "${REQUIRED_COMMANDS[@]}"; do
  command -v "${command_name}" >/dev/null 2>&1 || missing+=("${command_name}")
done
if ((${#missing[@]} != 0)); then
  say_error "required tools are missing: ${missing[*]}" \
    "On Ubuntu, copy and run: sudo apt update && sudo apt install -y ${APT_PACKAGES[*]}"
  exit 1
fi

if command -v dpkg-query >/dev/null 2>&1; then
  missing_packages=()
  for package_name in "${APT_PACKAGES[@]}"; do
    dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | \
      grep -Fq 'install ok installed' || missing_packages+=("${package_name}")
  done
  if ((${#missing_packages[@]} != 0)); then
    say_error "Ubuntu packages are missing: ${missing_packages[*]}" \
      "Copy and run: sudo apt update && sudo apt install -y ${missing_packages[*]}"
    exit 1
  fi
fi

free_kib="$(df -Pk "${SCRIPT_DIR}" | awk 'NR == 2 { print $4 }')"
case "${free_kib}" in ''|*[!0-9]*) free_kib=0 ;; esac
required_gib=40
if [[ "${MODE}" = check || "${MODE}" = setup ]]; then required_gib=8; fi
required_kib=$((required_gib * 1024 * 1024))
if ((free_kib < required_kib)); then
  free_gib=$((free_kib / 1024 / 1024))
  say_error "only about ${free_gib} GiB is free; this operation needs at least ${required_gib} GiB" \
    "Free space on this ext4 filesystem, or move the project to a larger ext4 disk."
  exit 1
fi

for required_file in WORKSPACE.lock SOURCES.lock scripts/bootstrap-workspace.sh scripts/build-workspace.sh; do
  [[ -f "${SCRIPT_DIR}/${required_file}" ]] || {
    say_error "the repository is incomplete: ${required_file} is missing" \
      "Clone again with git clone --recurse-submodules, or download and fully extract the GitHub ZIP."
    exit 1
  }
done

echo "Computer check passed."
echo "  project:    ${SCRIPT_DIR}"
echo "  filesystem: ${filesystem}"
echo "  free space: $((free_kib / 1024 / 1024)) GiB"

if [[ "${MODE}" = check ]]; then
  echo "No files were downloaded or built (--check)."
  exit 0
fi

echo "Preparing the exact SDK, EmuELEC, and port revisions..."
"${SCRIPT_DIR}/scripts/bootstrap-workspace.sh"
if [[ "${MODE}" = setup ]]; then
  echo "Setup complete. Run ./easy-build.sh when you are ready for the full build."
  exit 0
fi

echo "Starting the full build. This can take roughly 1-3 hours on a typical PC."
"${SCRIPT_DIR}/scripts/build-workspace.sh"

echo
echo "Build finished successfully."
echo "  rootfs and release files: ${SCRIPT_DIR}/artifacts"
echo "  copy-ready TF package:    ${SCRIPT_DIR}/artifacts/tf-card"
echo "  complete build log:       ${SCRIPT_DIR}/logs/histb-emuelec-build-all.log"
