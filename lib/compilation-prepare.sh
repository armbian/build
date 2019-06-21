# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# compilation_prepare

compilation_prepare()
{
 
	# AUFS - advanced multi layered unification filesystem for Kernel 5.1.y
	#
	# Older versions have AUFS support with a patch

	if linux-version compare $version ge 5.1 && linux-version compare $version le 5.2 && [ "$AUFS" == yes ]; then

		# attach to specifics tag or branch
		local aufsver="branch:aufs5.1"

		display_alert "Adding" "AUFS 5.1" "info"

		fetch_from_repo "https://github.com/sfjro/aufs5-standalone" "aufs5" "branch:${aufsver}" "yes"
		cd ${SRC}/cache/sources/${LINUXSOURCEDIR}
		process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-kbuild.patch"		"applying"
		process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-base.patch"			"applying"
		process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-mmap.patch"			"applying"
		process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-standalone.patch"	"applying"		
		cp -R ${SRC}/cache/sources/aufs5/${aufsver#*:}/{Documentation,fs} .
		cp ${SRC}/cache/sources/aufs5/${aufsver#*:}/include/uapi/linux/aufs_type.h include/uapi/linux/

	fi




	# WireGuard - fast, modern, secure VPN tunnel

	if linux-version compare $version ge 3.10 && [ "${WIREGUARD}" == yes ]; then

		# attach to specifics tag or branch
		# local wirever="tag:0.0.20190406" # last known working

		local wirever="branch:master"
		display_alert "Adding" "WireGuard ${wirever} " "info"

		fetch_from_repo "https://git.zx2c4.com/WireGuard" "wireguard" "${wirever}" "yes"
		cd ${SRC}/cache/sources/${LINUXSOURCEDIR}
		rm -rf ${SRC}/cache/sources/${LINUXSOURCEDIR}/net/wireguard
		cp -R ${SRC}/cache/sources/wireguard/${wirever#*:}/src/ ${SRC}/cache/sources/${LINUXSOURCEDIR}/net/wireguard
		sed -i "/^obj-\\\$(CONFIG_NETFILTER).*+=/a obj-\$(CONFIG_WIREGUARD) += wireguard/" \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/net/Makefile
		sed -i "/^if INET\$/a source \"net/wireguard/Kconfig\"" \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/net/Kconfig
		# remove duplicates
		[[ $(cat ${SRC}/cache/sources/${LINUXSOURCEDIR}/net/Makefile | grep wireguard | wc -l) -gt 1 ]] && \
		sed -i '0,/wireguard/{/wireguard/d;}' ${SRC}/cache/sources/${LINUXSOURCEDIR}/net/Makefile
		[[ $(cat ${SRC}/cache/sources/${LINUXSOURCEDIR}/net/Kconfig | grep wireguard | wc -l) -gt 1 ]] && \
		sed -i '0,/wireguard/{/wireguard/d;}' ${SRC}/cache/sources/${LINUXSOURCEDIR}/net/Kconfig
		# headers workaround
		display_alert "Patching WireGuard" "Applying workaround for headers compilation" "info"
		sed -i '/mkdir -p "$destdir"/a mkdir -p "$destdir"/net/wireguard; \
		touch "$destdir"/net/wireguard/{Kconfig,Makefile} # workaround for Wireguard' \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/scripts/package/builddeb

	fi




	# Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets

	if linux-version compare $version ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8812auver="branch:v5.2.20"

		display_alert "Adding" "Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets ${rtl8812auver}" "info"

		fetch_from_repo "https://github.com/aircrack-ng/rtl8812au" "rtl8812au" "${rtl8812auver}" "yes"
		cd ${SRC}/cache/sources/${LINUXSOURCEDIR}
		rm -rf ${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8812au
		mkdir -p ${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8812au/
		cp -R ${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}/{core,hal,include,os_dep,platform} \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8812au

		# Makefile
		cp ${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}/Makefile \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8812au/Makefile
		cp ${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}/Kconfig \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8812au/Kconfig

		# Adjust path
		sed -i 's/include $(src)\/hal\/phydm\/phydm.mk/include $(TopDIR)\/drivers\/net\/wireless\/rtl8812au\/hal\/phydm\/phydm.mk/' \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8812au/Makefile
		sed -i 's/include $(TopDIR)\/hal\/phydm\/phydm.mk/include $(TopDIR)\/drivers\/net\/wireless\/rtl8812au\/hal\/phydm\/phydm.mk/' \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8812au/Makefile

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8812AU) += rtl8812au/" >> $SRC/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/Makefile
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8812au\/Kconfig"' \
		$SRC/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/Kconfig

	fi




	# Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets

	if linux-version compare $version ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8811euver="branch:v5.3.9"

		display_alert "Adding" "Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets ${rtl8811euver}" "info"

		fetch_from_repo "https://github.com/aircrack-ng/rtl8188eus" "rtl8188eu" "${rtl8811euver}" "yes"
		cd ${SRC}/cache/sources/${LINUXSOURCEDIR}
		rm -rf ${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8188eu
		mkdir -p ${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8188eu/
		cp -R ${SRC}/cache/sources/rtl8188eu/${rtl8811euver#*:}/{core,hal,include,os_dep,platform} \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8188eu

		# Makefile
		cp ${SRC}/cache/sources/rtl8188eu/${rtl8811euver#*:}/Makefile \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8188eu/Makefile
		cp ${SRC}/cache/sources/rtl8188eu/${rtl8811euver#*:}/Kconfig \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl8188eu/Kconfig

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8188EU) += rtl8188eu/" >> $SRC/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/Makefile
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8188eu\/Kconfig"' \
		$SRC/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/Kconfig

	fi




	# Wireless drivers for Realtek 88x2bu chipsets

	if linux-version compare $version ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl88x2buver="branch:master"

		display_alert "Adding" "Wireless drivers for Realtek 88x2bu chipsets ${rtl88x2buver}" "info"

		fetch_from_repo "https://github.com/cilynx/rtl88x2BU_WiFi_linux_v5.3.1_27678.20180430_COEX20180427-5959" "rtl88x2bu" "${rtl88x2buver}" "yes"
		cd ${SRC}/cache/sources/${LINUXSOURCEDIR}
		rm -rf ${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl88x2bu
		mkdir -p ${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl88x2bu/
		cp -R ${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/{core,hal,include,os_dep,platform,rtl8822b.mk} \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl88x2bu

		# Makefile
		cp ${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Makefile \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl88x2bu/Makefile
		cp ${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Kconfig \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl88x2bu/Kconfig

		# Adjust path
		sed -i 's/include $(src)\/rtl8822b.mk /include $(TopDIR)\/drivers\/net\/wireless\/rtl88x2bu\/rtl8822b.mk/' \
		${SRC}/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/rtl88x2bu/Makefile

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8822BU) += rtl88x2bu/" >> $SRC/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/Makefile
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl88x2bu\/Kconfig"' \
		$SRC/cache/sources/${LINUXSOURCEDIR}/drivers/net/wireless/Kconfig

	fi

}
