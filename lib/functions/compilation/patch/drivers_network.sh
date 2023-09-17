#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

function driver_generic_bring_back_ipx() {
	#
	# Returning headers needed for some wireless drivers
	#
	if linux-version compare "${version}" ge 5.4; then
		display_alert "Reverting upstream-removed" "IPX stuff needed for Wireless Drivers" "info"
		process_patch_file "${SRC}/patch/misc/wireless-bring-back-headers.patch" "applying"
	fi
}

driver_mt7921u_add_pids() {
	# Add two popular cheap USB devices to the table
	if linux-version compare "${version}" ge 6.1 && linux-version compare "${version}" lt 6.2; then
		display_alert "Mediatek MT7921u" "Add Comfast CF952A and Netgear AXE3000" "info"
		process_patch_file "${SRC}/patch/misc/wireless-mt7921u-add-pids.patch" "applying"
	fi
}

driver_rtl8152_rtl8153() {
	# Updated USB network drivers for RTL8152/RTL8153 based dongles that also support 2.5Gbs variants
	if linux-version compare "${version}" ge 5.4 && linux-version compare "${version}" le 5.12 && [ "$LINUXFAMILY" != mvebu64 ] && [ "$LINUXFAMILY" != rk322x ] && [ "$LINUXFAMILY" != odroidxu4 ]; then

		# attach to specifics tag or branch
		local rtl8152ver="branch:master"

		display_alert "Adding" "Drivers for 2.5Gb RTL8152/RTL8153 USB dongles ${rtl8152ver}" "info"
		fetch_from_repo "$GITHUB_SOURCE/igorpecovnik/realtek-r8152-linux" "rtl8152" "${rtl8152ver}" "yes"
		cp -R "${SRC}/cache/sources/rtl8152/${rtl8152ver#*:}"/{r8152.c,compatibility.h} \
			"$kerneldir/drivers/net/usb/"

	fi
}

driver_rtl8189ES() {
	# Wireless drivers for Realtek 8189ES chipsets

	if linux-version compare "${version}" ge 3.14; then

		# attach to specifics tag or branch
		local rtl8189esver="branch:master"

		display_alert "Adding" "Wireless drivers for Realtek 8189ES chipsets ${rtl8189esver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/jwrdegoede/rtl8189ES_linux" "rtl8189es" "${rtl8189esver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8189es"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8189es/"
		cp -R "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}"/{core,hal,include,os_dep,platform} \
			"$kerneldir/drivers/net/wireless/rtl8189es"

		# Makefile
		cp "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl8189es/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl8189es/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8189ES) += rtl8189es/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8189es\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8189es/Makefile"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8189es-Fix-uninitialized-cfg80211-chan-def.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8189es-Fix-p2p-go-advertising.patch" "applying"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl8189es-Fix-VFS-import.patch" "applying"

		# fix compilation for kernels >= 5.4.251
		process_patch_file "${SRC}/patch/misc/wireless-rtl8189es-Fix-building-on-5.4.251-kernel.patch" "applying"
	fi
}

driver_rtl8189FS() {

	# Wireless drivers for Realtek 8189FS chipsets

	if linux-version compare "${version}" ge 3.14; then

		# attach to specifics tag or branch
		local rtl8189fsver="branch:rtl8189fs"

		display_alert "Adding" "Wireless drivers for Realtek 8189FS chipsets ${rtl8189fsver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/jwrdegoede/rtl8189ES_linux" "rtl8189fs" "${rtl8189fsver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8189fs"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8189fs/"
		cp -R "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}"/{core,hal,include,os_dep,platform} \
			"$kerneldir/drivers/net/wireless/rtl8189fs"

		# Makefile
		cp "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl8189fs/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl8189fs/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8189FS) += rtl8189fs/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8189fs\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8189fs/Makefile"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8189fs-fix-p2p-go-advertising.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8189fs-fix-and-enable-secondary-iface.patch" "applying"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl8189fs-Fix-VFS-import.patch" "applying"

		# fix compilation for kernels >= 5.4.251
		process_patch_file "${SRC}/patch/misc/wireless-rtl8189fs-Fix-building-on-5.4.251-kernel.patch" "applying"
	fi

}

