# Allwinner D1 single core (C906) 512MB/1GB RAM WiFi/BT HDMI
BOARD_NAME="Mangopi-MQ"
BOARD_VENDOR="mangopi"
BOARDFAMILY="d1"
BOARD_MAINTAINER=""
INTRODUCED="2021"
KERNEL_TARGET="edge"
BOOT_FDT_FILE="allwinner/sun20i-d1-mangopi-mq-pro.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200n8 console=tty0 earlycon=sbi rootflags=data=writeback stmmaceth=chain_mode:1 rw"
BOOTCONFIG="nezha_defconfig"

enable_extension "mangopi-rtc"

# Build MQ Pro SPL/FIT with the existing firmware package functions.
function post_family_config__mangopi_source_boot() {
	declare -g BOOTPATCHDIR="u-boot-mangopi-mq-spl"
	declare -g BOOTBRANCH="commit:2e89b706f5c956a70c989cd31665f1429e9a0b48"
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
	# Keep the verified GPT and ext4 layout during the SPL transition.
	run_host_command_logged sgdisk --move-main-table=8160 "${SDCARD}.raw"
}
# Enable SPL/FIT with the MQ Pro memory layout.
function post_config_uboot_target__mangopi_source_boot() {
	run_host_command_logged ./scripts/config --set-val TEXT_BASE 0x4a000000 \
		--enable SPL --enable SPL_LOAD_FIT --enable SPL_OPENSBI \
		--set-val SPL_OPENSBI_LOAD_ADDR 0x40000000 \
		--enable EFI_PARTITION --enable PARTITION_UUIDS --enable CMD_SYSBOOT --enable FS_EXT4 --enable CMD_EXT4 \
		--enable SUNXI_MANGOPI_MQ_SPL
	run_host_command_logged make CROSS_COMPILE=riscv64-linux-gnu- olddefconfig
}
