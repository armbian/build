#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2024 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

###  _                            _              _
### (_)_ __ ___  _ __   ___  _ __| |_ __ _ _ __ | |_
### | | '_ ` _ \| '_ \ / _ \| '__| __/ _` | '_ \| __|
### | | | | | | | |_) | (_) | |  | || (_| | | | | |_
### |_|_| |_| |_| .__/ \___/|_|   \__\__,_|_| |_|\__|
###             |_|
###
### do NOT, I repeat, do NOT use "branch:xxx" in fetch_from_repo() calls in this file.
### this whole file is hashed to produce drivers hash for the kernel versioning.
### if you use a mutable branch reference, any changes in the upstream will not be detected,
### and your changes will possibly be ignored.
### please use "commit:<sha1>" or "tag:<immutable_tagname>" instead, and note the original branch name
###
### Also important: do NOT, I repeat, do NOT apply any patches that are not in "patch/misc" directory or subdirs.
### Only 'patch/misc' is hashed to produce drivers hash for the kernel versioning, and using patches that don't
### reside there will also lead to problems.

function driver_generic_bring_back_ipx() {
	#
	# Returning headers needed for some wireless drivers
	#
	if linux-version compare "${version}" ge 5.4; then
		display_alert "Reverting upstream-removed" "IPX stuff needed for Wireless Drivers" "info"
		process_patch_file "${SRC}/patch/misc/wireless-bring-back-headers.patch" "applying"
	fi
}

driver_rtl8189ES() {

	# Wireless drivers for Realtek 8189ES chipsets

	if linux-version compare "${version}" ge 3.14; then

		# Attach to specific commit (was "branch:master")
		local rtl8189esver='commit:30a52f789a0b933c4a7eb06cbf4a4d21c8e581aa' # Commit date: May 19, 2024 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 8189ES chipsets ${rtl8189esver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/jwrdegoede/rtl8189ES_linux" "rtl8189es" "${rtl8189esver}" "yes" # https://github.com/jwrdegoede/rtl8189ES_linux
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

		# Attach to specific commit (was "branch:rtl8189fs")
		local rtl8189fsver='commit:9a82349c2c40515f9d20b9f6721670f76b4e1c7a' # Commit date: May 19, 2024 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 8189FS chipsets ${rtl8189fsver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/jwrdegoede/rtl8189ES_linux" "rtl8189fs" "${rtl8189fsver}" "yes" # https://github.com/jwrdegoede/rtl8189ES_linux
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

		# fix compilation for kernels >= 5.4
		process_patch_file "${SRC}/patch/misc/wireless-rtl8189fs-Fix-VFS-import.patch" "applying"

		# fix compilation for kernels >= 5.4.251
		process_patch_file "${SRC}/patch/misc/wireless-rtl8189fs-Fix-building-on-5.4.251-kernel.patch" "applying"
	fi
}

driver_rtl8192EU() {

	# Wireless drivers for Realtek 8192EU chipsets

	if linux-version compare "${version}" ge 3.14; then

		# Attach to specific commit (was "branch:realtek-4.4.x")
		local rtl8192euver='commit:a5ac6789a78a4f5ca0bf157a0f62385ea034cb9c' # Commit date: May 18, 2024 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 8192EU chipsets ${rtl8192euver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/Mange/rtl8192eu-linux-driver" "rtl8192eu" "${rtl8192euver}" "yes" # https://github.com/Mange/rtl8192eu-linux-driver
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

		# Attach to specific commit (is branch:v5.6.4.2)
		local rtl8812auver="commit:b44d288f423ede0fc7cdbf92d07a7772cd727de4" # Commit date: May 10, 2024 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets ${rtl8812auver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/aircrack-ng/rtl8812au" "rtl8812au" "${rtl8812auver}" "yes" # https://github.com/aircrack-ng/rtl8812au
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
	fi
}