driver_rtl8192EU() {

	# Wireless drivers for Realtek 8192EU chipsets

	if linux-version compare "${version}" ge 3.14; then

		# attach to specifics tag or branch
		local rtl8192euver="branch:realtek-4.4.x"

		display_alert "Adding" "Wireless drivers for Realtek 8192EU chipsets ${rtl8192euver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/Mange/rtl8192eu-linux-driver" "rtl8192eu" "${rtl8192euver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8192eu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8192eu/"
		cp -R "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}"/{core,hal,include,os_dep,platform} \
			"$kerneldir/drivers/net/wireless/rtl8192eu"

		# Makefile
		cp "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl8192eu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl8192eu/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8192EU) += rtl8192eu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8192eu\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8192eu-Fix-p2p-go-advertising.patch" "applying"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl8192eu-Fix-VFS-import.patch" "applying"

		# fix compilation for kernels >= 5.4.251
		process_patch_file "${SRC}/patch/misc/wireless-rtl8192eu-Fix-building-on-5.4.251-kernel.patch" "applying"
	fi
}

driver_rtl8811_rtl8812_rtl8814_rtl8821() {

	# Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets

	if linux-version compare "${version}" ge 3.14; then

		# attach to specifics tag or branch
		local rtl8812auver="commit:450db78f7bd23f0c611553eb475fa5b5731d6497"

		display_alert "Adding" "Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets ${rtl8812auver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/aircrack-ng/rtl8812au" "rtl8812au" "${rtl8812auver}" "yes"
		cd "$kerneldir" || exit

		# Brief detour. Turns out that HardKernel's vendor odroidxu4 kernel already has this driver
		# "slipstreamed" into it, complete with a bunch of PDF files and other junk.
		# See https://github.com/hardkernel/linux/tree/odroid-5.4.y/drivers/net/wireless/rtl8812au
		# If we remove them here, the resulting patch will contain binary diffs which are unsupported by patch(1).
		# So if building for the odroidxu4/current, we'll leave the original files in place, and just overwrite
		# the possibly-updated source files (not PDFs and such). Thanks, HardKernel.
		if [[ "${LINUXFAMILY}/${BRANCH}" == "odroidxu4/current" ]]; then
			display_alert "Skipping" "Removing rtl8812au files from odroidxu4 kernel" "info"
		else
			rm -rf "$kerneldir/drivers/net/wireless/rtl8812au"
		fi

		mkdir -p "$kerneldir/drivers/net/wireless/rtl8812au/"
		cp -R "${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}"/{core,hal,include,os_dep,platform} \
			"$kerneldir/drivers/net/wireless/rtl8812au"

		# Makefile
		cp "${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl8812au/Makefile"

		# Kconfig
		cp "${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl8812au/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_88XXAU) += rtl8812au/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8812au\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		# fix compilation for kernels >= 6.3
		process_patch_file "${SRC}/patch/misc/wireless-rtl8812au-6.3.patch" "applying"

	fi

}

