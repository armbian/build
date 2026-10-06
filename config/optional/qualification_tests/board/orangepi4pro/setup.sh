#!/usr/bin/env bash
#
# Setup script for Xunlong Orange Pi 4 Pro target board.
# Configures network nameservers/hosts, installs test packages, and mounts peripherals.
#

set -e

echo "=== [Setup: orangepi4pro] Configuring Board Environment ==="

# 1. Configure DNS and Local Hosts
GATEWAY_IP="10.0.1.1"

if [[ -f /etc/resolv.conf ]]; then
    if ! grep -q "^nameserver ${GATEWAY_IP}" /etc/resolv.conf; then
        echo "Adding nameserver ${GATEWAY_IP} to /etc/resolv.conf..."
        echo "nameserver ${GATEWAY_IP}" >> /etc/resolv.conf
    fi
else
    echo "Creating /etc/resolv.conf with nameserver ${GATEWAY_IP}..."
    echo "nameserver ${GATEWAY_IP}" > /etc/resolv.conf
fi

if [[ -f /etc/hosts ]]; then
    if ! grep -q "router.lan" /etc/hosts; then
        echo "Adding router.lan mapping to /etc/hosts..."
        echo "${GATEWAY_IP} router.lan" >> /etc/hosts
    fi
else
    echo "${GATEWAY_IP} router.lan" > /etc/hosts
fi

# Verify connectivity to router/gateway
if ping -c 1 -W 2 "${GATEWAY_IP}" >/dev/null 2>&1; then
    echo "Network gateway ${GATEWAY_IP} is reachable."
else
    echo "WARNING: Network gateway ${GATEWAY_IP} did not respond to ping."
fi

# 2. Check and Install Required Packages (iperf3, ethtool, mtd-utils, etc.)
PKGS_TO_INSTALL=()

if ! command -v iperf3 >/dev/null 2>&1; then
    PKGS_TO_INSTALL+=("iperf3")
fi

if ! command -v ethtool >/dev/null 2>&1; then
    PKGS_TO_INSTALL+=("ethtool")
fi

if ! command -v mtdinfo >/dev/null 2>&1; then
    PKGS_TO_INSTALL+=("mtd-utils")
fi

if ! command -v evtest >/dev/null 2>&1; then
    PKGS_TO_INSTALL+=("evtest")
fi

if [[ ${#PKGS_TO_INSTALL[@]} -gt 0 ]]; then
    echo "Installing missing package dependencies: ${PKGS_TO_INSTALL[*]}..."
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq || true
        apt-get install -y --no-install-recommends "${PKGS_TO_INSTALL[@]}" || true
    else
        echo "WARNING: apt-get not available to install ${PKGS_TO_INSTALL[*]}."
    fi
else
    echo "All core testing tools (iperf3, ethtool, mtd-utils, evtest) are installed."
fi

# 3. Mount USB Storage if Present
USB_DEV="$(find /sys/block/sd* -maxdepth 1 2>/dev/null | head -n 1 || true)"
if [[ -n "${USB_DEV}" ]]; then
    DEV_NAME="$(basename "${USB_DEV}")"
    # Check for partition 1, otherwise whole disk
    TARGET_PART="/dev/${DEV_NAME}1"
    if [[ ! -b "${TARGET_PART}" ]]; then
        TARGET_PART="/dev/${DEV_NAME}"
    fi

    if [[ -b "${TARGET_PART}" ]]; then
        mkdir -p /mnt/usb
        if ! mountpoint -q /mnt/usb; then
            echo "Mounting USB storage device ${TARGET_PART} at /mnt/usb..."
            mount -o ro "${TARGET_PART}" /mnt/usb 2>/dev/null || mount "${TARGET_PART}" /mnt/usb 2>/dev/null || true
        else
            echo "USB storage already mounted at /mnt/usb."
        fi
    fi
fi

echo "=== [Setup: orangepi4pro] Setup Complete ==="
