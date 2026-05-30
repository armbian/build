#!/bin/bash
# EasePi Universal IR setup script

echo "Detecting IR devices..."

for dev in /dev/lirc* /sys/class/rc/*; do
    if [ -e "$dev" ]; then
        echo "Found IR device: $dev"
        /usr/bin/ir-keytable -c -w /etc/rc_keymaps/easepi_remote
        /usr/bin/ir-keytable -p nec
        exit 0
    fi
done

echo "No IR device found (check device tree configuration)"
exit 0