driver_xradio_xr819() {

	# Wireless drivers for Xradio XR819 chipsets
	if linux-version compare "${version}" ge 4.19 && [[ "$LINUXFAMILY" == sunxi* ]]; then

		display_alert "Adding" "Wireless drivers for Xradio XR819 chipsets" "info"

		fetch_from_repo "$GITHUB_SOURCE/dbeinder/xradio" "xradio" "branch:karabek_rebase" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/xradio"
		mkdir -p "$kerneldir/drivers/net/wireless/xradio/"
		cp "${SRC}"/cache/sources/xradio/karabek_rebase/*.{h,c} \
			"$kerneldir/drivers/net/wireless/xradio/"

		# Makefile
		cp "${SRC}/cache/sources/xradio/karabek_rebase/Makefile" \
			"$kerneldir/drivers/net/wireless/xradio/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/xradio/karabek_rebase/Kconfig"
		cp "${SRC}/cache/sources/xradio/karabek_rebase/Kconfig" \
			"$kerneldir/drivers/net/wireless/xradio/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_WLAN_VENDOR_XRADIO) += xradio/" \
			>> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/xradio\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		# add support for K5.13+
		process_patch_file "${SRC}/patch/misc/wireless-xradio-5.13.patch" "applying"

		# add support for K5.19+
		process_patch_file "${SRC}/patch/misc/wireless-xradio-code-cleanup.patch" "applying"

		# add support for K5.19+
		process_patch_file "${SRC}/patch/misc/wireless-xradio-insmod-rmmod-fx.patch" "applying"

		# add support for K5.19+
		process_patch_file "${SRC}/patch/misc/wireless-xradio-5.19.patch" "applying"

		# add support for K6.0+
		process_patch_file "${SRC}/patch/misc/wireless-xradio-6.0.patch" "applying"

		# add support for K6.1+
		process_patch_file "${SRC}/patch/misc/wireless-xradio-6.1.patch" "applying"

		# add support for K6.2+
		process_patch_file "${SRC}/patch/misc/wireless-xradio-6.2.patch" "applying"

		# vmmaped stack memory access fix
		process_patch_file "${SRC}/patch/misc/wireless-xradio-vmmaped-stack-fix.patch" "applying"

		# add support for aarch64
		if [[ $ARCH == arm64 ]]; then
			process_patch_file "${SRC}/patch/misc/wireless-xradio-aarch64.patch" "applying"
		fi

	fi

}

driver_rtl8811CU_rtl8821C() {
	# Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets

	if linux-version compare "${version}" ge 3.14; then

		# attach to specifics tag or branch
		local rtl8811cuver="commit:9e2772540f66a69170f43864a6560d0d190d97b1"

		display_alert "Adding" "Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets ${rtl8811cuver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/morrownr/8821cu-20210916" "rtl8811cu" "${rtl8811cuver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8811cu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8811cu/"
		cp -R "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}"/{core,hal,include,os_dep,platform,*.mk} \
			"$kerneldir/drivers/net/wireless/rtl8811cu"

		# Makefile
		cp "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl8811cu/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Address ARM related bug $GITHUB_SOURCE/aircrack-ng/rtl8812au/issues/233
		sed -i "s/^CONFIG_MP_VHT_HW_TX_MODE.*/CONFIG_MP_VHT_HW_TX_MODE = n/" \
			"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8821CU) += rtl8811cu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8811cu\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8811cu-Fix-p2p-go-advertising.patch" "applying"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl8811cu-Fix-VFS-import.patch" "applying"

	fi

}

driver_rtl8188EU_rtl8188ETV() {

	# Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets

	if linux-version compare "${version}" ge 3.14 &&
		linux-version compare "${version}" lt 5.15; then

		# attach to specifics tag or branch
		local rtl8188euver="branch:v5.7.6.1"

		display_alert "Adding" "Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets ${rtl8188euver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/aircrack-ng/rtl8188eus" "rtl8188eu" "${rtl8188euver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8188eu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8188eu/"
		cp -R "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}"/{core,hal,include,os_dep,platform} \
			"$kerneldir/drivers/net/wireless/rtl8188eu"

		# Makefile
		cp "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl8188eu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl8188eu/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8188eu/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8188EU) += rtl8188eu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8188eu\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8188eu.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-realtek-8188eu-5.12.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8188eu-Fix-uninitialized-cfg80211-chan-def.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8188eu-Fix-p2p-go-advertising.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8188eu-Fix-misleading-indentation.patch" "applying"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl8188eu-Fix-VFS-import.patch" "applying"
	fi
}

