cat <<EOF
#!/bin/sh
#
# ${BOARD} post installation script
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
if [ -f "/boot/bin/$BOARD.bin" ] && [ ! -f "/boot/script.bin" ]; then ln -sf bin/$BOARD.bin /boot/script.bin >/dev/null 2>&1 || cp /boot/bin/$BOARD.bin /boot/script.bin; fi
rm -f /usr/local/bin/h3disp /usr/local/bin/h3consumption
exit 0
EOF