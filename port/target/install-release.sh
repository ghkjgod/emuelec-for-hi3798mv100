#!/bin/sh

set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 RELEASE.tar.gz [STATE_ROOT]" >&2
    exit 2
fi

ARCHIVE=$1
STATE_ROOT=${2:-/storage/ee}
ARCHIVE_NAME=$(basename "${ARCHIVE}")
RELEASE_ID=${ARCHIVE_NAME%.tar.gz}
CHECKSUM=${ARCHIVE}.sha256
TEST_MODE=${HISTB_INSTALL_TEST_MODE:-0}

replace_release_link()
{
    source_link=$1
    destination_link=$2
    if [ -e "${destination_link}" ] && [ ! -L "${destination_link}" ]; then
        echo "refusing to replace non-symlink: ${destination_link}" >&2
        return 1
    fi
    # BusyBox 1.26 mv follows a destination symlink to a directory and lacks
    # -T.  Remove the already-validated link first so mv performs a rename.
    # If power is lost in this short window, the supervisor uses /opt/emuelec.
    rm -f "${destination_link}"
    mv "${source_link}" "${destination_link}"
}

case "${STATE_ROOT}" in
    /|"") echo "refusing unsafe state root: ${STATE_ROOT}" >&2; exit 1 ;;
    /*) ;;
    *) echo "state root must be an absolute path: ${STATE_ROOT}" >&2; exit 1 ;;
esac
if [ "$#" -eq 2 ] && [ "${TEST_MODE}" != 1 ]; then
    echo "custom state roots are allowed only with HISTB_INSTALL_TEST_MODE=1" >&2
    exit 1
fi

if [ "${STATE_ROOT}" = /storage/ee ]; then
    if [ ! -x /usr/bin/histb-storage-guard ]; then
        echo "refusing install without the p9 storage identity guard" >&2
        exit 1
    fi
    if ! HISTB_STORAGE_ROOT=/storage \
        /usr/bin/histb-storage-guard --require-marker; then
        echo "refusing install outside the authenticated mmcblk0p9 root storage" >&2
        exit 1
    fi
fi

case "${RELEASE_ID}" in
    histb-emuelec-[A-Za-z0-9._-]*) ;;
    *) echo "refusing unexpected release name: ${RELEASE_ID}" >&2; exit 1 ;;
esac
if printf '%s\n' "${RELEASE_ID}" | grep -Eq '[^A-Za-z0-9._-]'; then
    echo "refusing unsafe release name: ${RELEASE_ID}" >&2
    exit 1
fi

if [ ! -f "${ARCHIVE}" ] || [ ! -f "${CHECKSUM}" ]; then
    echo "release archive or checksum is missing" >&2
    exit 1
fi

expected_checksum=$(awk 'NR == 1 { value=$1 } END { if (NR != 1) exit 1; print value }' \
    "${CHECKSUM}") || {
    echo "invalid checksum file" >&2
    exit 1
}
if ! printf '%s\n' "${expected_checksum}" | grep -Eq '^[0-9A-Fa-f]{64}$'; then
    echo "invalid SHA-256 value in ${CHECKSUM}" >&2
    exit 1
fi
actual_checksum=$(sha256sum "${ARCHIVE}" | awk '{ print $1 }')
if [ "${actual_checksum}" != "${expected_checksum}" ]; then
    echo "release checksum mismatch" >&2
    exit 1
fi
echo "${ARCHIVE_NAME}: checksum OK"

if tar -tzf "${ARCHIVE}" | awk -v prefix="${RELEASE_ID}/" '
    index($0, prefix) != 1 || $0 ~ /(^|\/)\.\.($|\/)/ { bad=1 }
    END { exit bad ? 1 : 0 }
'; then
    :
else
    echo "release contains an unsafe or unexpected path" >&2
    exit 1
fi

mkdir -p "${STATE_ROOT}/releases" "${STATE_ROOT}/state"
LOCK_DIR=${STATE_ROOT}/.install-lock
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    echo "another release install is active: ${LOCK_DIR}" >&2
    exit 1
fi
DESTINATION=${STATE_ROOT}/releases/${RELEASE_ID}
if [ -e "${DESTINATION}" ] || [ -L "${DESTINATION}" ]; then
    echo "release already installed: ${DESTINATION}" >&2
    rmdir "${LOCK_DIR}"
    exit 1
fi

INCOMING=${STATE_ROOT}/.incoming-${RELEASE_ID}-$$
cleanup()
{
    rm -rf "${INCOMING}"
    rmdir "${LOCK_DIR}" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM
mkdir -p "${INCOMING}"
tar -xzf "${ARCHIVE}" -C "${INCOMING}"
if [ -L "${INCOMING}/${RELEASE_ID}/bin/run-emulationstation.sh" ] || \
   [ ! -x "${INCOMING}/${RELEASE_ID}/bin/run-emulationstation.sh" ] || \
   [ ! -f "${INCOMING}/${RELEASE_ID}/MANIFEST.sha256" ]; then
    echo "release payload is incomplete" >&2
    exit 1
fi

find "${INCOMING}/${RELEASE_ID}" -type l -print >"${INCOMING}/symlinks.list"
while IFS= read -r symlink_path; do
    symlink_target=$(readlink "${symlink_path}")
    case "${symlink_target}" in
        /*|*..*)
            echo "unsafe symlink in release: ${symlink_path} -> ${symlink_target}" >&2
            exit 1
            ;;
    esac
done <"${INCOMING}/symlinks.list"
rm -f "${INCOMING}/symlinks.list"
(
    cd "${INCOMING}/${RELEASE_ID}"
    sha256sum -c MANIFEST.sha256
)
mv "${INCOMING}/${RELEASE_ID}" "${DESTINATION}"
rmdir "${INCOMING}"
INCOMING=${STATE_ROOT}/.incoming-cleaned-$$
sync

old_current=
if [ -L "${STATE_ROOT}/current" ]; then
    old_current=$(readlink "${STATE_ROOT}/current" 2>/dev/null || true)
    case "${old_current}" in releases/histb-emuelec-*) ;; *) old_current=invalid ;; esac
    old_release_name=${old_current#releases/}
    case "${old_release_name}" in
        ""|*/*|*..*|*[!A-Za-z0-9._-]*) old_current=invalid ;;
    esac
    if [ "${old_current}" = invalid ] || \
       [ ! -x "${STATE_ROOT}/${old_current}/bin/run-emulationstation.sh" ]; then
        echo "existing current link is unsafe or incomplete" >&2
        exit 1
    fi