driver_rtl88x2bu() {

	# Wireless drivers for Realtek 88x2bu chipsets

	if linux-version compare "${version}" ge 5.0; then

		# attach to specifics tag or branch
		local rtl88x2buver="commit:2590672d717e2516dd2e96ed66f1037a6815bced"

		display_alert "Adding" "Wireless drivers for Realtek 88x2bu chipsets ${rtl88x2buver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/morrownr/88x2bu-20210702" "rtl88x2bu" "${rtl88x2buver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl88x2bu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl88x2bu/"
		cp -R "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}"/{core,hal,include,os_dep,platform,halmac.mk,rtl8822b.mk} \
			"$kerneldir/drivers/net/wireless/rtl88x2bu"

		# Makefile
		cp "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl88x2bu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl88x2bu/Kconfig"

		# Adjust path
		sed -i "s/include \$(src)\/rtl8822b.mk /include \$(TopDIR)\/drivers\/net\/wireless\/rtl88x2bu\/rtl8822b.mk/" \
			"$kerneldir/drivers/net/wireless/rtl88x2bu/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8822BU) += rtl88x2bu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i "/source \"drivers\/net\/wireless\/ti\/Kconfig\"/a source \"drivers\/net\/wireless\/rtl88x2bu\/Kconfig\"" \
			"$kerneldir/drivers/net/wireless/Kconfig"

		process_patch_file "${SRC}/patch/misc/wireless-rtl88x2bu-Fix-p2p-go-advertising.patch" "applying"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl88x2bu-Fix-VFS-import.patch" "applying"

		# fix compilation for kernels >= 6.3
		process_patch_file "${SRC}/patch/misc/wireless-rtl88x2bu-6.3.0.patch" "applying"

		# fix compilation for kernels >= 6.3.13 < 6.4 and >= 6.5
		process_patch_file "${SRC}/patch/misc/wireless-rtl88x2bu-wireless-ignore-stale-kickoff-removal.patch" "applying"

	fi

}

driver_rtw88() {
	# Quite a few kernel families have KERNEL_DRIVERS_SKIP listing this driver. If so, this won't even be called.

	# Upstream wireless RTW88 drivers (wireless-next-2023-08-25)
	if linux-version compare "${version}" ge 6.1; then
		display_alert "Adding" "Upstream wireless RTW88 drivers" "info"
		process_patch_file "${SRC}/patch/misc/rtw88/${version}/001-drivers-net-wireless-realtek-rtw88-upstream-wireless.patch" "applying"
		process_patch_file "${SRC}/patch/misc/rtw88/hack/002-rtw88-usb-make-work-queues-high-priority.patch" "applying"
		process_patch_file "${SRC}/patch/misc/rtw88/hack/003-rtw88-decrease-the-log-level-of-tx-report.patch" "applying"
	fi
}

driver_rtl88x2cs() {

	# Wireless drivers for Realtek 88x2cs chipsets

	if linux-version compare "${version}" ge 5.9 && linux-version compare "${version}" lt 6.1; then

		# attach to specifics tag or branch
		local rtl88x2csver="branch:tune_for_jethub"

		display_alert "Adding" "Wireless drivers for Realtek 88x2cs chipsets ${rtl88x2csver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/jethome-ru/rtl88x2cs" "rtl88x2cs" "${rtl88x2csver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl88x2cs"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl88x2cs/"
		cp -R "${SRC}/cache/sources/rtl88x2cs/${rtl88x2csver#*:}"/{core,hal,include,os_dep,platform,halmac.mk,ifcfg-wlan0,rtl8822c.mk,runwpa,wlan0dhcp} \
			"$kerneldir/drivers/net/wireless/rtl88x2cs"

		# Makefile
		cp "${SRC}/cache/sources/rtl88x2cs/${rtl88x2csver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl88x2cs/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl88x2cs/${rtl88x2csver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl88x2cs/${rtl88x2csver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl88x2cs/Kconfig"

		# Adjust path
		sed -i "s/include \$(src)\/rtl8822c.mk/include \$(TopDIR)\/drivers\/net\/wireless\/rtl88x2cs\/rtl8822c.mk/" \
			"$kerneldir/drivers/net/wireless/rtl88x2cs/Makefile"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl88x2cs/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8822CS) += rtl88x2cs/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl88x2cs\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl88x2cs-Fix-VFS-import.patch" "applying"
	fi
}
#_bt for blueteeth
driver_rtl8822cs_bt() {
	# Bluetooth support for Realtek 8822CS (hci_ver 0x8) chipsets
	# both of these patches were upstreamed in 5.18
	if linux-version compare "${version}" ge 5.11 && linux-version compare "${version}" lt 5.18; then

		display_alert "Adding" "Bluetooth support for Realtek 8822CS (hci_ver 0x8) chipsets" "info"

		process_patch_file "${SRC}/patch/misc/bluetooth-rtl8822cs-hci_ver-0x8.patch" "applying"
		process_patch_file "${SRC}/patch/misc/Bluetooth-hci_h5-Add-power-reset-via-gpio-in-h5_btrt.patch" "applying"

	fi
}

