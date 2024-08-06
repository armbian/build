# Rockchip RK3588 octa core 16GB RAM SoC eMMC 4x NVMe 2x USB3 USB2 USB-C 2.5GbE
BOARD_NAME="FriendlyElec CM3588 NAS"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
BOOTCONFIG="nanopc_cm3588_defconfig" # Enables booting from NVMe. Vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="vendor,current,edge,collabora"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588-nanopc-cm3588-nas.dtb"
BOOT_SCENARIO="spl-blobs"

function post_family_tweaks__nanopccm3588nas_udev_naming_audios() {
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
function post_family_tweaks__nanopccm3588nas_udev_naming_network_interfaces() {
	display_alert "$BOARD" "Renaming CM3588 LAN interface to eth0" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0004:41:00.0", NAME:="eth0"
	EOF
}

# Mainline u-boot or Kwiboo's tree
function post_family_config_branch_edge__nanopccm3588nas_use_mainline_uboot() {
	display_alert "$BOARD" "mainline (next branch) u-boot overrides for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="nanopc-t6-rk3588_defconfig"                    # override the default for the board/family
	declare -g BOOTDELAY=1                                                # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g BOOTSOURCE="https://github.com/Kwiboo/u-boot-rockchip.git" # We ❤️ Kwiboo's tree
	declare -g BOOTBRANCH="branch:rk3xxx-2024.04"                         # commit:31522fe7b3c7733313e1c5eb4e340487f6000196 as of 2024-04-01
	declare -g BOOTPATCHDIR="v2024.04/board_${BOARD}"                     # empty; defconfig changes are done in hook below
	declare -g BOOTDIR="u-boot-${BOARD}"                                  # do not share u-boot directory
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}

	function write_uboot_platform_mtd() {
		flashcp -v -p "$1/u-boot-rockchip-spi.bin" /dev/mtd0
	}
}
