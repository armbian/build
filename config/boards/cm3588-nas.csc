# Rockchip RK3588 octa core 16GB RAM SoC eMMC 4x NVMe 2x USB3 USB2 USB-C 2.5GbE
BOARD_NAME="FriendlyElec CM3588 NAS"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="ColorfulRhino"
BOOTCONFIG="cm3588-nas-rk3588_defconfig" # Mainline defconfig, enables booting from NVMe
BOOT_SOC="rk3588"
KERNEL_TARGET="edge,current,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588-friendlyelec-cm3588-nas.dtb"
BOOT_SCENARIO="spl-blobs"

function post_family_tweaks__cm3588_nas_udev_naming_audios() {
	display_alert "$BOARD" "Renaming CM3588 audio interfaces to human-readable form" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/

	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/90-naming-audios.rules"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI-0 Audio Out"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi1-sound", ENV{SOUND_DESCRIPTION}="HDMI-1 Audio Out"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DisplayPort-Over-USB Audio Out"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-rt5616-sound", ENV{SOUND_DESCRIPTION}="Headphone Out/Mic In"
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmiin-sound", ENV{SOUND_DESCRIPTION}="HDMI-IN Audio In"
	EOF
}

# Output from CM3588 syslog with edge kernel 6.8: r8169 0004:41:00.0 enP4p65s0: renamed from eth0
# Note: legacy kernel 5.10 uses driver r8125, edge kernel uses r8169 as of 6.8
function post_family_tweaks__cm3588_nas_udev_naming_network_interfaces() {
	display_alert "$BOARD" "Renaming CM3588 LAN interface to eth0" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0004:41:00.0", NAME:="eth0"
	EOF
}

# Mainline U-Boot
function post_family_config__cm3588_nas_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTDELAY=1                                       # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git" # We ❤️ Mainline U-Boot
	declare -g BOOTBRANCH="tag:v2024.10"
	declare -g BOOTPATCHDIR="v2024.10"
	# Don't set BOOTDIR, allow shared U-Boot source directory for disk space efficiency

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
