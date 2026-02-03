# Rockchip RK3566 quad core 2GB RAM eMMC 2x GbE USB3
BOARD_NAME="NanoPi R3S"
BOARD_VENDOR="friendlyelec"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
HAS_VIDEO_OUTPUT="no"
BOOTCONFIG="nanopi-r3s-rk3566_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current,edge"
BOOT_FDT_FILE="rockchip/rk3566-nanopi-r3s.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"


function post_family_config__use_mainline_uboot() {
	if [[ "$BRANCH" == "vendor" ]]; then
    	return 0
	fi

	unset BOOT_FDT_FILE # boot.scr will use whatever u-boot detects and sets 'fdtfile' to
	
	# Mainline U-Boot can read ext4 directly, so no separate boot partition needed for ext4 root
	# However, for filesystems U-Boot cannot read (btrfs, f2fs, etc.), we need a boot partition
	if [[ "$ROOTFS_TYPE" =~ btrfs|f2fs|nilfs2|xfs ]]; then
		BOOTFS_TYPE=${BOOTFS_TYPE:-ext4}
		BOOTSIZE=${BOOTSIZE:-512}
	else
		unset BOOTFS_TYPE  # ext4 root can be read directly by U-Boot
	fi
	BOOTCONFIG="nanopi-r3s-rk3566_defconfig"
	BOOTSOURCE="https://github.com/u-boot/u-boot"
	BOOTBRANCH="tag:v2025.04"
	BOOTPATCHDIR="v2025.04"

	UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB ROCKCHIP_TPL=$RKBIN_DIR/$DDR_BLOB;;u-boot-rockchip.bin"

	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	function write_uboot_platform() {
		dd if=$1/u-boot-rockchip.bin of=$2 seek=64 conv=notrunc status=none
	}
}
