#!/bin/bash
# network/ifaces.sh
#
# Shared helper library: auto-detects the two physical Ethernet ports on the
# NanoPi R3S-LTS and exports them as IFACE_TARGET / IFACE_HOST.
#
# "Target" = the port facing the network you want to tap (uplink side, e.g.
#            the existing switch/router port the host used to plug into).
# "Host"   = the port facing the device that used to be directly connected
#            (the box whose place we are now sitting in-line with).
#
# Intended to be `source`d, not executed directly:
#   source "$(dirname "$0")/../network/ifaces.sh"
#   detect_physical_ifaces
#   echo "$IFACE_TARGET / $IFACE_HOST"

set -euo pipefail

: "${IFACE_EXCLUDE_REGEX:=^(lo|veth|docker|br-|virbr|tailscale|wg|tun|wl)}"

# list_physical_ifaces: print candidate physical Ethernet interface names,
# one per line, filtering out loopback/virtual/tailscale/wifi interfaces.
list_physical_ifaces() {
    local names=()

    if command -v ip >/dev/null 2>&1; then
        # `ip -br link show` output looks like:
        #   eth0             UP   aa:bb:cc:dd:ee:ff <BROADCAST,MULTICAST,UP,LOWER_UP>
        while read -r name _state _mac _flags; do
            name="${name%@*}" # strip "eth0@if2" style suffixes
            [[ -z "$name" ]] && continue
            names+=("$name")
        done < <(ip -br link show 2>/dev/null)
    fi

    if [[ ${#names[@]} -eq 0 && -d /sys/class/net ]]; then
        for p in /sys/class/net/*; do
            names+=("$(basename "$p")")
        done
    fi

    local n
    for n in "${names[@]}"; do
        # Exclude configured virtual/loopback/tailscale interfaces.
        echo "$n" | grep -Eq "$IFACE_EXCLUDE_REGEX" && continue

        # Only keep interfaces backed by real hardware (i.e. that have a
        # "device" symlink under /sys/class/net/<iface>/device). This filters
        # out bridges, bonds, and other software-only interfaces that could
        # otherwise slip through the exclude regex.
        if [[ -e "/sys/class/net/${n}/device" ]]; then
            echo "$n"
        fi
    done
}

# detect_physical_ifaces: populate IFACE_TARGET / IFACE_HOST globals.
# Interfaces are sorted by name for deterministic ordering (e.g. eth0 before
# eth1, end0 before end1) across reboots.
detect_physical_ifaces() {
    local -a ifaces
    mapfile -t ifaces < <(list_physical_ifaces | sort -u)

    if [[ ${#ifaces[@]} -lt 2 ]]; then
        echo "ERROR: expected at least 2 physical Ethernet interfaces, found: ${ifaces[*]:-none}" >&2
        echo "       (checked via 'ip -br link show' and /sys/class/net, excluding: ${IFACE_EXCLUDE_REGEX})" >&2
        return 1
    fi

    IFACE_TARGET="${ifaces[0]}"
    IFACE_HOST="${ifaces[1]}"
    export IFACE_TARGET IFACE_HOST

    if [[ ${#ifaces[@]} -gt 2 ]]; then
        echo "WARNING: more than 2 physical interfaces detected (${ifaces[*]}); using '$IFACE_TARGET' and '$IFACE_HOST'." >&2
    fi
}