driver_rtl8723DS() {
	# Wireless drivers for Realtek 8723DS chipsets

	if linux-version compare "${version}" ge 5.0; then

		# attach to specifics tag or branch
		local rtl8723dsver="branch:master"

		display_alert "Adding" "Wireless drivers for Realtek 8723DS chipsets ${rtl8723dsver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/lwfinger/rtl8723ds" "rtl8723ds" "${rtl8723dsver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8723ds"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8723ds/"
		cp -R "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}"/{core,hal,include,os_dep,platform} \
			"$kerneldir/drivers/net/wireless/rtl8723ds"

		# Makefile
		cp "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl8723ds/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl8723ds/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8723ds/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8723DS) += rtl8723ds/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8723ds\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8723ds-Fix-p2p-go-advertising.patch" "applying"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723ds-Fix-VFS-import.patch" "applying"
	fi
}

driver_rtl8723DU() {

	# Wireless drivers for Realtek 8723DU chipsets

	if linux-version compare "${version}" ge 5.0; then

		local rtl8723duver="branch:master"

		display_alert "Adding" "Wireless drivers for Realtek 8723DU chipsets ${rtl8723duver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/lwfinger/rtl8723du" "rtl8723du" "${rtl8723duver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8723du"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8723du/"
		cp -R "${SRC}/cache/sources/rtl8723du/${rtl8723duver#*:}"/{core,hal,include,os_dep,platform} \
			"$kerneldir/drivers/net/wireless/rtl8723du"

		# Makefile
		cp "${SRC}/cache/sources/rtl8723du/${rtl8723duver#*:}"/Makefile \
			"$kerneldir/drivers/net/wireless/rtl8723du/Makefile"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/rtl8723du/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8723DU) += rtl8723du/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8723du\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8723du-5.19.2.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723du-Fix-uninitialized-cfg80211-chan-def.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723du-Fix-p2p-go-advertising.patch" "applying"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723du-Fix-VFS-import.patch" "applying"

		# fix compilation for kernels >=  6.3
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723du-6.3.patch" "applying"

	fi
}

driver_rtl8822BS() {
	# Wireless drivers for Realtek 8822BS chipsets

	if linux-version compare "${version}" ge 4.4 && linux-version compare "${version}" le 5.16; then

		# attach to specifics tag or branch
		display_alert "Adding" "Wireless drivers for Realtek 8822BS chipsets ${rtl8822bsver}" "info"

		local rtl8822bsver="branch:local_rtl8822bs"
		fetch_from_repo "$GITHUB_SOURCE/150balbes/wifi" "rtl8822bs" "${rtl8822bsver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8822bs"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8822bs/"
		cp -R "${SRC}/cache/sources/rtl8822bs/${rtl8822bsver#*:}"/{core,hal,include,os_dep,platform,bluetooth,getAP,rtl8822b.mk} \
			"$kerneldir/drivers/net/wireless/rtl8822bs"

		# Remove some leftover binary files that shouldn't be there. firmware?
		rm -fv "$kerneldir/drivers/net/wireless/rtl8822bs/bluetooth/rtl8822b_config.bin" "$kerneldir/drivers/net/wireless/rtl8822bs/bluetooth/rtl8822b_fw.bin"

		# Makefile
		cp "${SRC}/cache/sources/rtl8822bs/${rtl8822bsver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/rtl8822bs/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8822bs/${rtl8822bsver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8822bs/${rtl8822bsver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/rtl8822bs/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8822BS) += rtl8822bs/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8822bs\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8822bs-Fix-uninitialized-cfg80211-chan-def.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8822bs-Fix-p2p-go-advertising.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8822bs-Fix-misleading-indentation.patch" "applying"

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl8822bs-Fix-VFS-import.patch" "applying"
	fi

}

