"I NEED ME SOME PACKETS. GET GANKED SON!!!" 

<img width="1024" height="559" alt="image" src="https://github.com/user-attachments/assets/4d150d53-2c24-422d-bce4-d0c7751b1ac0" />

# Pi-Squirrel: NanoPi R3S-LTS inline network tap + remote access drop-box

Made by an aspiring red teamer! I wanted to buy the Hak 5 Packet Squirrel for forever but I could not afford one :( So I made a DIY version on the much cheaper NanoPi R3S-LTS!

For a messily 40 buckos you could have a device with the same function as the Packet Squirrel at 20% of the price! 

A deployment repository for turning a NanoPi R3S-LTS running Armbian (Debian target with the Rockchip RK3566 kernel) into an inline Ethernet tap and portable remote access drop box.

This project is designed for authorized network diagnostics, edge-device troubleshooting, red-team lab work, and defensive network monitoring in environments where you have explicit written approval to monitor traffic and/or place a device in-line.

Important: This repository intentionally creates a transparent L2 bridge and captures traffic. Use only on networks and hosts you are authorized to test, monitor, or support.

## What this repo does

- Auto-detects the two physical Ethernet controllers on the NanoPi R3S-LTS.
- Builds a transparent bridge named `br-tap` without assigning an IP address to the bridge itself.
- Keeps the capture host invisible at Layer 3 while passing traffic through the bridge.
- Clones or overrides a target-facing MAC address so a downstream switch or host sees the tap as a transparent extension of the original host.
- Captures live traffic to `$HOME/loot/` as rotating `.pcap` files in 100MB chunks.
- Detects a USB storage device and moves all captured files to `/mnt/usb/loot/` via a transient systemd job.
- Configures Tailscale for secure remote access to the device.

## Repository layout

```text
Pi-Squirrel/
├── README.md
├── setup.sh
├── config/
│   └── pi-squirrel.conf
├── network/
│   ├── ifaces.sh
│   ├── setup_bridge.sh
│   └── mac_clone.sh
├── scripts/
│   ├── start_capture.sh
│   └── offload_loot.sh
├── systemd/
│   ├── br-tap.service
│   └── packet-tap.service
├── udev/
│   └── 99-usb-offload.rules
└── docs/
```

## NanoPi R3S-LTS physical port mapping

The board exposes multiple Ethernet ports. In practice, the port layout is:

- Port A: target-facing / upstream path (the side that originally connected to the network or upstream switch)
- Port B: host-facing / downstream path (the side that originally connected to the device or host you are replacing inline)

The automation scripts intentionally do not use hardcoded names such as `eth0`/`eth1`. Instead, they auto-discover the real physical interfaces using `ip -br link show` and `/sys/class/net` and filter out loopback, bridge, veth, Tailscale, and other virtual interfaces.

Recommended port-assignment logic:

1. Connect the upstream path to the side of the network that should remain online.
2. Connect the downstream path to the host or device you are replacing in-line.
3. Confirm the correct mapping with `ip -br link show` and `ethtool` before enabling the bridge.
4. Keep one port on the upstream side and the other on the downstream side.

The bridge itself is named `br-tap` and is intentionally left without an IP address, because the tap is meant to operate at Layer 2.

## Armbian setup steps

### 1. Install Armbian on the NanoPi R3S-LTS

Use the Debian target image for the RK3566 platform. After writing the image to the eMMC or SSD, boot the device and complete the normal Armbian first-boot setup. Ensure SSH is enabled.

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

### 2. Clone this repository and install dependencies

```bash
git clone https://github.com/your-org/Pi-Squirrel.git
cd Pi-Squirrel
sudo ./setup.sh
```

`setup.sh` will:

- install `bridge-utils`, `tcpdump`, `dnsmasq`, `iptables`, `macchanger`, `curl`, and other support packages
- install Tailscale if it is not already present
- install the repo under `/opt/pi-squirrel`
- copy the bridge service and USB-offload rules into the system directories

### 3. Configure the interface auto-detection

The interface selection is handled by `network/ifaces.sh`. It automatically exports:

- `IFACE_TARGET`
- `IFACE_HOST`

These are resolved using the live interface list and a hardware filter. You do not need to hardcode `eth0`/`eth1`.

### 4. Build the bridge

```bash
sudo /opt/pi-squirrel/network/setup_bridge.sh
```

This will:

- detect the two physical Ethernet ports
- create the `br-tap` bridge
- add both interfaces to the bridge
- enable promisc mode on both ports
- leave the bridge without an IP address

### 5. Configure MAC cloning

The default config file is:

```bash
/etc/pi-squirrel/ifaces.env
```

The main runtime settings live in:

```bash
/opt/pi-squirrel/config/pi-squirrel.conf
```

Relevant variables:

```bash
MAC_CLONE_ENABLED=true
TARGET_HOST_MAC=""
```

Behavior:

- If `TARGET_HOST_MAC` is set, that exact MAC is cloned onto `IFACE_TARGET`.
- If it is empty, the script attempts to learn the original host MAC from traffic observed on `IFACE_HOST`.
- `macchanger` is preferred if installed; otherwise, the script falls back to `ip link set dev ... address ...`.

Example explicit MAC cloning:

```bash
sudo /opt/pi-squirrel/network/mac_clone.sh 00:11:22:33:44:55
sudo /opt/pi-squirrel/network/mac_clone.sh --persist
```

The `--persist` flag writes a systemd `.link` file so the interface reuses the cloned MAC on reboot.

## Capture operation

The capture service runs through `scripts/start_capture.sh` and is started by `systemd/packet-tap.service`.

### Start / enable the capture service

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now packet-tap.service
sudo systemctl status packet-tap.service
```

### Capture storage

By default, packets are logged to:

```bash
$HOME/loot/
```

The capture rotates at:

- 100MB chunk size (`CAPTURE_ROTATE_MB=100`)
- file naming pattern: `capture_%Y-%m-%d_%H-%M-%S.pcap`

The script launches `tcpdump` on the `br-tap` bridge and creates multiple timestamped capture files automatically.

Example:

```bash
ls -lh ~/loot
```

## USB offload

The USB offload logic is handled by:

- `scripts/offload_loot.sh`
- `udev/99-usb-offload.rules`

When a USB storage device is inserted, the udev rule triggers the script, which:

- mounts the USB drive under `/mnt/usb`
- creates `/mnt/usb/loot`
- moves any existing `.pcap` files from `$HOME/loot` into `/mnt/usb/loot/`
- uses a transient `systemd-run` background unit so the move happens asynchronously without blocking the USB hotplug event

Manual test:

```bash
sudo /opt/pi-squirrel/scripts/offload_loot.sh
```

## Tailscale remote access

The setup script installs Tailscale automatically. After installation, log in and bring the node online:

```bash
sudo tailscale up --ssh --accept-routes
sudo tailscale status
```

If you want to authenticate with an auth key:

```bash
sudo TAILSCALE_AUTH_KEY=tskey-xxxxxxxx /opt/pi-squirrel/setup.sh
```

Or explicitly:

```bash
sudo tailscale up --authkey tskey-xxxxxxxx --ssh --accept-routes
```

To view the node IP and verify connectivity:

```bash
tailscale ip -4
tailscale netcheck
```

## Useful commands

```bash
ip -br link show
ip -d link show br-tap
sudo tcpdump -i br-tap -nn -vvv
sudo systemctl status packet-tap.service
sudo journalctl -u packet-tap.service -f
ls -lh ~/loot
sudo mount | grep /mnt/usb
```

## Notes for deployment

- Keep the bridge without an IP so it behaves like a transparent Layer 2 tap.
- Use the `IFACE_TARGET` and `IFACE_HOST` mapping that matches the actual physical ports on your board.
- Ensure the two physical ports are connected to the correct upstream and downstream endpoints before enabling the bridge.
- Validate the bridge and capture flow in a lab or on an approved network before production use.

## License and usage

This repository is intended for authorized, supervised field use and lab testing only. The author does not condone unauthorized interception, network monitoring, or device tampering. Ensure you have written permission and comply with local laws, employer policies, and contractual requirements before deploying this system.
