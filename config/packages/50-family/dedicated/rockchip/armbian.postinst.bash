cat <<EOF
#!/bin/sh
#
# ${FAMILY} post installation script
#

# Peripheral access for specific groups
addgroup --system --quiet --gid 997 gpio
addgroup --system --quiet --gid 998 i2c

# tinkerboard audio settings
ln -sf /etc/armbian/asound.conf /etc/asound.conf
sed -i -e "/#load-module module-alsa-sink/r /etc/armbian/pulseaudio.txt" /etc/pulse/default.pa >/dev/null 2>&1

# read config
[ -f /etc/armbian-release ] && . /etc/armbian-release

[ "\$BOARD" = "tinkerboard" ] && systemctl --no-reload enable tinker-bluetooth.service
if [ "\$BOARD" = "xt-q8l-v10" ]; then
	[ -z "\$(grep -w '^fdtfile=rk3288-xt-q8l-v10.dtb' /boot/armbianEnv.txt 2> /dev/null)" ] && echo "fdtfile=rk3288-xt-q8l-v10.dtb" >> /boot/armbianEnv.txt
	mkdir -p /etc/firmware/
	ln -sf /lib/firmware/brcm/BCM4330B1.hcd /etc/firmware
	systemctl --no-reload enable ap6330-bluetooth.service
fi
exit 0
EOF