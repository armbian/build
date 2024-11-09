# Amlogic S905Y4 4C 2GHz Cortex-A35 Mali-G31 MP2 2GB LPDDR4 16GB eMMC AP6256
BOARD_NAME="Khadas VIM1S" # don't confuse with VIM1 (S905X)
BOARDFAMILY="meson-s4t7"
KERNEL_TARGET="legacy"
BOARD_MAINTAINER="rpardini viraniac"
SERIALCON="ttyS0" # for vendor kernel
# BOOT_FDT_FILE="amlogic/kvim1s.dtb" # unset on purpose: uboot auto-determines the DTB to use

# build uboot from source
BOOTCONFIG="kvim1s_defconfig"
KHADAS_BOARD_ID="kvim1s" # used to compile the fip blobs

declare -g KHADAS_OOWOW_BOARD_ID="VIM1S" # for use with EXT=output-image-oowow

OVERLAY_PREFIX='s4-s905y4'
DEFAULT_OVERLAYS="panfrost"

function post_family_tweaks_bsp__populate_etc_firmware() {
	# The hciattach command needs firmware to be placed in /etc/firmware directory.
	# Populate the same.
	run_host_command_logged mkdir -p "${destination}"/etc/firmware/brcm
	run_host_command_logged ln -sf /lib/firmware/brcm/BCM4345C5.hcd "${destination}"/etc/firmware/brcm/BCM4345C5.hcd
}

function vim1s_bsp_legacy_postinst_link_video_firmware() {
	ln -sf video_ucode.bin.s4 /lib/firmware/video/video_ucode.bin
}

function post_family_tweaks_bsp__vim1s_link_video_firmware_on_install() {
	postinst_functions+=(vim1s_bsp_legacy_postinst_link_video_firmware)
}
