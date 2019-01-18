cat <<EOF
#!/bin/sh
#
# ${FAMILY} post installation script
#


# read config
[ -f /etc/armbian-release ] && . /etc/armbian-release


if [ "\$BOARD" = "nanopct4" ]; then
	[ -z "\$(grep -w '^fdtfile=rockchip/rk3399-nanopi4-rev00.dtb' /boot/armbianEnv.txt 2> /dev/null)" ] \
	&& echo "fdtfile=rockchip/rk3399-nanopi4-rev00.dtb" >> /boot/armbianEnv.txt
fi

if [ "\$BOARD" = "nanopim4" ]; then
	[ -z "\$(grep -w '^fdtfile=rockchip/rk3399-nanopi4-rev01.dtb' /boot/armbianEnv.txt 2> /dev/null)" ] \
	&& echo "fdtfile=rockchip/rk3399-nanopi4-rev00.dtb" >> /boot/armbianEnv.txt
fi

if [ "\$BOARD" = "nanopineo4" ]; then
	[ -z "\$(grep -w '^fdtfile=rockchip/rk3399-nanopi4-rev04.dtb' /boot/armbianEnv.txt 2> /dev/null)" ] \
	&& echo "fdtfile=rockchip/rk3399-nanopi4-rev00.dtb" >> /boot/armbianEnv.txt
fi

if [ "\$BOARD" = "firefly-rk3399" ]; then
	[ -z "\$(grep -w '^fdtfile=rockchip/rk3399-nanopi4-rev00.dtb' /boot/armbianEnv.txt 2> /dev/null)" ] \
	&& echo "fdtfile=rockchip/rk3399-firefly.dtb" >> /boot/armbianEnv.txt
fi

exit 0
EOF