#!/bin/bash
# network/setup_bridge.sh
#
# Builds a transparent layer-2 bridge (br-tap) out of the two auto-detected
# physical Ethernet interfaces, so the NanoPi R3S-LTS can sit in-line on a
# cable run without the hosts on either side noticing. The bridge itself is
# never assigned an IP address, keeping it invisible at L3.
#
# Usage: sudo ./network/setup_bridge.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/pi-squirrel.conf
source "${REPO_ROOT}/config/pi-squirrel.conf"
# shellcheck source=./ifaces.sh
source "${REPO_ROOT}/network/ifaces.sh"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must be run as root (sudo)." >&2
    exit 1
fi

detect_physical_ifaces
echo "Detected physical interfaces: IFACE_TARGET=${IFACE_TARGET} IFACE_HOST=${IFACE_HOST}"

# Persist the detected mapping for other scripts/services (e.g. start_capture.sh)
install -d -m 0755 /etc/pi-squirrel
cat >/etc/pi-squirrel/ifaces.env <<EOF
IFACE_TARGET=${IFACE_TARGET}
IFACE_HOST=${IFACE_HOST}
BRIDGE_NAME=${BRIDGE_NAME}
EOF

echo "Disabling offload features that can interfere with transparent bridging..."
for iface in "${IFACE_TARGET}" "${IFACE_HOST}"; do
    if command -v ethtool >/dev/null 2>&1; then
        ethtool -K "$iface" gro off gso off tso off 2>/dev/null || true
    fi
done

echo "Bringing up bridge '${BRIDGE_NAME}'..."
if ! ip link show "${BRIDGE_NAME}" >/dev/null 2>&1; then
    ip link add name "${BRIDGE_NAME}" type bridge
fi

# No STP: a tap must not negotiate with switches, it should look like plain wire.
ip link set dev "${BRIDGE_NAME}" type bridge stp_state 0
ip link set dev "${BRIDGE_NAME}" type bridge forward_delay 0

for iface in "${IFACE_TARGET}" "${IFACE_HOST}"; do
    ip link set dev "$iface" down
    ip link set dev "$iface" promisc on
    ip link set dev "$iface" master "${BRIDGE_NAME}"
    ip link set dev "$iface" up
done

# Intentionally no `ip addr add` on the bridge: a tap should be L2 invisible.
ip link set dev "${BRIDGE_NAME}" up

echo "Bridge '${BRIDGE_NAME}' is up, joining ${IFACE_TARGET} <-> ${IFACE_HOST}, no IP assigned."
ip -br link show "${BRIDGE_NAME}" "${IFACE_TARGET}" "${IFACE_HOST}"
