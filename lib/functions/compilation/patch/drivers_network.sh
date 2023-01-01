#!/bin/bash

extrawifi_patch_default()
{
	local name="$1"
	local repo="$2"
	local ref="$3"

	fetch_from_repo "${repo}" "${name}" "${ref}" "yes"

	cd "$kerneldir" || exit
	mkdir -p "${kerneldir}/drivers/net/wireless/${name}"
	cp -R "${SRC}/cache/sources/${name}/${ref##*:}/." \
		"$kerneldir/drivers/net/wireless/${name}/"

	# https://github.com/torvalds/linux/commit/8f268881d7d278047b00eed54bbb9288dbd6ab23
	sed -i 's/---help---/help/g' \
		"${kerneldir}/drivers/net/wireless/${name}/Kconfig"

	# Append to section Makefile
	local config="$(grep --max-count=1 '^config ' "${kerneldir}/drivers/net/wireless/${name}/Kconfig" | cut -d' ' -f2)"
	echo "obj-\$(${config}) += ${name}/" >>"${kerneldir}/drivers/net/wireless/Makefile"

	# Append to section Kconfig
	sed -i "
		1h;1!H;\$!d;x;
		s@.*\nsource [^\n]*@&\nsource \"drivers/net/wireless/${name}/Kconfig\"@
	" "${kerneldir}/drivers/net/wireless/Kconfig"

}

driver_rtl8152_rtl8153()
{
	# Updated USB network drivers for RTL8152/RTL8153 based dongles that also support 2.5Gbs variants
	if linux-version compare "${version}" ge 5.4 && linux-version compare "${version}" le 5.12 && [ "$LINUXFAMILY" != mvebu64 ] && [ "$LINUXFAMILY" != rk322x ] && [ "$LINUXFAMILY" != odroidxu4 ] && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8152ver="branch:master"

		display_alert "Adding" "Drivers for 2.5Gb RTL8152/RTL8153 USB dongles ${rtl8152ver}" "info"
		fetch_from_repo "$GITHUB_SOURCE/igorpecovnik/realtek-r8152-linux" "rtl8152" "${rtl8152ver}" "yes"
		cp -R "${SRC}/cache/sources/rtl8152/${rtl8152ver#*:}"/{r8152.c,compatibility.h} \
			"$kerneldir/drivers/net/usb/"

	fi
}

driver_rtl8189ES()
{
	# Wireless drivers for Realtek 8189ES chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		display_alert "Adding" "Wireless drivers for Realtek 8189ES chipsets ${rtl8189esver}" "info"

		extrawifi_patch_default "rtl8189es" \
			"$GITHUB_SOURCE/jwrdegoede/rtl8189ES_linux" \
			"branch:master"

	fi
}

driver_rtl8189FS()
{


	# Wireless drivers for Realtek 8189FS chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		display_alert "Adding" "Wireless drivers for Realtek 8189FS chipsets ${rtl8189fsver}" "info"

		extrawifi_patch_default "rtl8189fs" \
			"$GITHUB_SOURCE/jwrdegoede/rtl8189ES_linux" \
			"branch:rtl8189fs"

	fi

}

driver_rtl8192EU()
{

	# Wireless drivers for Realtek 8192EU chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		display_alert "Adding" "Wireless drivers for Realtek 8192EU chipsets ${rtl8192euver}" "info"

		extrawifi_patch_default "rtl8192eu" \
			"$GITHUB_SOURCE/Mange/rtl8192eu-linux-driver" \
			"branch:realtek-4.4.x"

	fi
}

driver_rtl8811_rtl8812_rtl8814_rtl8821()
{

	# Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		display_alert "Adding" "Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets ${rtl8812auver}" "info"

		extrawifi_patch_default "rtl8812au" \
			"$GITHUB_SOURCE/aircrack-ng/rtl8812au" \
			"commit:450db78f7bd23f0c611553eb475fa5b5731d6497"

	fi

}

driver_xradio_xr819()
{

	# Wireless drivers for Xradio XR819 chipsets
	if linux-version compare "${version}" ge 4.19 && linux-version compare "${version}" le 5.19 &&
		[[ "$LINUXFAMILY" == sunxi* ]] && [[ "$EXTRAWIFI" == yes ]]; then

		display_alert "Adding" "Wireless drivers for Xradio XR819 chipsets" "info"

		extrawifi_patch_default "xradio" \
			"$GITHUB_SOURCE/dbeinder/xradio" \
			"branch:karabek_rebase"

		# add support for K5.13+
		process_patch_file "${SRC}/patch/misc/wireless-xradio-5.13.patch" "applying"

		# add support for aarch64
		if [[ $ARCH == arm64 ]]; then
			process_patch_file "${SRC}/patch/misc/wireless-xradio-aarch64.patch" "applying"
		fi

	fi

}

driver_rtl8811CU_rtl8821C()
{
	# Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		display_alert "Adding" "Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets ${rtl8811cuver}" "info"

		extrawifi_patch_default "rtl8811cu" \
			"$GITHUB_SOURCE/morrownr/8821cu-20210118" \
			"commit:7b8c45a270454f05e2dbf3beeb4afcf817db65da"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Address ARM related bug $GITHUB_SOURCE/aircrack-ng/rtl8812au/issues/233
		sed -i "s/^CONFIG_MP_VHT_HW_TX_MODE.*/CONFIG_MP_VHT_HW_TX_MODE = n/" \
			"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

	fi

}

