cat <<EOF
#!/bin/sh
#
# ${BOARD} BSP post installation script
#



# configure MIN / MAX speed for cpufrequtils
if [ -z "\$(cat /etc/default/cpufr1equtils 2> /dev/null | awk -F'[=&]' '{print \$2}')" ]; then
cat <<-EOT > /etc/default/cpufrequtils
ENABLE=true
MIN_SPEED=$CPUMIN
MAX_SPEED=$CPUMAX
GOVERNOR=$GOVERNOR
EOT
fi

# enable ramlog only if it was enabled before
if [ -n "\$(service log2ram status 2> /dev/null)" ]; then
	systemctl --no-reload enable armbian-ramlog.service
fi

# check if it was disabled in config and disable in new service
if [ -n "\$(grep -w '^ENABLED=false' /etc/default/log2ram 2> /dev/null)" ]; then
	sed -i "s/^ENABLED=.*/ENABLED=false/" /etc/default/armbian-ramlog
fi

# fix boot delay "waiting for suspend/resume device"
if [ -f "/etc/initramfs-tools/initramfs.conf" ]; then
	if ! grep --quiet "RESUME=none" /etc/initramfs-tools/initramfs.conf; then
	echo "RESUME=none" >> /etc/initramfs-tools/initramfs.conf
	fi
fi

# install bootscripts if they are not present. Fix upgrades from old images
if [ ! -f /boot/$bootscript_dst ]; then
	echo "Recreating boot script"
	cp /usr/share/armbian/$bootscript_dst /boot  >/dev/null 2>&1
	rootdev=\$(sed -e 's/^.*root=//' -e 's/ .*\$//' < /proc/cmdline)
	cp /usr/share/armbian/armbianEnv.txt /boot  >/dev/null 2>&1
	echo "rootdev="\$rootdev >> /boot/armbianEnv.txt
	sed -i "s/setenv rootdev.*/setenv rootdev \\"\$rootdev\\"/" /boot/boot.ini
	[ -f /boot/boot.cmd ] && mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr  >/dev/null 2>&1
EOF

if [[ $FORCE_BOOTSCRIPT_UPDATE == yes ]]; then
cat <<EOF
else
	echo "Updating bootscript"
	# copy new bootscript
	cp /usr/share/armbian/$bootscript_dst /boot  >/dev/null 2>&1

	# build new bootscript
	if [ -f /boot/boot.cmd ]; then
		mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr  >/dev/null 2>&1
	elif [ -f /boot/boot.ini ]; then
		rootdev=\$(sed -e 's/^.*root=//' -e 's/ .*\$//' < /proc/cmdline)
		sed -i "s/setenv rootdev.*/setenv rootdev \\"\$rootdev\\"/" /boot/boot.ini
	fi
	# cleanup old bootscript backup
	[ -f /usr/share/armbian/boot.cmd ] && ls /usr/share/armbian/boot.cmd-* | head -n -5 | xargs rm -f --
	[ -f /usr/share/armbian/boot.ini ] && ls /usr/share/armbian/boot.ini-* | head -n -5 | xargs rm -f --
EOF
fi
cat <<EOF
fi
# now cleanup and remove old ramlog service
systemctl disable log2ram.service >/dev/null 2>&1
[ -f "/usr/sbin/log2ram" ] && rm /usr/sbin/log2ram
[ -f "/usr/share/log2ram/LICENSE" ] && rm -r /usr/share/log2ram
[ -f "/lib/systemd/system/log2ram.service" ] && rm /lib/systemd/system/log2ram.service
[ -f "/etc/cron.daily/log2ram" ] && rm /etc/cron.daily/log2ram
[ -f "/etc/default/log2ram.dpkg-dist" ] && rm /etc/default/log2ram.dpkg-dist

[ ! -f "/etc/network/interfaces" ] && cp /etc/network/interfaces.default /etc/network/interfaces
ln -sf /var/run/motd /etc/motd
rm -f /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text
if [ -f "/boot/bin/$BOARD.bin" ] && [ ! -f "/boot/script.bin" ]; then ln -sf bin/$BOARD.bin /boot/script.bin >/dev/null 2>&1 || cp /boot/bin/$BOARD.bin /boot/script.bin; fi
rm -f /usr/local/bin/h3disp /usr/local/bin/h3consumption
if [ ! -f "/etc/default/armbian-motd" ]; then
	mv /etc/default/armbian-motd.dpkg-dist /etc/default/armbian-motd
fi
if [ ! -f "/etc/default/armbian-ramlog" ]; then
	mv /etc/default/armbian-ramlog.dpkg-dist /etc/default/armbian-ramlog
fi
if [ ! -f "/etc/default/armbian-zram-config" ]; then
	mv /etc/default/armbian-zram-config.dpkg-dist /etc/default/armbian-zram-config
fi

if [ -L "/usr/lib/chromium-browser/master_preferences.dpkg-dist" ]; then
	mv /usr/lib/chromium-browser/master_preferences.dpkg-dist /usr/lib/chromium-browser/master_preferences
fi

systemctl --no-reload enable armbian-hardware-monitor.service armbian-hardware-optimize.service armbian-zram-config.service >/dev/null 2>&1
exit 0
EOF