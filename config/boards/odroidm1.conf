# Rockchip RK3568 quad core 4GB-8GB GBE PCIe USB3 SATA NVMe
BOARD_NAME="Odroid M1"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER="rpardini"
BOOT_SOC="rk3568"
KERNEL_TARGET="current,edge"
BOOT_FDT_FILE="rockchip/rk3568-odroid-m1.dtb"
SRC_EXTLINUX="no"
ASOUND_STATE="asound.state.station-m2"
IMAGE_PARTITION_TABLE="gpt"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"

BOOTBRANCH_BOARD="tag:v2024.07"
BOOTPATCHDIR="v2024.07"

BOOTCONFIG="odroid-m1-rk3568_defconfig"
BOOTDIR="u-boot-${BOARD}" # do not share u-boot directory

# The overlays for this board are prefixed by 'rockchip-rk3568-hk' (see for example patch/kernel/archive/rockchip64-6.6/overlay/rockchip-rk3568-hk-i2c0.dts)
OVERLAY_PREFIX="rockchip-rk3568-hk"

# HK's SPI partition on MTD:
# mtd0: start 0         size 917.504   end 917.504    : SPL          == start 0x0      size 0xe0000  : SPL
# mtd1: start 917.504   size 131.072   end 1.048.576  : U-Boot Env   == start 0xe0000  size 0x20000  : U-Boot Env
# mtd2: start 1.048.576 size 2.097.152 end 3.145.728  : U-Boot       == start 0x100000 size 0x200000 : U-Boot
function post_family_config__uboot_config() {
	display_alert "$BOARD" "u-boot ${BOOTBRANCH_BOARD} overrides" "info"
	BOOTDELAY=1 # Wait for UART interrupt to enter UMS/RockUSB mode etc
	UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/$BL31_BLOB ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin u-boot-rockchip-spi.bin u-boot.itb idbloader.img idbloader-spi.img"
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd # disable stuff from rockchip64_common; we're using binman here which does all the work already

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd if=${1}/u-boot-rockchip.bin of=${2} bs=32k seek=1 conv=fsync
	}

	# We don't use u-boot-rockchip-spi.bin here; instead, write SPL and u-boot individually
	# If we're deinfesting from Petitboot, clear the environment too; PREBOOT will save a new one for mainline
	function write_uboot_platform_mtd() {
		declare -a extra_opts_flashcp=("--verbose")
		# -p is: "read the flash and only write blocks that are actually different"
		# if on bullseye et al, flashcp/mtd-utils is old, and doesn't have --partition/-p
		if flashcp -h | grep -q -e '--partition'; then
			echo "Confirmed flashcp supports --partition -- read and write only changed blocks." >&2
			extra_opts_flashcp+=("--partition")
		else
			echo "flashcp does not support --partition, will write full SPI flash blocks." >&2
		fi
		flashcp "${extra_opts_flashcp[@]}" "${1}/idbloader-spi.img" /dev/mtd0 # write SPL
		flashcp "${extra_opts_flashcp[@]}" "${1}/u-boot.itb" /dev/mtd2        # write u-boot
		if fw_printenv | grep -q -i petitboot; then                           # Petitboot leaves a horrible env behind, clear it off if so
			echo "Found traces of Petitboot in SPI u-boot environment, clearing SPI environment..." >&2
			flash_erase /dev/mtd1 0 0 # clear u-boot env
		fi
	}
}

# Include fw_setenv, configured to point to Petitboot's u-env mtd partition
PACKAGE_LIST_BOARD="libubootenv-tool" # libubootenv-tool provides fw_printenv and fw_setenv, for talking to U-Boot environment

function post_family_tweaks__config_odroidm1_fwenv() {
	display_alert "Configuring fw_printenv and fw_setenv" "for Odroid M1" "info"
	# Addresses below come from
	# - (we use mainline, not vendor, so this is only for reference)
	#   https://github.com/hardkernel/u-boot/blob/356906e6445378a45ac14ec184fc6e666b22338a/configs/odroid_rk3568_defconfig#L212-L213
	# The kernel DT has a convenient partition table, so mtd1 is ready to use, just gotta set the size.
	#   https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/rockchip/rk3568-odroid-m1.dts#L637-L662

	cat <<- 'FW_ENV_CONFIG' > "${SDCARD}"/etc/fw_env.config
		# MTD on the SPI for the Odroid-M1; this requires the MTD partition table in the board kernel DTS
		# MTD device name Device offset Env. size Flash sector size Number of sectors
		/dev/mtd1                       0x0000                      0x20000
	FW_ENV_CONFIG

	# add a network rule to rename default name
	display_alert "Creating network rename rule for Odroid M1"
	mkdir -p "${SDCARD}"/etc/udev/rules.d/
	cat <<- EOF > "${SDCARD}"/etc/udev/rules.d/70-rename-lan.rules
		SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", KERNEL=="end*", NAME="eth0"
	EOF

}

# A better equivalent to patching a defconfig, do changes to .config via code.
# For UMS/RockUSB to work in u-boot, &usb_host0_xhci { dr_mode = "otg" } is required. See 0002-board-rockchip-ODROID-M1-override-kernel-DT-for-xhci-otg-dr_mode.patch
function post_config_uboot_target__extra_configs_for_odroid-m1() {
	[[ "${BRANCH}" == "edge" || "${BRANCH}" == "current" ]] || return 0

	display_alert "u-boot for ${BOARD}" "u-boot: store ENV in SPI, matching Petitboot size/offset" "info"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_IS_NOWHERE "n"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_IS_IN_SPI_FLASH "y"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_SIZE "0x20000"
	run_host_command_logged scripts/config --set-val CONFIG_ENV_OFFSET "0xe0000"
	run_host_command_logged scripts/config --enable CONFIG_VERSION_VARIABLE

	display_alert "u-boot for ${BOARD}" "u-boot: enable preboot & reset environment once in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'echo armbian leds; led led-0 on; led led-1 on; sleep 0.1; led led-0 off; led led-1 off; sleep 0.1; led led-0 on; if test a\${armbian}a = atwicea; then echo armbian env already set once; else echo armbian resetting environment once; env default -f -a; setenv armbian twice; saveenv; fi'" # double quote

	display_alert "u-boot for ${BOARD}" "u-boot: enable EFI debugging command" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enabling UMS/RockUSB Gadget functionality" "info"
	declare -a enable_configs=("CONFIG_CMD_USB_MASS_STORAGE" "CONFIG_USB_GADGET" "USB_GADGET_DOWNLOAD" "CONFIG_USB_FUNCTION_ROCKUSB" "CONFIG_USB_FUNCTION_ACM" "CONFIG_CMD_ROCKUSB" "CONFIG_CMD_USB_MASS_STORAGE")
	for config in "${enable_configs[@]}"; do
		run_host_command_logged scripts/config --enable "${config}"
	done
	# Auto-enabled by the above, force off...
	run_host_command_logged scripts/config --disable USB_FUNCTION_FASTBOOT
}
