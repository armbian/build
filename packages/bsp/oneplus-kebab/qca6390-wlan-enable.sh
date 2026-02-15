#!/bin/bash
# Enable QCA6390 WLAN and BT by driving enable GPIOs high (tlmm pins 20 = WLAN, 21 = BT).
# TLMM is f100000.pinctrl. The qca639x driver does not probe, so we assert enables in userspace.

set -e
WLAN_LINE=20
BT_LINE=21

# Find TLMM gpiochip (f100000.pinctrl) via gpiodetect
find_tlmm_chip() {
	local line
	while IFS= read -r line; do
		if [[ "$line" == *"f100000.pinctrl"* ]]; then
			# e.g. "gpiochip3 [f100000.pinctrl] (230 lines)"
			echo "$line" | sed -n 's/^\(gpiochip[0-9]*\).*/\1/p'
			return 0
		fi
	done < <(gpiodetect 2>/dev/null || true)
	return 1
}

chip=$(find_tlmm_chip)
if [[ -z "$chip" ]]; then
	echo "qca6390-wlan-enable: gpiodetect did not find f100000.pinctrl; install gpiod and check gpiodetect" >&2
	exit 1
fi

dev="/dev/${chip}"
if [[ ! -c "$dev" ]]; then
	echo "qca6390-wlan-enable: $dev not found" >&2
	exit 1
fi

# Hold both lines high (gpioset runs until killed). Rescan PCI after a short delay.
gpioset "$dev" "${WLAN_LINE}=1" "${BT_LINE}=1" &
pid=$!
sleep 0.5
echo 1 > /sys/bus/pci/rescan 2>/dev/null || true
wait $pid