elif [ -e "${STATE_ROOT}/current" ]; then
    echo "current exists but is not a symlink" >&2
    exit 1
fi
if [ -n "${old_current}" ]; then
    if [ -e "${STATE_ROOT}/previous" ] && [ ! -L "${STATE_ROOT}/previous" ]; then
        echo "previous exists but is not a symlink" >&2
        exit 1
    fi
    rm -f "${STATE_ROOT}/previous.new"
    ln -s "${old_current}" "${STATE_ROOT}/previous.new"
    replace_release_link "${STATE_ROOT}/previous.new" "${STATE_ROOT}/previous"
fi
rm -f "${STATE_ROOT}/current.new"
ln -s "releases/${RELEASE_ID}" "${STATE_ROOT}/current.new"
replace_release_link "${STATE_ROOT}/current.new" "${STATE_ROOT}/current"

echo "${RELEASE_ID}" >"${STATE_ROOT}/state/pending.new"
mv -f "${STATE_ROOT}/state/pending.new" "${STATE_ROOT}/state/pending"
echo 0 >"${STATE_ROOT}/state/attempts.new"
mv -f "${STATE_ROOT}/state/attempts.new" "${STATE_ROOT}/state/attempts"
sync
trap - EXIT HUP INT TERM
rmdir "${LOCK_DIR}"

echo "installed ${RELEASE_ID}"
echo "active link: ${STATE_ROOT}/current"
echo "reboot, or restart /usr/bin/histb-emuelec-supervisor, to activate"
