# Allwinner D1 single core (C906) 512MB/1GB RAM WiFi/BT HDMI
BOARD_NAME="MQ Pro"
BOARD_VENDOR="mangopi"
BOARDFAMILY="d1"
BOARD_MAINTAINER="khaliforce"
INTRODUCED="2021"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"
BOOT_FDT_FILE="allwinner/sun20i-d1-mangopi-mq-pro.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 console=tty0 earlycon=sbi rootflags=data=writeback stmmaceth=chain_mode:1 rw"
BOOTCONFIG="mangopi_mq_pro_defconfig"

enable_extension "mangopi-rtc"

enable_extension "grub-riscv64"
enable_extension "mangopi-grub"

# The hardware monitor walks /sys at each boot and triggers the tracefs automount notice.
function post_customize_image__mangopi_disable_hw_monitor() {
	chroot_sdcard systemctl disable armbian-hardware-monitor.service "||" true
}

# Build MQ Pro SPL/FIT with the existing firmware package functions.
function post_family_config__mangopi_source_boot() {
	declare -g ATFBRANCH="tag:v1.9" ATFPATCHDIR="atf-opensbi-v1.9"
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.10"
	declare -g BOOTPATCHDIR="v2026.10"
	declare -g UBOOT_TARGET_MAP=";;u-boot-sunxi-with-spl.bin"
	declare -g IMAGE_PARTITION_TABLE="gpt" OFFSET=4 BOOTSIZE=0 BOOTFS_TYPE="" SRC_EXTLINUX=yes
	local input_hash
	input_hash=$(sha256sum "${BASH_SOURCE[0]}")
	declare -g UBOOT_HASH_EXTRA="${input_hash%% *}"
	# Reject firmware that would overwrite GPT metadata.
	function write_uboot_platform() {
		local image="${1}/u-boot-sunxi-with-spl.bin"
		[[ -s $image ]] || return 1
		local image_size
		image_size=$(stat -c %s -- "$image") || return 1
		# Firmware must end before the GPT entry table at sector 8160.
		[[ $image_size -le $(((8160 - 256) * 512)) ]] || return 1
		# Sector 256 avoids GPT metadata. SPL finds FIT after its own image.
		dd if="$image" of="${2}" bs=512 seek=256 conv=notrunc
	}
}
# Keep GPT entries outside the reserved firmware area.
function post_create_partitions__mangopi_source_boot() {
	run_host_command_logged sgdisk --move-main-table=8160 "${SDCARD}.raw"
}
