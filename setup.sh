#!/bin/bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: run as root with sudo ./setup.sh" >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="/opt/pi-squirrel"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bridge-utils \
    tcpdump \
    dnsmasq \
    iptables \
    macchanger \
    curl \
    ca-certificates \
    git \
    kmod \
    net-tools

if ! command -v tailscale >/dev/null 2>&1; then
    echo "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
fi

install -d -m 0755 "${TARGET_DIR}"
for item in config network scripts systemd udev; do
    cp -a "${REPO_ROOT}/${item}" "${TARGET_DIR}/"
done

install -d -m 0755 /etc/systemd/system /etc/udev/rules.d /etc/pi-squirrel
cp -f "${REPO_ROOT}/systemd/br-tap.service" /etc/systemd/system/br-tap.service
cp -f "${REPO_ROOT}/systemd/packet-tap.service" /etc/systemd/system/packet-tap.service
cp -f "${REPO_ROOT}/udev/99-usb-offload.rules" /etc/udev/rules.d/99-usb-offload.rules
chmod +x "${TARGET_DIR}"/scripts/*.sh "${TARGET_DIR}"/network/*.sh

systemctl daemon-reload
udevadm control --reload

cat <<'EOF'
Setup complete.

Next steps:
  1. Review config/pi-squirrel.conf and set MAC_CLONE_ENABLED, TARGET_HOST_MAC,
     CAPTURE_ROTATE_MB, and TAILSCALE_UP_FLAGS as needed.
  2. Create the transparent bridge:
       sudo /opt/pi-squirrel/network/setup_bridge.sh
  3. Clone the host MAC onto the target port if desired:
       sudo /opt/pi-squirrel/network/mac_clone.sh --persist
  4. Start capture:
       sudo systemctl enable --now packet-tap.service
  5. Authenticate Tailscale:
       sudo tailscale up --ssh --accept-routes

For example, you can also provide an auth key on the command line:
  sudo TAILSCALE_AUTH_KEY=tskey-... /opt/pi-squirrel/setup.sh
EOF

if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    echo "Authenticating Tailscale with provided auth key..."
    tailscale up --authkey "${TAILSCALE_AUTH_KEY}" --ssh ${TAILSCALE_UP_FLAGS:-}
fi
