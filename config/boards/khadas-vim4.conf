# Amlogic A311D2 8GB
BOARD_NAME="Khadas VIM4"
BOARDFAMILY="meson-s4t7"
KERNEL_TARGET="legacy"
BOARD_MAINTAINER="adeepn rpardini viraniac"
SERIALCON="ttyS0" # for vendor kernel
# BOOT_FDT_FILE="amlogic/kvim4.dtb" # not set on purpose; u-boot auto-selects kvim4.dtb or kvim4n.dtb for "new VIM4"

# build uboot from source
BOOTCONFIG="kvim4_defconfig"
KHADAS_BOARD_ID="kvim4" # used to compile the fip blobs

declare -g KHADAS_OOWOW_BOARD_ID="VIM4" # for use with EXT=output-image-oowow

OVERLAY_PREFIX='t7-a311d2'

function post_family_tweaks_bsp__enable_fan_service() {
	if [[ ${BRANCH} = "legacy" ]]; then
		run_host_command_logged mkdir -p "${destination}"/etc/systemd/system/mutli-user.target.wants
		run_host_command_logged ln -sf /etc/systemd/system/fan.service "${destination}"/etc/systemd/system/mutli-user.target.wants/fan.service
	fi
}

function post_family_tweaks_bsp__use_correct_bluetooth_firmware() {
	# We already had a BCM4362A2.hcd file, but that was not compatible with vim4.
	# Hence added vim4 compatible file in armbian/firmare and adding symlink to
	# make sure that is used on vim4
	run_host_command_logged mkdir -p "${destination}"/etc/firmware/brcm
	run_host_command_logged ln -sf /lib/firmware/brcm/BCM4362A2-khadas-vim4.hcd "${destination}"/etc/firmware/brcm/BCM4362A2.hcd
}

function vim4_bsp_legacy_postinst_link_video_firmware() {
	ln -sf video_ucode.bin.t7 /lib/firmware/video/video_ucode.bin
}

function post_family_tweaks_bsp__vim4_link_video_firmware_on_install() {
	postinst_functions+=(vim4_bsp_legacy_postinst_link_video_firmware)
}
