# Rockchip RK3588S octa core 8GB RAM SoC eMMC 1x NVMe 1x USB3 1x USB2 1x 2.5GbE 1x GbE
BOARD_NAME="NanoPi R6C"
BOARD_VENDOR="friendlyelec"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="ColorfulRhino"
BOOTCONFIG="nanopi-r6c-rk3588s_defconfig" # Mainline defconfig, enables booting from NVMe
BOOT_SOC="rk3588"
KERNEL_TARGET="current,edge,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588s-nanopi-r6c.dtb"
BOOT_SCENARIO="spl-blobs"
declare -g UEFI_EDK2_BOARD_ID="nanopi-r6c" # This _only_ used for uefi-edk2-rk3588 extension

function post_family_tweaks__nanopi_r6c_naming_audios() {
	display_alert "$BOARD" "Renaming NanoPi R6C HDMI audio interface to human-readable form" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
		SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"'
	EOF
}

function post_family_tweaks__nanopi_r6c_naming_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming NanoPi R6C network interfaces to 'wan1' and 'lan1'" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="fe1c0000.ethernet", NAME:="wan1"
		SUBSYSTEM=="net", ACTION=="add", KERNELS=="0003:31:00.0", NAME:="lan1"
	EOF
}

# Mainline U-Boot
function post_family_config__nanopi_r6c_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTDELAY=1                                       # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git" # We ❤️ Mainline U-Boot
	declare -g BOOTBRANCH="tag:v2026.01"
	declare -g BOOTPATCHDIR="v2026.01"
	declare -g BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

function pre_config_uboot_target__r6c_patch_uboot_dtsi_for_ums() {
	display_alert "u-boot for ${BOARD}" "u-boot: add to u-boot dtsi for UMS" "info" # avoid a patch, just append to the dtsi file
	cat <<- EOD >> arch/arm/dts/rk3588s-nanopi-r6c-u-boot.dtsi
		&u2phy0 { status = "okay"; };
		&u2phy0_otg { status = "okay"; };
		&usbdp_phy0 { status = "okay"; };
		&usb_host0_xhci { dr_mode = "peripheral";  maximum-speed = "high-speed";  status = "okay"; };
	EOD
}

# The upstream DTs (kernel 6.13 / u-boot 2025.01) are in flux and different
# let's just patch to normalize the SD and eMMC order as in mainline Linux DT: https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/rockchip/rk3588s-nanopi-r6.dtsi#L14-L15
function pre_config_uboot_target__r6c_patch_uboot_dtsi_for_sd_emmc_order() {
	display_alert "u-boot for ${BOARD}" "u-boot: add to u-boot dtsi for SD=mmc0 and eMMC=mmc1" "info"
	cat <<- EOD >> arch/arm/dts/rk3588s-nanopi-r6c-u-boot.dtsi
		/ { aliases { mmc0 = &sdmmc; mmc1 = &sdhci; }; };
	EOD
}

# "rockchip-common: boot SD card first, then NVMe, then mmc"
# include/configs/rockchip-common.h
# -#define BOOT_TARGETS "mmc1 mmc0 nvme scsi usb pxe dhcp spi"
# +#define BOOT_TARGETS "mmc0 nvme mmc1 scsi usb pxe dhcp spi"
# On R6C, mmc1 is the eMMC, mmc0 is the SD card slot
function pre_config_uboot_target__r6c_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc0" "nvme" "mmc1" "scsi" "usb" "pxe" "dhcp" "spi") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

function post_config_uboot_target__extra_configs_for_r6c_mainline() {
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable board-specific configs" "info"
	run_host_command_logged scripts/config --enable CONFIG_DM_PMIC_FAN53555
	run_host_command_logged scripts/config --enable CONFIG_CMD_MISC

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
}
