#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
case $BRANCH in

	legacy | current | edge)

		BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
		BOOTDIR=$MAINLINE_UBOOT_DIR
		BOOTBRANCH='tag:v2025.10'
		BOOTPATCHDIR="${BOOTBRANCH#tag:}/board_${BOARD:?}"
		BOOTSCRIPT='boot-mvebu.cmd:boot.cmd'

		UBOOT_TARGET_MAP="
			;sata;u-boot-with-spl.kwb:u-boot.sata
			;sdhc;u-boot-with-spl.kwb:u-boot.mmc
			;spi;u-boot-with-spl.kwb:u-boot.flash
			;uart;u-boot-with-spl.kwb:u-boot.uart"

		OVERLAY_PREFIX='armada-388-helios4'
		;;

esac

# Helios4 tweak
family_tweaks_bsp() {
	## Add dependency list
	local DEPENDENCIES="fancontrol, mdadm"
	sed -i "/^Depends:/ s/$/, $DEPENDENCIES/" "${destination}"/DEBIAN/control

	## Pack additional files

	mkdir -p $destination/etc/systemd/system/
	mkdir -p $destination/etc/udev/rules.d/
	mkdir -p $destination/etc/default/
	mkdir -p $destination/lib/systemd/system/
	mkdir -p $destination/usr/sbin

	### Fancontrol tweaks
	# copy hwmon rules to fix device mapping
	install -m 644 $SRC/packages/bsp/mvebu/helios4/90-helios4-hwmon.rules $destination/etc/udev/rules.d/

	# copy fancontrol config
	install -m 644 $SRC/packages/bsp/mvebu/helios4/fancontrol_pwm-fan.conf $destination/etc/fancontrol
	install -m 644 $SRC/packages/bsp/mvebu/helios4/fancontrol.service $destination/etc/systemd/system/

	### Mdadm tweaks

	# copy mdadm-fault-led script and set right permission
	install -m 755 $SRC/packages/bsp/mvebu/helios4/mdadm-fault-led.sh $destination/usr/sbin

	### Ethernet tweaks

	# copy and enable helios4-wol.service
	install -m 644 $SRC/packages/bsp/mvebu/helios4/helios4-wol.service $destination/lib/systemd/system/

	### Other tweaks

	# add custom motd default conf file
	install -m 644 $SRC/packages/bsp/mvebu/helios4/armbian-motd $destination/etc/default/

	# create modules file
	if [[ $BRANCH == dev && -n $MODULES_EDGE ]]; then
		tr ' ' '\n' <<< "$MODULES_DEV" > "${destination}"/etc/modules
	elif [[ $BRANCH == current || $BRANCH == dev ]]; then
		tr ' ' '\n' <<< "$MODULES_CURRENT" > "${destination}"/etc/modules
	else
		tr ' ' '\n' <<< "$MODULES_LEGACY" > "${destination}"/etc/modules
	fi

	display_alert "Adding to bsp-cli" "${BOARD}: postinst for mdadm and wol service" "info"
	# Define a function to be run board-side during postinst of the BSP
	# FIXME: this is a big no-no.  postinst should never unilaterally muck around with config files in /etc
	postinst_functions+=("board_side_helios4_bsp_cli_postinst_mdadm") # add to the postinst function list
	function board_side_helios4_bsp_cli_postinst_mdadm() {
		### Mdadm tweaks
		MDADM_CONF=/etc/mdadm/mdadm.conf

		if [ -f $MDADM_CONF ]; then
			grep -q "PROGRAM" $MDADM_CONF
			if [ "$?" -ne 0 ]; then
				cat <<- EOS >> $MDADM_CONF
					# Trigger Fault Led script when an event is detected
					PROGRAM /usr/sbin/mdadm-fault-led.sh
				EOS
			fi
		fi

		# enable helios4-wol.service
		systemctl --no-reload enable helios4-wol.service
	}

}
