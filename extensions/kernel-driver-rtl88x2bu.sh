function fetch_sources_for_kernel_driver__realtek_wifi_rtl882x2bu() {
	declare -g rtl88x2buver="branch:5.8.7.1_35809.20191129_COEX20191120-7777"
	fetch_from_repo "https://github.com/cilynx/rtl88x2bu" "rtl88x2bu" "${rtl88x2buver}" "yes"
}

function custom_kernel_config__realtek_wifi_rtl882x2bu() {
	display_alert "Adding kernel config" "CONFIG_RTL8822BU=m" "warn"
	# enable RTL8822BU in .config
	run_host_command_logged ./scripts/config --module CONFIG_RTL8822BU
}

function patch_kernel_for_driver__realtek_wifi_rtl882x2bu() {
	display_alert "Patching Kernel for Driver" "Realtek WiFi RTL882x2bu: ${version} in ${kernel_work_dir}" "info"

	if ! linux-version compare "${version}" ge 5.0; then
		display_alert "Kernel version too old: ${version} -- requires 5.0+" "Skipping ${EXTENSION}" "warn"
		return 0
	fi

	display_alert "Adding" "Wireless drivers for Realtek 88x2bu chipsets ${rtl88x2buver}" "info"

	run_host_command_logged rm -rf "${kernel_work_dir}/drivers/net/wireless/rtl88x2bu"
	run_host_command_logged mkdir -pv "${kernel_work_dir}/drivers/net/wireless/rtl88x2bu/"
	run_host_command_logged cp -Rp "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}"/{core,hal,include,os_dep,platform,halmac.mk,rtl8822b.mk} "${kernel_work_dir}/drivers/net/wireless/rtl88x2bu"

	# Makefile
	run_host_command_logged cp -pv "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Makefile" "${kernel_work_dir}/drivers/net/wireless/rtl88x2bu/Makefile"

	# Kconfig
	sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Kconfig"
	run_host_command_logged cp -pv "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Kconfig" "${kernel_work_dir}/drivers/net/wireless/rtl88x2bu/Kconfig"

	# Adjust path
	sed -i 's/include $(src)\/rtl8822b.mk /include $(TopDIR)\/drivers\/net\/wireless\/rtl88x2bu\/rtl8822b.mk/' "${kernel_work_dir}/drivers/net/wireless/rtl88x2bu/Makefile"

	# Add to section Makefile
	echo "obj-\$(CONFIG_RTL8822BU) += rtl88x2bu/" >> "${kernel_work_dir}/drivers/net/wireless/Makefile"
	sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl88x2bu\/Kconfig"' "${kernel_work_dir}/drivers/net/wireless/Kconfig"

	display_alert "Done patching kernel ${version} for" "${EXTENSION}" "info"
}

