# 1GB RAM 8GB eMMC 2.5G PHY USB3
BOARD_NAME="GL-MT2500 v2"
BOARD_VENDOR="GL.iNet"
BOARDFAMILY="filogic"
BOARD_MAINTAINER="JiaY-shi"
INTRODUCED="2022"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"
BOOT_SOC="mt7981"
BOOTCONFIG="mt7981_glinet_gl-mt2500_defconfig"
BOOT_FDT_FILE="mediatek/mt7981b-glinet-gl-mt2500-v2.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 rootwait rootdelay=10 cgroup_enable cgroup_memory=1 init=/sbin/init"
HAS_VIDEO_OUTPUT="no"

function post_family_tweaks_bsp__gl_mt2500_v2_airoha_firmware() {
	display_alert "Adding to bsp-cli" "${BOARD}: Airoha EN8811H firmware" "info"
	local firmware_commit="458e40fdbb4dad5134ec230a42df21aea1b5baf8"
	local firmware_base_url="https://gitlab.com/api/v4/projects/48890189/repository/files"
	local firmware_destination="${destination}/lib/firmware/airoha"
	local license_destination="${destination}/usr/share/doc/armbian-bsp-cli-gl-mt2500-v2"
	local -a firmware_names=("EthMD32.dm.bin" "EthMD32.DSP.bin")
	local -a firmware_sha256=(
		"874982b88330112c376e484cdce114cf2e1476ccbb901c87f80882f127ffb90f"
		"3e4699ec709c836d5fce7c91bc5d205beb54aea326c4b70c7050b355784cbebd"
	)
	local index firmware_file

	run_host_command_logged mkdir -pv "${firmware_destination}" "${license_destination}"
	for index in "${!firmware_names[@]}"; do
		firmware_file="${firmware_destination}/${firmware_names[index]}"
		run_host_command_logged curl -fLo "${firmware_file}" --retry 5 --retry-all-errors \
			--retry-delay 2 --connect-timeout 30 --max-time 300 \
			"${firmware_base_url}/airoha%2F${firmware_names[index]}/raw?ref=${firmware_commit}"
		echo "${firmware_sha256[index]}  ${firmware_file}" | sha256sum -c - || \
			exit_with_error "Checksum validation failed for ${firmware_names[index]}"
	done

	local license_file="${license_destination}/LICENSE.airoha"
	run_host_command_logged curl -fLo "${license_file}" --retry 5 --retry-all-errors \
		--retry-delay 2 --connect-timeout 30 --max-time 300 \
		"${firmware_base_url}/LICENSES%2FLICENSE.airoha/raw?ref=${firmware_commit}"
	echo "ad548ca0ffb91ec655de0f28e13089ef1cd4e0deabb2f15a9289194990e62252  ${license_file}" | \
		sha256sum -c - || exit_with_error "Checksum validation failed for LICENSE.airoha"
}

function post_family_tweaks_bsp__gl_mt2500_v2_airoha_firmware_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: Airoha EN8811H firmware in initrd" "info"
	declare file_added_to_bsp_destination
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/hooks/gl-mt2500-v2-firmware" <<- 'FIRMWARE_HOOK'
		#!/bin/bash
		[[ "$1" == "prereqs" ]] && exit 0
		. /usr/share/initramfs-tools/hook-functions
		add_firmware "airoha/EthMD32.dm.bin"
		add_firmware "airoha/EthMD32.DSP.bin"
	FIRMWARE_HOOK
	run_host_command_logged chmod -v +x "${file_added_to_bsp_destination}"
}

function post_family_tweaks_bsp__gl_mt2500_v2_usb_modules_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: USB rootfs modules in initrd" "info"
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/modules" <<- 'EXTRA_MODULES'
		xhci-mtk-hcd
		xhci-hcd
		usb-storage
		uas
		sd_mod
	EXTRA_MODULES
}
