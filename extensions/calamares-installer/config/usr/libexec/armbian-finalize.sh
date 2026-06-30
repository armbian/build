#!/bin/bash
echo "--- Running Armbian Finalization Script ---"

if [ -f /usr/lib/armbian/armbian-install ]; then
    echo "Executing armbian-install to configure the bootloader..."
    /usr/lib/armbian/armbian-install
else
    echo "ERROR: /usr/lib/armbian/armbian-install not found!"
    exit 1
fi

echo "--- Armbian Finalization Complete ---"
exit 0