driver_xradio_xr819() {

	# Wireless drivers for Xradio XR819 chipsets

	if linux-version compare "${version}" ge 4.19 && [[ "$LINUXFAMILY" == sunxi* ]]; then

		# Attach to specific commit (is branch:master)
		local xradio_xr819_ver="commit:3a1f77fb2db248b7d18d93b67b16e0d6c91db184" # Commit date: Dec 25, 2023 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Xradio XR819 chipsets" "info"

		fetch_from_repo "$GITHUB_SOURCE/fifteenhex/xradio" "xradio" "${xradio_xr819_ver}" "yes" # https://github.com/fifteenhex/xradio
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/xradio"
		mkdir -p "$kerneldir/drivers/net/wireless/xradio/"
		cp "${SRC}"/cache/sources/xradio/${xradio_xr819_ver#*:}/*.{h,c} \
			"$kerneldir/drivers/net/wireless/xradio/"

		# Makefile
		cp "${SRC}/cache/sources/xradio/${xradio_xr819_ver#*:}/Makefile" \
			"$kerneldir/drivers/net/wireless/xradio/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/xradio/${xradio_xr819_ver#*:}/Kconfig"
		cp "${SRC}/cache/sources/xradio/${xradio_xr819_ver#*:}/Kconfig" \
			"$kerneldir/drivers/net/wireless/xradio/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_XRADIO) += xradio/" \
			>> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/xradio\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/Kconfig"
	fi
}

driver_rtl8811CU_rtl8821C() {
	# Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets

	if linux-version compare "${version}" ge 3.14; then

		# Attach to specific commit (is branch:main)
		local rtl8811cuver="commit:3eacc28b721950b51b0249508cc31e6e54988a0c" # Commit date: May 3, 2024 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets ${rtl8811cuver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/morrownr/8821cu-20210916" "rtl8811cu" "${rtl8811cuver}" "yes" # https://github.com/morrownr/8821cu-20210916
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
	fi
}

driver_rtl88x2bu() {

	# Wireless drivers for Realtek 88x2bu chipsets

	if linux-version compare "${version}" ge 5.0; then

		# Attach to specific commit (is branch:main)
		local rtl88x2buver="commit:e96ef9a9e0a9261598137b3ad2c70fa018914764" # Commit date: May 11, 2024 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 88x2bu chipsets ${rtl88x2buver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/morrownr/88x2bu-20210702" "rtl88x2bu" "${rtl88x2buver}" "yes" # https://github.com/morrownr/88x2bu-20210702
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

	fi
}

driver_rtw88() {

	# Upstream wireless RTW88 drivers
	# Quite a few kernel families have KERNEL_DRIVERS_SKIP listing this driver. If so, this won't even be called.

	if linux-version compare "${version}" ge 6.1; then
		display_alert "Adding" "Upstream wireless RTW88 drivers" "info"
		if [[ -f "${SRC}/patch/misc/rtw88/${version}/001-drivers-net-wireless-realtek-rtw88-upstream-wireless.patch" ]]; then
			process_patch_file "${SRC}/patch/misc/rtw88/${version}/001-drivers-net-wireless-realtek-rtw88-upstream-wireless.patch" "applying"
		fi
		process_patch_file "${SRC}/patch/misc/rtw88/hack/002-rtw88-usb-make-work-queues-high-priority.patch" "applying"
		process_patch_file "${SRC}/patch/misc/rtw88/hack/003-rtw88-decrease-the-log-level-of-tx-report.patch" "applying"
	fi
}

driver_rtl8852bs() {

	# Wireless driver for Realtek 8852BS SDIO Wireless driver used in BananaPi F3 and Armsom Sige5

	if linux-version compare "${version}" ge 6.1 && [[ "${LINUXFAMILY}" == spacemit || "${LINUXFAMILY}" == rk35xx ]]; then

		# Attach to specific commit
		local rtl8852bs_ver='commit:b7d94226641ef4687bc7f54ae6fa01b7e30f4b82' # Commit date: July 10, 2024 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 8852BS SDIO chipset ${rtl8852bs_ver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/armbian/wifi-rtl8852bs" "rtl8852bs" "${rtl8852bs_ver}" "yes" # https://github.com/armbian/wifi-rtl8852bs
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/realtek/rtl8852bs"
		mkdir -p "$kerneldir/drivers/net/wireless/realtek/rtl8852bs/"

		# Copy folders into kernel-work-dir
		cp -R "${SRC}/cache/sources/rtl8852bs/${rtl8852bs_ver#*:}"/{core,include,os_dep,phl,platform} \
			"$kerneldir/drivers/net/wireless/realtek/rtl8852bs"

		# Copy Kconfig into kernel-work-dir
		cp "${SRC}/cache/sources/rtl8852bs/${rtl8852bs_ver#*:}"/Kconfig \
			"$kerneldir/drivers/net/wireless/realtek/rtl8852bs/Kconfig"

		# Copy Makefile into kernel-work-dir
		cp "${SRC}/cache/sources/rtl8852bs/${rtl8852bs_ver#*:}"/Makefile \
			"$kerneldir/drivers/net/wireless/realtek/rtl8852bs/Makefile"

		# Copy common.mk into kernel-work-dir
		cp "${SRC}/cache/sources/rtl8852bs/${rtl8852bs_ver#*:}"/common.mk \
			"$kerneldir/drivers/net/wireless/realtek/rtl8852bs/common.mk"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
			"$kerneldir/drivers/net/wireless/realtek/rtl8852bs/Makefile"

		# Bugfix/workaround: Comment undefined RTW_WARN_LMT
		# @TODO Check on update if this fix is still needed (added 2024-July-10)
		sed -i  "s/RTW_WARN_LMT(/\/\/RTW_WARN_LMT(/g"  \
			"$kerneldir/drivers/net/wireless/realtek/rtl8852bs/core/rtw_xmit.c"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8852BS) += rtl8852bs/" >> "$kerneldir/drivers/net/wireless/realtek/Makefile"
		sed -i '/source "drivers\/net\/wireless\/realtek\/rtw89\/Kconfig"/a source "drivers\/net\/wireless\/realtek\/rtl8852bs\/Kconfig"' \
			"$kerneldir/drivers/net/wireless/realtek/Kconfig"

		# We have to enable specific platforms in the driver Makefile to enable specific driver tweaks, they are all "n" by default
		case ${LINUXFAMILY} in
			# For Rockchip devices, add family name here
			rk35xx)
				sed -i "s/CONFIG_PLATFORM_ARM_ROCKCHIP = n/CONFIG_PLATFORM_ARM_ROCKCHIP = y/g" "$kerneldir/drivers/net/wireless/realtek/rtl8852bs/Makefile"
				;;
			# For Spacemit devices, add family name here
			spacemit)
				sed -i "s/CONFIG_PLATFORM_SPACEMIT = n/CONFIG_PLATFORM_SPACEMIT = y/g" "$kerneldir/drivers/net/wireless/realtek/rtl8852bs/Makefile"
				;;
		esac

		# Patches
		process_patch_file "${SRC}/patch/misc/wireless-rtl8852bs-Update-rtw_regd_init-for-6.1.patch" "applying"
	fi
}

