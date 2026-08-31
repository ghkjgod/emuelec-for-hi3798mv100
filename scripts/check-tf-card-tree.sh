#!/usr/bin/env bash

set -euo pipefail

TREE="${1:-}"
[[ -n "${TREE}" && -d "${TREE}/EmuELEC" ]] || {
  echo "usage: $0 PATH-TO-TF-CARD-TREE" >&2
  exit 2
}
CORE_DIR="${TREE}/EmuELEC/cores"
CONFIG_DIR="${TREE}/EmuELEC/config"
CORE_NAMES=(
  fceumm gambatte gpsp mgba picodrive snes9x2010 mednafen_pce_fast
  pcsx_rearmed fbneo mame2003_plus
)

if find "${TREE}" -type d \( -iname bios -o -iname roms \) -print -quit | grep -q .; then
  echo "checked-in TF tree must not contain a BIOS/ROM directory" >&2
  exit 1
fi
[[ -f "${TREE}/MANIFEST.sha256" ]] || { echo "TF tree manifest is missing" >&2; exit 1; }
(
  cd "${TREE}"
  sha256sum --check --status MANIFEST.sha256
)
listed_count="$(wc -l <"${TREE}/MANIFEST.sha256" | tr -d '[:space:]')"
file_count="$(find "${TREE}" -type f ! -name MANIFEST.sha256 | wc -l | tr -d '[:space:]')"
[[ "${listed_count}" = "${file_count}" ]] || {
  echo "TF tree has unlisted or duplicate files: manifest=${listed_count}, files=${file_count}" >&2
  exit 1
}

[[ -f "${CORE_DIR}/cores.sha256" ]] || { echo "TF core manifest is missing" >&2; exit 1; }
(
  cd "${CORE_DIR}"
  sha256sum --check --status cores.sha256
)
[[ "$(wc -l <"${CORE_DIR}/cores.sha256" | tr -d '[:space:]')" = "${#CORE_NAMES[@]}" ]] || {
  echo "TF core manifest must contain exactly ${#CORE_NAMES[@]} records" >&2
  exit 1
}
for core in "${CORE_NAMES[@]}"; do
  binary="${CORE_DIR}/${core}_libretro.so"
  [[ -f "${binary}" ]] || { echo "checked-in TF core is missing: ${binary}" >&2; exit 1; }
  filename="${core}_libretro.so"
  expected="$(awk -v name="${filename}" '
    ($2 == name || $2 == "*" name) && length($1) == 64 && $1 !~ /[^0-9a-fA-F]/ {
      print tolower($1); count++
    }
    END { if (count != 1) exit 1 }
  ' "${CORE_DIR}/cores.sha256")" || {
    echo "TF core manifest lacks one exact record for ${filename}" >&2
    exit 1
  }
  [[ "$(sha256sum "${binary}" | awk '{print $1}')" = "${expected}" ]]
  header="$(readelf -h "${binary}")"
  grep -Fq 'Class:                             ELF32' <<<"${header}"
  grep -Fq "Data:                              2's complement, little endian" <<<"${header}"
  grep -Fq 'Machine:                           ARM' <<<"${header}"
  grep -Eq 'Flags:.*(EABI5|Version5 EABI)' <<<"${header}"
  grep -Eq 'Flags:.*soft-float ABI' <<<"${header}"
  if readelf -A "${binary}" | grep -Fq 'Tag_ABI_VFP_args: VFP registers'; then
    echo "checked-in TF core uses incompatible hard-float ABI: ${binary}" >&2
    exit 1
  fi
  if ! find "${TREE}/EmuELEC/licenses/libretro-cores/${core}" \
      -type f -print -quit | grep -q .; then
    echo "checked-in TF core lacks license material: ${core}" >&2
    exit 1
  fi
done
core_count="$(find "${CORE_DIR}" -maxdepth 1 -type f -name '*_libretro.so' | wc -l | tr -d '[:space:]')"
[[ "${core_count}" = "${#CORE_NAMES[@]}" ]] || {
  echo "unexpected checked-in TF core count: ${core_count}" >&2
  exit 1
}

[[ -f "${CONFIG_DIR}/gamecontrollerdb.txt" && \
   -f "${CONFIG_DIR}/gamecontrollerdb.sha256" ]] || {
  echo "checked-in TF controller database or checksum is missing" >&2
  exit 1
}
(
  cd "${CONFIG_DIR}"
  sha256sum --check --status gamecontrollerdb.sha256
)
awk '
  /^[[:space:]]*($|#)/ { next }
  /^xinput,[^,]+,/ { next }
  {
    comma=index($0, ","); guid=substr($0, 1, comma - 1)
    if (comma > 1 && length(guid) == 32 && guid !~ /[^0-9a-fA-F]/ &&
        substr($0, comma + 1) ~ /^[^,]+,/) {
      mappings++; if (index($0, "platform:Linux") != 0) linux++; next
    }
  }
  { bad=1 }
  END { exit (bad || mappings == 0 || linux == 0) ? 1 : 0 }
' "${CONFIG_DIR}/gamecontrollerdb.txt"

printf 'PASS: checked-in TF tree has 10 ARMv7 softfp cores, controller DB, complete hashes, and no BIOS/ROM\n'
