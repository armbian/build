# Rockchip RK3588S octa core 4/8/16GB RAM SoC NVMe USB3 USB-C GbE
BOARD_NAME="Indiedroid Nova"
BOARDFAMILY="rockchip-rk3588-indiedroid"
BOOTCONFIG="indiedroid_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="legacy"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-9tripod-linux.dtb"
BOOT_SCENARIO="spl-blobs"
WIREGUARD="no"
BOOT_SUPPORT_SPI="yes"
IMAGE_PARTITION_TABLE="gpt"
SKIP_BOOTSPLASH="yes" # Skip boot splash patch, conflicts with CONFIG_VT=yes
BOOTFS_TYPE="fat"

# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__indiedroid-nova_use_stvhay_uboot() {
	BOOTSOURCE='https://github.com/stvhay/u-boot.git'
	BOOTBRANCH='branch:rockchip-rk3588-unified'
	BOOTPATCHDIR="legacy"
}