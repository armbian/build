# shellcheck shell=bash
# shellcheck disable=SC2034 # FIXME-QA(Krey): Define source directive for shellcheck

# Provide common configuration for the SiPeed LicheePi 4A

# NOTE(chainsx): Based on feedback, compiling U-Boot, OpenSBI, and the kernel using the GNU GCC compiler instead of the Thead-optimized compilation toolchain can lead to occasional issues in areas such as audio.

# Metadata
BOARD_NAME="SiPeed LicheePi 4A"
BOARDFAMILY="thead"

# OpenSBI
case "$BRANCH" in
	"legacy")
		# RevyOS is used as the official distro for the board and this repository is where upstream affiliates work on mainline to original project
		OPENSBISOURCE="https://github.com/revyos/thead-opensbi"
		OPENSBIBRANCH="branch:lpi4a"
		OPENSBI_USE_GCC="> 6.3"
		OPENSBI_TARGET_MAP=";;build/platform/generic/firmware/fw_dynamic.bin"
		;;
	*)
		display_alert "Building the supervisor binary for the board '$BOARD' is not implemented for branch '$BRANCH', success is not guaranteed" warn
esac

# Bootloader
case "$BRANCH" in
	"legacy")
		BOOTSOURCE='https://github.com/chainsx/thead-u-boot'
		BOOTBRANCH='branch:extlinux'
		BOOTPATCHDIR="legacy"

		case "$LICHEEPI4A_VARIANT" in
			"8")
				# https://github.com/chainsx/thead-u-boot/blob/extlinux/configs/light_lpi4a_defconfig
				BOOTCONFIG="light_lpi4a_defconfig"

				# https://github.com/revyos/thead-kernel/blob/lpi4a/arch/riscv/boot/dts/thead/light-lpi4a.dts
				BOOT_FDT_FILE="thead/light-lpi4a.dtb"
				;;
			"16")
				# https://github.com/chainsx/thead-u-boot/blob/extlinux/configs/light_lpi4a_16g_defconfig
				BOOTCONFIG="light_lpi4a_16g_defconfig"

				# https://github.com/revyos/thead-kernel/blob/lpi4a/arch/riscv/boot/dts/thead/light-lpi4a-16gb.dts
				BOOT_FDT_FILE="thead/light-lpi4a-16gb.dtb"
				;;
			*) exit_with_error "The SiPeed LicheePi 4A Variant '$LICHEEPI4A_VARIANT' is not implemented, fixme? bug?"
		esac

		BOOTFS_TYPE="ext4"
		UBOOT_TARGET_MAP=";;u-boot-with-spl.bin"
		;;
	*)
		display_alert "Building bootloader for the board '$BOARD' is not implemented for branch '$BRANCH', success is not guaranteed" warn
esac

# Kernel
# FIXME(Krey): Implement current and edge
KERNEL_TARGET="legacy"

case "$BRANCH" in
	"legacy")
		KERNELSOURCE='https://github.com/revyos/thead-kernel'
		KERNELBRANCH="branch:lpi4a"
		declare -g KERNEL_MAJOR_MINOR="5.10"
	;;
	*) display_alert "Building kernel for the board '$BOARD' is not implemented for branch '$BRANCH, success is not guaranteed" warn
esac

SERIALCON="ttyS0:115200"

SRC_EXTLINUX="yes"
SRC_CMDLINE="rootwait rw earlycon clk_ignore_unused loglevel=7 eth=\$ethaddr rootrwoptions=rw,noatime rootrwreset=yes"

# Additionals
function post_family_tweaks__licheepi4a() {
	display_alert "Applying firmware blobs" "info"

	# E902 aon fw
	cp -v "$SRC/packages/blobs/riscv64/thead/light_aon_fpga.bin" "$SDCARD/boot/light_aon_fpga.bin"

	# C906 audio fw
	cp -v "$SRC/packages/blobs/riscv64/thead/light_c906_audio.bin" "$SDCARD/boot/light_c906_audio.bin"

	# Provide the OpenSBI binary in case we are not building from source
	[ "$COMPILE_OPENSBI" = "yes" ] || cp -v "$SRC/packages/blobs/riscv64/thead/fw_dynamic.bin" "$SDCARD/boot/fw_dynamic.bin"
}