driver_uwe5622_allwinner() {
	# Unisoc uwe5622 wireless Support
	if linux-version compare "${version}" ge 5.15 && linux-version compare "${version}" le 6.5 && [[ "$LINUXFAMILY" == sunxi* || "$LINUXFAMILY" == rockchip64 ]]; then
		display_alert "Adding" "Drivers for Unisoc uwe5622 found on some Allwinner and Rockchip boards" "info"

		if linux-version compare "${version}" ge 6.3; then
			process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-allwinner-v6.3.patch" "applying"
			process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-allwinner-bugfix-v6.3.patch" "applying"
			process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-allwinner-v6.3-compilation-fix.patch" "applying"
		else
			process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-allwinner.patch" "applying"
			process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-allwinner-bugfix.patch" "applying"
		fi

		if linux-version compare "${version}" ge 6.4; then
			process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-v6.4-post.patch" "applying"
		fi

		process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-warnings.patch" "applying"

		# Add to section Makefile
		echo "obj-\$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/" >> "$kerneldir/drivers/net/wireless/Makefile"

		# Don't add this to legacy (<5.0) kernels.
		if linux-version compare "${version}" ge 5.0 && linux-version compare "${version}" lt 6.1; then
			process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-park-link-pre-v6.1.patch" "applying"
		fi

		if linux-version compare "${version}" ge 6.1; then
			if linux-version compare "${version}" ge 6.2 && linux-version compare "${version}" lt 6.3; then # only for 6.2.y
				process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-park-link-v6.2-only.patch" "applying"
			else # assume 6.1.y y > 30
				process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-park-link-v6.1-post.patch" "applying"
			fi
			process_patch_file "${SRC}/patch/misc/wireless-driver-for-uwe5622-v6.1.patch" "applying"
		fi
	fi
}

driver_rtl8723cs() {
	# Realtek rtl8723cs wireless support.
	# Driver has been borrowed from sunxi 6.1 megous patch archive.
	# Applies only from linux 6.1 onwards, so older kernel archives does not require to be altered

	# It was disabled from d1/bcm2711 as that kernel is not fully in sync with mainline and as its probably not needed there anyway
	if [[ "$LINUXFAMILY" == bcm2711 || "$LINUXFAMILY" == d1 ]]; then
		return 0
	fi

	if linux-version compare "${version}" ge 6.1; then
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Add-a-new-driver-v5.12.2-7-g2de5ec386.20201013_beta.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Make-the-driver-compile-and-probe-drop-rockchip-platform.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Enable-OOB-interrupt.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Load-the-MAC-address-from-local-mac-address.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Modify-makefile-options-to-better-suit-PinePhone-Allwinn.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Enable-monitor-mode.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Disable-power-saving.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-aes_encrypt-aes_encrypt_128-to-avoid-symbol-name-conflic.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Enable-wifi-power-saving-mode.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Enable-TDLS-802.11z-support-direct-sta-sta-connection.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Disable-CONFIG_CONCURRENT_MODE.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Set-CONFIG_RTW_SDIO_PM_KEEP_POWER-n-to-fix-suspend-38.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Resume-wifi-in-a-workqueue.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-5.11.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Enable-WoWLAN.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-5.12.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Fix-misleading-indentation.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Disable-use-of-NAPI.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Fix-indentation.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Fix-compile-warnings.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-5.15.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Clear-wowlan_last_wake_reason-prior-to-suspend.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Forward-port-to-5.17.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-5.18.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Fix-some-compilation-warnings.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Adapt-to-API-changes-in-stable-5.19.2-and-6.0.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-6.0.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-6.1.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-6.1-rc1.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/dt-bindings-net-bluetooth-Add-rtl8723bs-bluetooth.patch" "applying"

		if linux-version compare "${version}" ge 6.2 && linux-version compare "${version}" lt 6.3; then # landed in 6.1.30/6.3.4 # keep for 6.2
			process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/bluetooth-btrtl-quirk-local-ext-features.patch" "applying"
			process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/Bluetooth-btrtl-add-support-for-the-RTL8723CS.patch" "applying"
		fi

		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/Bluetooth-hci_h5-Add-support-for-binding-RTL8723CS-with-device-.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/bluetooth-h5-Don-t-re-initialize-rtl8723cs-on-resume.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/bluetooth-btrtl-add-rtl8703bs.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Fix-symbol-conflicts-with-rtw88-driver.patch" "applying"
	fi

	if linux-version compare "${version}" ge 6.3; then
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-6.3.patch" "applying"
	fi

	if linux-version compare "${version}" ge 6.5; then
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-6.5.patch" "applying"
	fi

}
