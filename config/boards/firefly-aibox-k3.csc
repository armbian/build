# SpacemiT K3 16-core RISC-V SoC, UFS Storage

BOARD_NAME="AIBOX-K3"
BOARD_VENDOR="firefly"
BOARDFAMILY="spacemit-k3"
BOARD_MAINTAINER="leoppark94"
INTRODUCED="2026"
# SpacemiT 6.18 vendor BSP is currently classified as legacy in the family config
KERNEL_TARGET="legacy"
KERNEL_TEST_TARGET="legacy"

BOOT_FDT_FILE="spacemit/k3-firefly-aibox-k3.dtb"

# UFS layout matching the vendor firmware: bootfs at 12 MiB, rootfs at 268 MiB.
# 4096-byte sectors are required: the UFS reports 4096-byte logical sectors and
# a 512-byte boot FAT would fail to mount.
IMAGE_PARTITION_TABLE="gpt"
SECTOR_SIZE="4096"
OFFSET="12"

BOOTFS_TYPE="fat"
BOOTSIZE="256"

# U-Boot is provided by the vendor SPI NOR firmware. It is not part of the
# image and is never written by the image or the installer.
# Installation uses the vendor TitanFlasher with bootfs.img and rootfs.ext4
# taken from this image.
function post_config_uboot_target__firefly_aibox_k3() {
	write_uboot_platform() {
		echo "NOTE: U-Boot is stored in SPI NOR and is not written to the UFS image."
	}
}

# Environment file expected by the vendor U-Boot on the boot partition.
function pre_umount_final_image__write_env_k3_txt() {
	local boot_dir="${MOUNT}/boot"

	cat > "${boot_dir}/env_k3.txt" <<-'EOF'
	console=ttyS0,115200
	bootdelay=5
	knl_name=Image
	dtb_dir=dtb/spacemit
	loglevel=8
	EOF
}
