# Rockchip RK3588j Octa core 4GB-32GB eMMC GBE HDMI HDMI-IN PCIe SATA USB3 WiFi 4G 5G
BOARD_NAME="Firefly ITX-3588J"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
KERNEL_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588-firefly-itx-3588j.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS02,1500000 console=tty0"
BOOT_SOC="rk3588"
IMAGE_PARTITION_TABLE="gpt"

function post_family_config__firefly-itx-3588j_use_vendor_uboot() {
	BOOTCONFIG="rk3588_defconfig"
	BOOTSOURCE='https://github.com/150balbes/u-boot-rk'
	BOOTBRANCH='branch:rk3588'
	BOOTDIR="u-boot-${BOARD}"
	BOOTPATCHDIR="u-boot-firefly-itx-3588j"
}
