# Rockchip RK3399 hexa core 4GB RAM SoC WiFi/BT
BOARD_NAME="Clockworkpi A06"
BOARDFAMILY="rockchip64"
BOOTCONFIG="clockworkpi-a06-rk3399_defconfig"
KERNEL_TARGET="legacy,current,edge"
FULL_DESKTOP="yes"
BOOT_LOGO="no"
BOOTBRANCH_BOARD="tag:v2022.04"
BOOTPATCHDIR="u-boot-rockchip64-v2022.04"

function post_family_tweaks_bsp__clockworkpi-a06() {
    display_alert "Installing BSP firmware and fixups"

	# rotate screen & disable dpms
	mkdir -p "$destination"/etc/X11/xorg.conf.d
	cat <<- EOF > "$destination"/etc/X11/xorg.conf.d/10-monitor.conf
		# set monitor
		Section "Monitor"
		        Identifier "DSI-1"
		        Option "Rotate" "right"
		        Option "DPMS" "false"
		EndSection

		Section "ServerLayout"
		        Identifier "ServerLayout0"
		        Option "BlankTime"  "0"
		        Option "StandbyTime" "0"
		        Option "SuspendTime" "0"
		        Option "OffTime" "0"
		EndSection
	EOF
	# fan support
	install -Dm644 $SRC/packages/bsp/clockworkpi-a06/temp_fan_daemon_a06.py $destination/usr/share/clockworkpi-a06-fan-daemon/bin/temp_fan_daemon_a06.py
	cp $SRC/packages/bsp/clockworkpi-a06/clockworkpi-a06-fan-daemon.service $destination/lib/systemd/system/

	# alsa-ucm-conf profile for DevTerm A06
	mkdir -p $destination/usr/share/alsa/ucm2/Rockchip/es8388
	install -Dm644 $SRC/packages/bsp/clockworkpi-a06/es8388.conf $destination/usr/share/alsa/ucm2/Rockchip/es8388/es8388.conf
	install -Dm644 $SRC/packages/bsp/clockworkpi-a06/HiFi.conf $destination/usr/share/alsa/ucm2/Rockchip/es8388/HiFi.conf
	mkdir -p $destination/usr/share/alsa/ucm2/conf.d/simple-card
	ln -sfv /usr/share/alsa/ucm2/Rockchip/es8388/es8388.conf \
		$destination/usr/share/alsa/ucm2/conf.d/simple-card/rockchip,es8388-codec.conf

	return 0
}
