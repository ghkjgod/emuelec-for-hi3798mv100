#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TOOLS_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
SUPERVISOR=${TOOLS_DIR}/rootfs-overlay/usr/bin/histb-emuelec-supervisor
ROLLBACK=${TOOLS_DIR}/rootfs-overlay/usr/bin/histb-release-rollback
WORK_ROOT=$(CDPATH= cd -- "${TOOLS_DIR}/../../.." && pwd)
TEST_PARENT=${WORK_ROOT}/.tests
TEST_STORAGE=

mkdir -p "${TEST_PARENT}"
TEST_STORAGE=$(mktemp -d -p "${TEST_PARENT}" supervisor-state.XXXXXX)
cleanup()
{
    case "${TEST_STORAGE}" in
        "${TEST_PARENT}"/supervisor-state.*) rm -rf "${TEST_STORAGE}" ;;
        *) echo "refusing unsafe test cleanup: ${TEST_STORAGE}" >&2 ;;
    esac
}
trap cleanup EXIT HUP INT TERM

STATE_ROOT=${TEST_STORAGE}/ee
GOOD_ID=histb-emuelec-test-good
BAD_ID=histb-emuelec-test-bad
mkdir -p \
    "${STATE_ROOT}/releases/${GOOD_ID}/bin" \
    "${STATE_ROOT}/releases/${BAD_ID}/bin" \
    "${STATE_ROOT}/state"
cp "${SCRIPT_DIR}/fixtures/frontend-healthy.sh" \
    "${STATE_ROOT}/releases/${GOOD_ID}/bin/run-emulationstation.sh"
cp "${SCRIPT_DIR}/fixtures/frontend-fail.sh" \
    "${STATE_ROOT}/releases/${BAD_ID}/bin/run-emulationstation.sh"
chmod 0755 \
    "${STATE_ROOT}/releases/${GOOD_ID}/bin/run-emulationstation.sh" \
    "${STATE_ROOT}/releases/${BAD_ID}/bin/run-emulationstation.sh"
ln -s "releases/${BAD_ID}" "${STATE_ROOT}/current"
ln -s "releases/${GOOD_ID}" "${STATE_ROOT}/previous"
echo "${BAD_ID}" >"${STATE_ROOT}/state/pending"
echo 2 >"${STATE_ROOT}/state/attempts"

HISTB_STORAGE_ROOT="${TEST_STORAGE}" \
HISTB_FB_DEVICE=/dev/null \
HISTB_MALI_DEVICE=/dev/null \
HISTB_DEVICE_WAIT_SECONDS=0 \
HISTB_HEALTH_SECONDS=1 \
HISTB_ROLLBACK_HELPER="${ROLLBACK}" \
HISTB_INSTALL_TEST_MODE=1 \
    "${SUPERVISOR}"

[ "$(readlink "${STATE_ROOT}/current")" = "releases/${GOOD_ID}" ]
[ "$(readlink "${STATE_ROOT}/previous")" = "releases/${BAD_ID}" ]
[ "$(cat "${STATE_ROOT}/state/last-failed")" = "${BAD_ID}" ]
[ "$(cat "${STATE_ROOT}/state/healthy")" = "${GOOD_ID}" ]
[ "$(cat "${STATE_ROOT}/state/last-good")" = "${GOOD_ID}" ]
[ ! -e "${STATE_ROOT}/state/pending" ]
[ ! -e "${STATE_ROOT}/state/attempts" ]

echo "supervisor automatic rollback and health state test: OK"
