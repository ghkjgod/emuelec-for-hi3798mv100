#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 OLD_RELEASE.tar.gz NEW_RELEASE.tar.gz" >&2
    exit 2
fi

OLD_ARCHIVE=$1
NEW_ARCHIVE=$2
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TOOLS_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
INSTALLER=${TOOLS_DIR}/target/install-release.sh
ROLLBACK=${TOOLS_DIR}/rootfs-overlay/usr/bin/histb-release-rollback
WORK_ROOT=$(CDPATH= cd -- "${TOOLS_DIR}/../../.." && pwd)
TEST_PARENT=${WORK_ROOT}/.tests

for archive in "${OLD_ARCHIVE}" "${NEW_ARCHIVE}"; do
    [ -f "${archive}" ] || { echo "missing archive: ${archive}" >&2; exit 1; }
    [ -f "${archive}.sha256" ] || {
        echo "missing checksum: ${archive}.sha256" >&2
        exit 1
    }
done

old_id=$(basename "${OLD_ARCHIVE}" .tar.gz)
new_id=$(basename "${NEW_ARCHIVE}" .tar.gz)
[ "${old_id}" != "${new_id}" ] || {
    echo "two distinct release archives are required" >&2
    exit 1
}

mkdir -p "${TEST_PARENT}"
TEST_ROOT=$(mktemp -d -p "${TEST_PARENT}" release-state.XXXXXX)
cleanup()
{
    case "${TEST_ROOT}" in
        "${TEST_PARENT}"/release-state.*) rm -rf "${TEST_ROOT}" ;;
        *) echo "refusing unsafe test cleanup: ${TEST_ROOT}" >&2 ;;
    esac
}
trap cleanup EXIT HUP INT TERM

HISTB_INSTALL_TEST_MODE=1 "${INSTALLER}" "${OLD_ARCHIVE}" "${TEST_ROOT}"
HISTB_INSTALL_TEST_MODE=1 "${INSTALLER}" "${NEW_ARCHIVE}" "${TEST_ROOT}"

[ "$(readlink "${TEST_ROOT}/current")" = "releases/${new_id}" ]
[ "$(readlink "${TEST_ROOT}/previous")" = "releases/${old_id}" ]
[ ! -e "${TEST_ROOT}/releases/${old_id}/current.new" ]
[ ! -e "${TEST_ROOT}/releases/${old_id}/previous.new" ]

HISTB_INSTALL_TEST_MODE=1 "${ROLLBACK}" "${TEST_ROOT}"
[ "$(readlink "${TEST_ROOT}/current")" = "releases/${old_id}" ]
[ "$(readlink "${TEST_ROOT}/previous")" = "releases/${new_id}" ]

echo "release A/B install and rollback state test: OK"