driver_rtl8188EU_rtl8188ETV()
{

	# Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets

	if linux-version compare "${version}" ge 3.14 &&
		linux-version compare "${version}" lt 5.15 &&
		[ "$EXTRAWIFI" == yes ]; then

		display_alert "Adding" "Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets ${rtl8188euver}" "info"

		extrawifi_patch_default "rtl8188eus" \
			"$GITHUB_SOURCE/aircrack-ng/rtl8188eus" \
			"branch:v5.7.6.1"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8188eu/Makefile"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8188eu.patch" "applying"

		# add support for K5.12+
		process_patch_file "${SRC}/patch/misc/wireless-realtek-8188eu-5.12.patch" "applying"

	fi
}

driver_rtl88x2bu()
{

	# Wireless drivers for Realtek 88x2bu chipsets

	if linux-version compare "${version}" ge 5.0 && [ "$EXTRAWIFI" == yes ]; then

		display_alert "Adding" "Wireless drivers for Realtek 88x2bu chipsets ${rtl88x2buver}" "info"

		extrawifi_patch_default "rtl88x2bu" \
			"$GITHUB_SOURCE/morrownr/88x2bu-20210702" \
			"commit:2590672d717e2516dd2e96ed66f1037a6815bced"
	
		# Adjust path
		sed -i "s/include \$(src)\/rtl8822b.mk /include \$(TopDIR)\/drivers\/net\/wireless\/rtl88x2bu\/rtl8822b.mk/" \
			"$kerneldir/drivers/net/wireless/rtl88x2bu/Makefile"

	fi

}

driver_rtl88x2cs()
{

	# Wireless drivers for Realtek 88x2cs chipsets

	if linux-version compare "${version}" ge 5.9 && [ "$EXTRAWIFI" == yes ] ; then

		display_alert "Adding" "Wireless drivers for Realtek 88x2cs chipsets ${rtl88x2csver}" "info"

		extrawifi_patch_default "rtl88x2cs" \
			"$GITHUB_SOURCE/jethome-ru/rtl88x2cs" \
			"branch:tune_for_jethub"

		# Adjust path
		sed -i "s/include \$(src)\/rtl8822c.mk/include \$(TopDIR)\/drivers\/net\/wireless\/rtl88x2cs\/rtl8822c.mk/" \
			"$kerneldir/drivers/net/wireless/rtl88x2cs/Makefile"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl88x2cs/Makefile"

	fi

}

#_bt for blueteeth
driver_rtl8822cs_bt()
{
	# Bluetooth support for Realtek 8822CS (hci_ver 0x8) chipsets
	# For sunxi, these two patches are applied in a series.
	if linux-version compare "${version}" ge 5.11 && [[ "$LINUXFAMILY" != sunxi* ]]; then

		display_alert "Adding" "Bluetooth support for Realtek 8822CS (hci_ver 0x8) chipsets" "info"

		process_patch_file "${SRC}/patch/misc/bluetooth-rtl8822cs-hci_ver-0x8.patch" "applying"
		process_patch_file "${SRC}/patch/misc/Bluetooth-hci_h5-Add-power-reset-via-gpio-in-h5_btrt.patch" "applying"

	fi
}

driver_rtl8723DS()
{
	# Wireless drivers for Realtek 8723DS chipsets

	if linux-version compare "${version}" ge 5.0 && [[ "$EXTRAWIFI" == yes ]]; then

		display_alert "Adding" "Wireless drivers for Realtek 8723DS chipsets ${rtl8723dsver}" "info"

		extrawifi_patch_default "rtl8723ds" \
			"$GITHUB_SOURCE/lwfinger/rtl8723ds" \
			"branch:master"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8723ds/Makefile"

	fi
}

driver_rtl8723DU()
{

	# Wireless drivers for Realtek 8723DU chipsets

	if linux-version compare "${version}" ge 5.0 && [ "$EXTRAWIFI" == yes ]; then

		display_alert "Adding" "Wireless drivers for Realtek 8723DU chipsets ${rtl8723duver}" "info"

		extrawifi_patch_default "rtl8723du" \
			"$GITHUB_SOURCE/lwfinger/rtl8723du" \
			"branch:master"
	
		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8723du/Makefile"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8723du-5.19.2.patch" "applying"

	fi
}

driver_rtl8822BS()
{
	# Wireless drivers for Realtek 8822BS chipsets

	if linux-version compare "${version}" ge 4.4 && linux-version compare "${version}" le 5.16 && [ "$EXTRAWIFI" == yes ]; then

		display_alert "Adding" "Wireless drivers for Realtek 8822BS chipsets ${rtl8822bsver}" "info"

		extrawifi_patch_default "rtl8822bs" \
			"$GITHUB_SOURCE/150balbes/wifi" \
			"branch:local_rtl8822bs"

	fi

}

patch_drivers_network()
{
	display_alert "Patching network related drivers"
	
	driver_rtl8152_rtl8153
	driver_rtl8189ES
	driver_rtl8189FS
	driver_rtl8192EU
	driver_rtl8811_rtl8812_rtl8814_rtl8821
	driver_xradio_xr819
	driver_rtl8811CU_rtl8821C
	driver_rtl8188EU_rtl8188ETV
	driver_rtl88x2bu
	driver_rtl88x2cs
	driver_rtl8822cs_bt
	driver_rtl8723DS
	driver_rtl8723DU
	driver_rtl8822BS

	display_alert "Network related drivers patched" "" "info"
}
