# 1GB RAM 8GB eMMC 2.5G PHY USB3
BOARD_NAME="GL-MT2500"
BOARD_VENDOR="GL.iNet"
BOARDFAMILY="filogic"
BOARD_MAINTAINER="JiaY-shi"
INTRODUCED="2022"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"
BOOT_SOC="mt7981"
BOOTCONFIG="mt7981_glinet_gl-mt2500_defconfig"
BOOT_FDT_FILE="mediatek/mt7981b-glinet-gl-mt2500-v1.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 rootwait cgroup_enable cgroup_memory=1 init=/sbin/init"
HAS_VIDEO_OUTPUT="no"

function post_family_tweaks_bsp__gl_mt2500_usb_modules_in_initrd() {
	display_alert "Adding to bsp-cli" "${BOARD}: USB rootfs modules in initrd" "info"
	add_file_from_stdin_to_bsp_destination "/etc/initramfs-tools/modules" <<- 'EXTRA_MODULES'
		xhci-mtk-hcd
		xhci-hcd
		usb-storage
		uas
		sd_mod
	EXTRA_MODULES
}