driver_rtl88x2cs() {

	# Wireless drivers for Realtek 88x2cs chipsets
	# Only used for meson64 family boards, use mainline rtw88 driver for all other boards

	if linux-version compare "${version}" ge 5.9 && [[ "$LINUXFAMILY" == meson64 ]]; then

		# Attach to specific commit (track branch:tune_for_jethub)
		local rtl88x2csver='commit:40450f759c8a930d271b5f0a663685f412debc72' # Commit date: Jan 24, 2024 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 88x2cs chipsets ${rtl88x2csver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/jethome-ru/rtl88x2cs" "rtl88x2cs" "${rtl88x2csver}" "yes" # https://github.com/jethome-ru/rtl88x2cs
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

driver_uwe5622() {

	# Wireless drivers for Unisoc uwe5622 wireless

	if linux-version compare "${version}" ge 5.15 && [[ "$LINUXFAMILY" == sunxi* || "$LINUXFAMILY" == rockchip64 || "$LINUXFAMILY" == rk35xx ]]; then

		display_alert "Adding" "Drivers for Unisoc uwe5622 found on some Allwinner and Rockchip boards" "info"

		if linux-version compare "${version}" ge 6.3; then
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-allwinner-v6.3.patch" "applying"
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-allwinner-bugfix-v6.3.patch" "applying"
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-allwinner-v6.3-compilation-fix.patch" "applying"
		else
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-allwinner.patch" "applying"
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-allwinner-bugfix.patch" "applying"
		fi

		if linux-version compare "${version}" ge 6.4; then
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-v6.4-post.patch" "applying"
		fi

		process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-warnings.patch" "applying"

		# Add to section Makefile
		echo "obj-\$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/" >> "$kerneldir/drivers/net/wireless/Makefile"

		# Don't add this to legacy (<5.0) kernels.
		if linux-version compare "${version}" ge 5.0 && linux-version compare "${version}" lt 6.1; then
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-park-link-pre-v6.1.patch" "applying"
		fi

		if linux-version compare "${version}" ge 6.1; then
			if linux-version compare "${version}" ge 6.2 && linux-version compare "${version}" lt 6.3; then # only for 6.2.y
				process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-park-link-v6.2-only.patch" "applying"
			else # assume 6.1.y y > 30
				process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-park-link-v6.1-post.patch" "applying"
			fi
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-v6.1.patch" "applying"
		fi

		if linux-version compare "${version}" ge 6.6; then
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-v6.6-fix-tty-sdio.patch" "applying"
		fi

		if [[ "$LINUXFAMILY" == sunxi* ]]; then
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-fix-setting-mac-address-for-netdev.patch" "applying"
		fi

		# Apply patches that adjust the driver only for rockchip platforms
		if [[ "$LINUXFAMILY" == rockchip* ]]; then
			if linux-version compare "${version}" le 6.1; then
				process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-adjust-for-rockchip-pre-6.1.patch"
			else
				process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-adjust-for-rockchip-post-6.1.patch"
			fi
		fi

		process_patch_file "${SRC}/patch/misc/wireless-uwe5622/wireless-uwe5622-Fix-compilation-with-6.7-kernel.patch" "applying"
		process_patch_file "${SRC}/patch/misc/wireless-uwe5622/wireless-uwe5622-reduce-system-load.patch" "applying"

		if linux-version compare "${version}" ge 6.9; then
			process_patch_file "${SRC}/patch/misc/wireless-uwe5622/uwe5622-v6.9.patch" "applying"
		fi

	fi
}

driver_rtl8723cs() {

	# Wireless drivers for Realtek rtl8723cs chipsets
	# Driver has been borrowed from sunxi 6.1 megous patch archive.
	# Applies only from linux 6.1 onwards, so older kernel archives does not require to be altered

	# It was disabled from d1/bcm2711 as that kernel is not fully in sync with mainline and as its probably not needed there anyway
	if [[ "$LINUXFAMILY" == bcm2711 || "$LINUXFAMILY" == d1 ]]; then
		return 0
	fi

	if linux-version compare "${version}" ge 6.1; then

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8723CS)                += rtl8723cs/" >> "$kerneldir/drivers/staging/Makefile"

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

	if linux-version compare "${version}" ge 6.7; then
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-6.7.patch" "applying"
	fi

	if linux-version compare "${version}" ge 6.8; then
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-6.8.patch" "applying"
	fi

	if linux-version compare "${version}" ge 6.9; then
		process_patch_file "${SRC}/patch/misc/wireless-rtl8723cs/8723cs-Port-to-6.9.patch" "applying"
	fi

}

