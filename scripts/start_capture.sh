#!/bin/bash
# scripts/start_capture.sh
#
# Wrapper invoked by packet-tap.service. Always logs live tcpdump captures
# locally to $LOOT_DIR, rotated into 100MB chunks, regardless of whether a
# USB drive is attached (offload_loot.sh handles moving files off later).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/pi-squirrel.conf
source "${REPO_ROOT}/config/pi-squirrel.conf"

# Prefer the interface mapping persisted by network/setup_bridge.sh; fall
# back to live auto-detection if it isn't present yet (e.g. first run).
if [[ -f /etc/pi-squirrel/ifaces.env ]]; then
    # shellcheck disable=SC1091
    source /etc/pi-squirrel/ifaces.env
else
    # shellcheck source=../network/ifaces.sh
    source "${REPO_ROOT}/network/ifaces.sh"
    detect_physical_ifaces
fi

CAPTURE_IFACE="${BRIDGE_NAME:-br-tap}"

mkdir -p "${LOOT_DIR}"

echo "Starting capture on ${CAPTURE_IFACE}, writing to ${LOOT_DIR}, rotating every ${CAPTURE_ROTATE_MB}MB..."

exec tcpdump -i "${CAPTURE_IFACE}" \
    -w "${LOOT_DIR}/${CAPTURE_FILENAME_PATTERN}" \
    -C "${CAPTURE_ROTATE_MB}" \
    -Z "$(id -un)" \
    ${CAPTURE_FILTER}
