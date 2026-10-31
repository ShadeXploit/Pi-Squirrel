#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/config/pi-squirrel.conf"

USB_MOUNT_POINT="${USB_MOUNT_POINT:-/mnt/usb}"
USB_LOOT_DIR="${USB_MOUNT_POINT}/${USB_LOOT_SUBDIR:-loot}"

mkdir -p "${LOOT_DIR}"
mkdir -p "${USB_MOUNT_POINT}"

find_usb_device() {
    for d in /dev/sd* /dev/mmcblk*; do
        [[ -e "$d" ]] || continue
        case "$(basename "$d")" in
            loop*|ram*|sr*|sd[a-z] | mmcblk[0-9])
                continue
                ;;
        esac
        if lsblk -no TYPE,TRAN,FSTYPE "$d" 2>/dev/null | grep -q 'disk'; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

USB_DEV="$(find_usb_device || true)"
if [[ -z "${USB_DEV}" ]]; then
    echo "No removable USB block device detected; skipping offload." >&2
    exit 0
fi

# Prefer a single partition if present; otherwise mount the whole USB disk.
USB_PART="${USB_DEV}1"
if [[ -e "${USB_PART}" ]]; then
    TARGET_DEVICE="${USB_PART}"
else
    TARGET_DEVICE="${USB_DEV}"
fi

if ! mountpoint -q "${USB_MOUNT_POINT}"; then
    mkdir -p "${USB_MOUNT_POINT}"
    mount -o rw,uid="$(id -u)",gid="$(id -g)" "${TARGET_DEVICE}" "${USB_MOUNT_POINT}" || \
        mount -o rw "${TARGET_DEVICE}" "${USB_MOUNT_POINT}"
fi

mkdir -p "${USB_LOOT_DIR}"

systemd-run --quiet \
    --unit="pi-squirrel-offload-$(date +%s)" \
    --property=Type=oneshot \
    --property=After=local-fs.target \
    --property=RemainAfterExit=no \
    /bin/bash -lc 'set -euo pipefail; src="${HOME}/loot"; dst="/mnt/usb/loot"; mkdir -p "$dst"; find "$src" -maxdepth 1 -type f -name "*.pcap" -exec mv -n -t "$dst" {} +; echo "Moved .pcap files from $src to $dst"'

printf 'USB offload queued to %s\n' "${USB_LOOT_DIR}"
