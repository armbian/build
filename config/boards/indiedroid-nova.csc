# Rockchip RK3588S octa core 4/8/16GB RAM SoC eMMC USB3 USB-C GbE
BOARD_NAME="Indiedroid Nova"
BOARDFAMILY="rockchip-rk3588"
BOOTCONFIG="indiedroid_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="indiedroid"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3588s-9tripod-linux.dtb"
BOOT_SCENARIO="spl-blobs"
WIREGUARD="no"
BOOT_SUPPORT_SPI="yes"
IMAGE_PARTITION_TABLE="gpt"
SKIP_BOOTSPLASH="yes" # Skip boot splash patch, conflicts with CONFIG_VT=yes
BOOTFS_TYPE="fat"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 console=tty1 console=both net.ifnames=0 rootflags=data=writeback"
EXTRAWIFI="no"


# Override family config for this board; let's avoid conditionals in family config.
function post_family_config__indiedroid-nova_use_stvhay_uboot() {
	BOOTSOURCE='https://github.com/stvhay/u-boot.git'
	BOOTBRANCH='branch:rockchip-rk3588-unified'
	BOOTPATCHDIR="legacy"
}

function post_family_config_branch_indiedroid__stvhay_kernel() {
	KERNELDIR='linux-rockchip64-rk3588-indiedroid'
	KERNELSOURCE='https://github.com/stvhay/kernel'
	declare -g KERNEL_MAJOR_MINOR="5.10" # Major and minor versions of this kernel.
	KERNELBRANCH='branch:armbian-9tripod-patchset'
#	KERNELBRANCH='branch:batocera-rk3588-3.6'
	KERNELPATCHDIR='rockchip-rk3588-indiedroid'
	LINUXCONFIG='linux-rockchip-rk3588-indiedroid'

	}
