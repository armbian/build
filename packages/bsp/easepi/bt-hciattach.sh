#!/bin/bash
# EasePi Universal Bluetooth initialization script
# Configuration via /etc/default/easepi-bt

# Load configuration file
if [ -f "/etc/default/easepi-bt" ]; then
    . /etc/default/easepi-bt
fi

# Set default values
BT_UART_DEVICE="${BT_UART_DEVICE:-/dev/ttyS8}"
BT_BAUD_RATE="${BT_BAUD_RATE:-1500000}"
BT_CHIP_TYPE="${BT_CHIP_TYPE:-bcm43xx}"
BOARD_NAME="${BOARD_NAME:-EasePi}"

echo "[BT] Initializing ${BOARD_NAME} Bluetooth (vendor kernel)"

# Check if already initialized by serdev
if hciconfig hci0 up >/dev/null 2>&1; then
    echo "[BT] hci0 already initialized by kernel serdev"
    exit 0
fi

# Unblock all
rfkill unblock all
sleep 1

# Try to enable rfkill0
if [ -d /sys/class/rfkill/rfkill0 ]; then
    echo 1 > /sys/class/rfkill/rfkill0/state 2>/dev/null || echo "[BT] rfkill0 state write failed (non-fatal)"
fi
sleep 1

echo "[BT] Attaching hciattach on ${BT_UART_DEVICE}"
exec hciattach -n -s 115200 "${BT_UART_DEVICE}" "${BT_CHIP_TYPE}" "${BT_BAUD_RATE}"