###  The vendor's RTL8723DS driver is still required for RockPI-S support because
###  the RTW88 driver for the chip configures its RF gains incorrectly
driver_rtl8723DS() {

	# Wireless drivers for Realtek 8723DS chipsets

	if linux-version compare "${version}" ge 5.0; then

		# Attach to specific commit (was "branch:master")
		local rtl8723dsver='commit:52e593e8c889b68ba58bd51cbdbcad7fe71362e4' # Commit date: Nov 14, 2023 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 8723DS chipsets ${rtl8723dsver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/lwfinger/rtl8723ds" "rtl8723ds" "${rtl8723dsver}" "yes" # https://github.com/lwfinger/rtl8723ds
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

###
###
### NOTICE: <=6.7 BELOW ONLY
###
### All drivers and patches listed below are only used in kernels <=6.7 and **not** in >=6.8
### Sorted by: "linux-version le ..." from high (newer kernel) to low (older kernel).
### It is sorted like this for better visibility.
###
### v v v v v v v v v v v v v v v v v v v v v v v

driver_rtl8723DU() {

	# Wireless drivers for Realtek 8723DU chipsets

	if linux-version compare "${version}" ge 5.0 && linux-version compare "${version}" le 6.7; then

		# Attach to specific commit (was "branch:master")
		local rtl8723duver='commit:ae03b0861351f72808405ddda80e8aab105bcfce' # Commit date: Dec 8, 2023 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 8723DU chipsets ${rtl8723duver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/lwfinger/rtl8723du" "rtl8723du" "${rtl8723duver}" "yes" # https://github.com/lwfinger/rtl8723du
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

driver_mt7921u_add_pids() {
	# Add two popular cheap USB devices to the table
	if linux-version compare "${version}" ge 6.1 && linux-version compare "${version}" lt 6.2; then
		display_alert "Mediatek MT7921u" "Add Comfast CF952A and Netgear AXE3000" "info"
		process_patch_file "${SRC}/patch/misc/wireless-mt7921u-add-pids.patch" "applying"
	fi
}

###
###
### NOTICE: <=5.x BELOW ONLY
###
### All drivers and patches listed below are only used in legacy kernels 5.x and **not** in >=6.0
### Sorted by: "linux-version lt ..." from high (newer kernel) to low (older kernel).
### It is sorted like this for better visibility.
###
### v v v v v v v v v v v v v v v v v v v v v v v

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

driver_rtl8822BS() {

	# Wireless drivers for Realtek 8822BS chipsets

	if linux-version compare "${version}" ge 4.4 && linux-version compare "${version}" le 5.16; then

		# Attach to specific commit (was "branch:local_rtl8822bs")
		local rtl8822bsver='commit:ee88babf55ad75b49c3312f997fd289e5ca4016b' # Commit date: Apr 30, 2022 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 8822BS chipsets ${rtl8822bsver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/150balbes/wifi" "rtl8822bs" "${rtl8822bsver}" "yes" # https://github.com/150balbes/wifi
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

driver_rtl8188EU_rtl8188ETV() {

	# Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets

	if linux-version compare "${version}" ge 3.14 &&
		linux-version compare "${version}" lt 5.15; then

		# Attach to specific commit (was "branch:v5.7.6.1")
		local rtl8188euver='commit:0683c3382f7ad4bb90d72b9c903a90a7bd7b200d' # Commit date: Dec 28, 2020 (please update when updating commit ref)

		display_alert "Adding" "Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets ${rtl8188euver}" "info"

		fetch_from_repo "$GITHUB_SOURCE/aircrack-ng/rtl8188eus" "rtl8188eu" "${rtl8188euver}" "yes" # https://github.com/aircrack-ng/rtl8188eus
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

driver_rtl8152_rtl8153() {
	# Updated USB network drivers for RTL8152/RTL8153 based dongles that also support 2.5Gbs variants
	if linux-version compare "${version}" ge 5.4 && linux-version compare "${version}" le 5.12 && [ "$LINUXFAMILY" != mvebu64 ] && [ "$LINUXFAMILY" != rk322x ] && [ "$LINUXFAMILY" != odroidxu4 ]; then

		# Attach to specific commit (was "branch:master")
		local rtl8152ver='commit:5a91843e032c00fd46b2c0b3cb2206685bb79420' # Commit date: Jun 29, 2021 (please update when updating commit ref)

		display_alert "Adding" "Drivers for 2.5Gb RTL8152/RTL8153 USB dongles ${rtl8152ver}" "info"
		fetch_from_repo "$GITHUB_SOURCE/igorpecovnik/realtek-r8152-linux" "rtl8152" "${rtl8152ver}" "yes" # https://github.com/igorpecovnik/realtek-r8152-linux
		cp -R "${SRC}/cache/sources/rtl8152/${rtl8152ver#*:}"/{r8152.c,compatibility.h} \
			"$kerneldir/drivers/net/usb/"
	fi
}
