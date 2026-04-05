# Rockchip RK3588 octa core 16GB RAM SoC eMMC 4x NVMe 2x USB3 USB2 USB-C 2.5GbE
BOARD_NAME="FriendlyElec CM3588 NAS"
BOARD_VENDOR="friendlyelec"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="ColorfulRhino"
BOOTCONFIG="cm3588-nas-rk3588_defconfig" # Mainline defconfig, enables booting from NVMe
BOOT_SOC="rk3588"
KERNEL_TARGET="current,edge,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588-friendlyelec-cm3588-nas.dtb"
BOOT_SCENARIO="tpl-blob-atf-mainline"
UEFI_EDK2_BOARD_ID="nanopc-cm3588-nas" # This _only_ used for uefi-edk2-rk3588 extension; cm3588-nas was introduced in v0.12 of edk2-porting/edk2-rk3588

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

	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.01"
	declare -g BOOTPATCHDIR="v2026.01"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=bl31.elf ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # Disable stuff from rockchip64_common; we're using binman here which does all the work

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

function pre_config_uboot_target__cm3588_patch_uboot_dtsi_for_ums() {
	display_alert "u-boot for ${BOARD}" "u-boot: add to u-boot dtsi for UMS" "info" # avoid a patch, just append to the dtsi file
	cat <<- UBOOT_BOARD_DTSI_OTG >> arch/arm/dts/rk3588-friendlyelec-cm3588-nas-u-boot.dtsi
		&u2phy0 { status = "okay"; };
		&u2phy0_otg { status = "okay"; };
		&usbdp_phy0 { status = "okay"; };
		&usb_host0_xhci { dr_mode = "peripheral";  maximum-speed = "high-speed";  status = "okay"; };
	UBOOT_BOARD_DTSI_OTG
}

# "rockchip-common: boot SD card first, then NVMe, then mmc"
# include/configs/rockchip-common.h
# -#define BOOT_TARGETS "mmc1 mmc0 nvme scsi usb pxe dhcp spi"
# +#define BOOT_TARGETS "mmc0 nvme mmc1 scsi usb pxe dhcp spi"
# On cm3588-nas, mmc0 is the eMMC, mmc1 is the SD card slot
function pre_config_uboot_target__cm3588_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc1" "nvme" "mmc0" "scsi" "usb" "pxe" "dhcp" "spi") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

function post_config_uboot_target__extra_configs_for_cm3588-nas_uboot() {
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable preboot & flash user LED in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led green on; sleep 0.1; led green off'" # double quotes required due to run_host_command_logged's quirks

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable EFI debugging commands" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable more filesystems support" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_BTRFS

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK

	# UMS, RockUSB, gadget stuff
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable UMS/RockUSB gadget" "info"
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB" "CONFIG_CMD_USB_MASS_STORAGE")
	for config in "${enable_configs[@]}"; do
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT

	return 0
}
