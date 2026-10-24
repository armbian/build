#!/usr/bin/env bash
#
# Setup script for sun60iw2 (Allwinner A733) SoC family.
# Configures kernel modules, NPU runtime assets, and hardware scaling governors.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="${SCRIPT_DIR}/assets"

echo "=== [Setup: sun60iw2] Configuring SoC Environment ==="

# 1. Load VIP9000 NPU Kernel Module (vipcore.ko)
if ! lsmod | grep -q "^vipcore"; then
    echo "Loading vipcore kernel module..."
    if modprobe vipcore 2>/dev/null; then
        echo "vipcore loaded via modprobe."
    else
        KVER="$(uname -r)"
        MODULE_PATH="$(find "/lib/modules/${KVER}" -name "vipcore.ko" 2>/dev/null | head -n 1)"
        if [[ -n "${MODULE_PATH}" && -f "${MODULE_PATH}" ]]; then
            insmod "${MODULE_PATH}"
            echo "vipcore loaded from ${MODULE_PATH}."
        else
            echo "WARNING: vipcore.ko not found under /lib/modules/${KVER}."
        fi
    fi
else
    echo "vipcore kernel module is already loaded."
fi

# 2. Ensure /dev/vipcore device node exists and has correct permissions
if [[ ! -c /dev/vipcore ]]; then
    if [[ -f /sys/class/misc/vipcore/dev ]]; then
        IFS=: read -r MAJOR MINOR < /sys/class/misc/vipcore/dev
        mknod /dev/vipcore c "${MAJOR}" "${MINOR}"
        echo "Created /dev/vipcore character device node (${MAJOR}:${MINOR})."
    fi
fi

if [[ -c /dev/vipcore ]]; then
    chmod 666 /dev/vipcore
    # Create compatibility symlink /dev/galcore -> /dev/vipcore
    ln -sf /dev/vipcore /dev/galcore
    echo "/dev/vipcore and /dev/galcore symlink ready."
fi

# 3. Deploy NPU Userspace Binaries, Libraries, and Models
if [[ -d "${ASSETS_DIR}" ]]; then
    echo "Installing NPU runtime assets from ${ASSETS_DIR}..."

    # Install binaries
    if [[ -d "${ASSETS_DIR}/usr/bin" ]]; then
        cp -a "${ASSETS_DIR}/usr/bin/"* /usr/bin/
        chmod +x /usr/bin/lenet /usr/bin/vpm_run 2>/dev/null || true
    fi

    # Install shared libraries
    LIB_DEST="/usr/lib/aarch64-linux-gnu"
    mkdir -p "${LIB_DEST}"
    if [[ -d "${ASSETS_DIR}/usr/lib/aarch64-linux-gnu" ]]; then
        cp -a "${ASSETS_DIR}/usr/lib/aarch64-linux-gnu/"* "${LIB_DEST}/"
        ldconfig 2>/dev/null || true
    fi

    # Install models and sample input data
    mkdir -p /etc/npu
    if [[ -d "${ASSETS_DIR}/etc/npu" ]]; then
        cp -ra "${ASSETS_DIR}/etc/npu/"* /etc/npu/
    fi

    # Install udev rule
    if [[ -f "${ASSETS_DIR}/etc/udev/rules.d/99-vipcore.rules" ]]; then
        mkdir -p /etc/udev/rules.d
        cp "${ASSETS_DIR}/etc/udev/rules.d/99-vipcore.rules" /etc/udev/rules.d/
    fi
    echo "NPU userspace runtime assets deployed successfully."
fi

# 4. Configure CPU Frequency Scaling Governors
if compgen -G "/sys/devices/system/cpu/cpufreq/policy*" >/dev/null; then
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        if [[ -f "${policy}/scaling_available_governors" && -f "${policy}/scaling_governor" ]]; then
            avail="$(cat "${policy}/scaling_available_governors")"
            target_gov="schedutil"
            if [[ "${avail}" == *"performance"* ]]; then
                target_gov="performance"
            fi
            echo "${target_gov}" > "${policy}/scaling_governor" 2>/dev/null || true
            echo "Set $(basename "${policy}") governor to ${target_gov}."
        fi
    done
fi

echo "=== [Setup: sun60iw2] Setup Complete ==="
