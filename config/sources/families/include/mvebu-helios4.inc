case $BRANCH in

	legacy | current | edge)

		BOOTSOURCE=$MAINLINE_UBOOT_SOURCE
		BOOTBRANCH='tag:v2019.04'
		BOOTDIR=$MAINLINE_UBOOT_DIR
		BOOTPATCHDIR='u-boot-helios4'
		BOOTSCRIPT='boot-mvebu.cmd:boot.cmd'

		UBOOT_TARGET_MAP=";sdhc;u-boot-spl.kwb:u-boot.mmc
				  ;spi;u-boot-spl.kwb:u-boot.flash
				  ;uart;u-boot-spl.kwb:u-boot.uart"

		UBOOT_USE_GCC='> 7.0'

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

	## Postinst
	# Remove exit 0 on end of file
	sed -i '$ s/^exit 0//g' "${destination}"/DEBIAN/postinst

	cat <<- 'EOF' >> "${destination}"/DEBIAN/postinst
		### Mdadm tweaks
		MDADM_CONF=/etc/mdadm/mdadm.conf
		MDADM_HOOK=/usr/share/initramfs-tools/hooks/mdadm
		grep -q "PROGRAM" $MDADM_CONF
		if [ "$?" -ne 0 ]; then
			cat <<-EOS >> $MDADM_CONF
			# Trigger Fault Led script when an event is detected
			PROGRAM /usr/sbin/mdadm-fault-led.sh
			EOS
		fi

		# Fix for "mdadm: initramfs boot message: /scripts/local-bottom/mdadm: rm: not found"
		# Refer to https://wiki.kobol.io/helios4/mdadm/#fix-mdadm
		grep -q "^[[:blank:]]*copy_exec /bin/rm /bin" $MDADM_HOOK
		if [ "$?" -ne 0 ]; then
			sed -i '/copy_exec \/sbin\/mdmon \/sbin/ a\copy_exec /bin/rm /bin' $MDADM_HOOK
			update-initramfs -u
		fi

		# enable helios4-wol.service
		systemctl --no-reload enable helios4-wol.service >/dev/null 2>&1

		exit 0
	EOF
}
