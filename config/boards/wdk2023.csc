# Qualcomm Snapdragon 8cx Gen 3 Adreno 690 Qualcomm WCN6855 Wi-Fi 6E Bluetooth 5.1
declare -g BOARD_NAME="Windows Dev Kit 2023"
declare -g BOARDFAMILY="uefi-arm64"
declare -g BOARD_MAINTAINER=""
declare -g KERNEL_TARGET="wdk2023"
declare -g BRANCH="wdk2023"

declare -g BOOT_LOGO=desktop

# This board boots via EFI/Grub, but requires a DTB to be passed, from Grub, to the Kernel.
declare -g GRUB_CMDLINE_LINUX_DEFAULT="efi=noruntime clk_ignore_unused pd_ignore_unused arm64.nopauth iommu.passthrough=0 iommu.strict=0 pcie_aspm.policy=powersupersave"
declare -g BOOT_FDT_FILE="qcom/sc8280xp-microsoft-dev-kit-2023.dtb"
enable_extension "grub-with-dtb" # important, puts the whole DTB handling in place.

# Use the full firmware, complete linux-firmware plus Armbian's
# @TODO: see if we can only get the blobs that are required for WDK operation.
declare -g BOARD_FIRMWARE_INSTALL="-full"

function post_family_config_branch_wdk2023__jg_kernel() {
	declare -g KERNEL_MAJOR_MINOR="6.7" # Major and minor versions of this kernel.
	declare -g KERNELBRANCH='branch:jg/wdk2023-gunyah-6.7-rc6'
	declare -g KERNELSOURCE='https://github.com/jglathe/linux_ms_dev_kit.git'
	declare -g LINUXCONFIG='linux-arm64-wdk2023'
	display_alert "Set up jg's kernel ${KERNELBRANCH} for" "${BOARD}" "info"
}

function wdk2023_is_userspace_supported() {
	[[ "${RELEASE}" == "trixie" || "${RELEASE}" == "sid" || "${RELEASE}" == "mantic" ]] && return 0
	return 1
}

# https://wiki.debian.org/InstallingDebianOn/Thinkpad/X13s
function post_family_config__debian_now_has_userspace_for_the_wdk2023() {
	if ! wdk2023_is_userspace_supported; then
		if [[ "${RELEASE}" != "" ]]; then
			display_alert "Missing userspace for ${BOARD}" "${RELEASE} does not have the userspace necessary to support the ${BOARD}" "warn"
		fi
		return 0
	fi

	display_alert "Setting up extra Debian packages for ${BOARD}" "${RELEASE}///${BOARD}" "info"
	add_packages_to_image "bluez" "bluetooth"        # for bluetooth stuff
	add_packages_to_image "protection-domain-mapper" # for charging; see https://packages.ubuntu.com/protection-domain-mapper and https://packages.debian.org/protection-domain-mapper
	add_packages_to_image "qrtr-tools"               # for charging; see https://packages.ubuntu.com/qrtr-tools and https://packages.debian.org/qrtr-tools
	add_packages_to_image "alsa-ucm-conf"            # for audio; see https://packages.ubuntu.com/alsa-ucm-conf and https://packages.debian.org/alsa-ucm-conf - we need 1.2.10 + patches, see below
	add_packages_to_image "acpi"                     # general ACPI support
	add_packages_to_image "zstd"                     # for zstd compression of initrd
	add_packages_to_image "mtools"                   # for access to the EFI partition

	# Trixie, as of 2023-10-13, is missing fprintd and libpam-fprintd; see https://tracker.debian.org/pkg/fprintd and https://tracker.debian.org/pkg/libpam-fprintd
	# @TODO: check again later, and remove this if it's there
	if [[ "${RELEASE}" != "trixie" ]]; then
		add_packages_to_image "fprintd"        # for fingerprint reader; see https://packages.ubuntu.com/fprintd and https://packages.debian.org/fprintd
		add_packages_to_image "libpam-fprintd" # for fingerprint reader PAM support; see https://packages.ubuntu.com/libpam-fprintd and https://packages.debian.org/libpam-fprintd
	fi

	# Also needed, not listed here:
	# - mesa > 23.1.5; see https://packages.ubuntu.com/mesa-vulkan-drivers and https://packages.debian.org/mesa-vulkan-drivers
}

