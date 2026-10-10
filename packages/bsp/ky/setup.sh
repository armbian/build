#!/bin/bash
#
# OrangePi RV2 / KY platform setup script
#

echo "Setting up KY platform specifics..."

# Enable SPI flash if present
if [[ -e /dev/mtdblock0 ]]; then
	echo "SPI flash detected at /dev/mtdblock0"
fi

# Setup GPIO access permissions
if [[ -d /sys/class/gpio ]]; then
	chmod 666 /sys/class/gpio/export 2>/dev/null || true
	chmod 666 /sys/class/gpio/unexport 2>/dev/null || true
fi

# Setup additional device permissions for RISC-V platform
if [[ -c /dev/mem ]]; then
	chmod 664 /dev/mem
fi

echo "KY platform setup completed."