# Rockchip RK3588S octa core 32GB RAM SoC eMMC NvME 1x USB3 4x USB2 1x GbE
BOARD_NAME="Youyeetoo R1 v3"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER="SuperKali"
BOOTCONFIG="generic-rk3588_defconfig" # vendor name, not standard, see hook below, set BOOT_SOC below to compensate
BOOT_SOC="rk3588"
KERNEL_TARGET="current,edge,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
IMAGE_PARTITION_TABLE="gpt"
BOOT_FDT_FILE="rockchip/rk3588s-youyeetoo-r1.dtb"
BOOT_SCENARIO="spl-blobs"

function post_family_tweaks__youyeetoo_r1_naming_audios() {
	display_alert "$BOARD" "Renaming Youyeetoo R1 audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8388-sound", ENV{SOUND_DESCRIPTION}="ES8388 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules

	return 0
}

function post_family_tweaks__youyeetoo_r1_naming_udev_network_interfaces() {
	display_alert "$BOARD" "Renaming Youyeetoo R1 network interfaces to eth0" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}/etc/udev/rules.d/70-persistent-net.rules"
		SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", KERNELS=="fe1c0000.ethernet", NAME:="eth0"
	EOF
}

# Mainline U-Boot
function post_family_config__youyeetoo_r1_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline (next branch) U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTCONFIG="generic-rk3588_defconfig"             # Use generic defconfig which should boot all RK3588 boards
	declare -g BOOTDELAY=1                                       # Wait for UART interrupt to enter UMS/RockUSB mode etc
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git" # We ❤️ Mainline U-Boot
	declare -g BOOTBRANCH="tag:v2025.01"
	declare -g BOOTPATCHDIR="v2025.01"
	# Don't set BOOTDIR, allow shared U-Boot source directory for disk space efficiency

	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}

# "rockchip-common: boot SD card first, then NVMe, then mmc"
# include/configs/rockchip-common.h
# -#define BOOT_TARGETS "mmc1 mmc0 nvme scsi usb pxe dhcp"
# +#define BOOT_TARGETS "mmc0 nvme mmc1 scsi usb pxe dhcp"
# On youyeetoo R1, mmc0 is the SD card, mmc1 is the eMMC slot
function pre_config_uboot_target__youyeetoo_r1_patch_rockchip_common_boot_order() {
	declare -a rockchip_uboot_targets=("mmc0" "nvme" "mmc1" "scsi" "usb" "pxe" "dhcp") # for future make-this-generic delight
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

function post_family_tweaks__youyeetoo_r1 {
	if [[ "${BRANCH}" != "vendor" ]]; then
		display_alert "$BOARD" "Adjusting rtw89_8852be module" "info"
		cat <<- EOF > "${SDCARD}/etc/modprobe.d/rtw8852be.conf"
			options rtw89_pci disable_aspm_l1=y disable_aspm_l1ss=y
			options rtw89pci disable_aspm_l1=y disable_aspm_l1ss=y
			options rtw89_core disable_ps_mode=y
			options rtw89core disable_ps_mode=y
		EOF
	fi
}