function post_family_tweaks_bsp__wdk2023_bsp_bluetooth_addr() {
	### The bluetooth does not have a public MAC address set in DT, and BT won't start without one.
	### Use a systemd override to hook up setting a public-addr before starting bluetoothd
	declare random_mac_address="" # would be much better to rnd mac on board-side though
	random_mac_address=$(printf '02:%02X:%02X:%02X:%02X:%02X' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256)))
	display_alert "Adding systemd override for bluetooth public address init" "${BOARD} :: bt mac ${random_mac_address}" "info"

	add_file_from_stdin_to_bsp_destination "/etc/systemd/system/bluetooth.service.d/override.conf" <<- EOD
		[Service]
		ExecStartPre=/bin/bash -c 'sleep 5 && yes | btmgmt public-addr ${random_mac_address}'
	EOD
}

function post_family_tweaks_bsp__wdk2023_bsp_always_start_pdmapper() {
	### (At least) Ubuntu's version of protection-domain-mapper's pd-mapper.service has a kernel condition.
	### On Debian, this does not hurt.
	### Remove it using a systemd override.
	add_file_from_stdin_to_bsp_destination "/etc/systemd/system/pd-mapper.service.d/override.conf" <<- EOD
		[Unit]
		Description=Qualcomm PD mapper service (always starts)
		ConditionKernelVersion=
	EOD
}

function post_family_tweaks_bsp__wdk2023_bsp_always_start_qrtr_ns() {
	### (At least) Ubuntu's version of qrtr-ns's qrtr-ns.service has a kernel condition.
	### On Debian, this does not hurt.
	### Remove it using a systemd override.
	add_file_from_stdin_to_bsp_destination "/etc/systemd/system/qrtr-ns.service.d/override.conf" <<- EOD
		[Unit]
		Description=QIPCRTR Name Service (always starts)
		ConditionKernelVersion=
	EOD
}

##
## Include certain firmware in the initrd
##
function post_family_tweaks_bsp__wdk2023_bsp_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: firmware in initrd" "info"
	declare file_added_to_bsp_destination # will be filled in by add_file_from_stdin_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/wdk2023-firmware" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		for f in /lib/firmware/qcom/sc8280xp/MICROSOFT/DEVKIT23/* ; do
			add_firmware "${f#/lib/firmware/}"
		done
		add_firmware "qcom/a660_sqe.fw" # extra one for dpu
		add_firmware "qcom/a660_gmu.bin" # extra one for gpu
		add_firmware "qcom/a690_gmu.bin" # extra one for gpu (is a symlink)
	FIRMWARE_HOOK
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}

## Modules, required to boot, add them to initrd; might need to be done in '.d/x13s-modules' instead
function post_family_tweaks_bsp__wdk2023_bsp_modules_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: modules in initrd" "info"
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/modules" <<- 'EXTRA_MODULES'
		# @TODO this list is outdated, much has changed; check jhovold's defconfig commit msg
		phy_qcom_qmp_pcie
		pcie_qcom
		phy_qcom
		qmp_pcie
		phy_qcom_qmp_combo
		qrtr
		phy_qcom_edp
		gpio_sbu_mux
		i2c_hid_of
		i2c_qcom_geni
		pmic_glink_altmode
		leds_qcom_lpg
		qcom_q6v5_pas  # This module loads a lot of FW blobs
		msm
		nvme
		usb_storage
		uas
	EXTRA_MODULES

}

# armbian-firstrun waits for systemd to be ready, but snapd.seeded might cause it to hang due to wrong clock.
# if the battery runs out, the clock is reset to 1970. This causes snapd.seeded to hang, and armbian-firstrun to hang.
function pre_customize_image__disable_snapd_seeded() {
	[[ "${DISTRIBUTION}" != "Ubuntu" ]] && return 0 # only needed for Ubuntu
	display_alert "Disabling snapd.seeded" "${BOARD}" "info"
	chroot_sdcard systemctl disable snapd.seeded.service "||" true
}
