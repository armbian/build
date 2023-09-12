# RISC-V BeagleV-Ahead

# shellcheck shell=bash
# shellcheck disable=SC2034 # FIXME-QA(Krey): Define source directive for shellcheck

# Metadata
BOARD_NAME="BeagleV-Ahead"
BOARDFAMILY="thead"

# OpenSBI
OPENSBISOURCE="https://github.com/revyos/opensbi"
OPENSBIBRANCH="branch:th1520-v1.3.1"

# Bootloader
BOOTSOURCE='https://github.com/chainsx/thead-u-boot'
BOOTBRANCH='branch:extlinux'

BOOT_FDT_FILE="thead/light-beagle.dtb"

BOOTCONFIG="light_beagle_defconfig"

# Kernel
# FIXME(Krey): Pull this on top of 6.5.2 (has over 2 months of riscv changes)
KERNELSOURCE="https://github.com/beagleboard/linux"
KERNELBRANCH="branch:v6.5-rc1-BeagleV-Ahead"
declare -g KERNEL_MAJOR_MINOR="6.5"

KERNEL_TARGET="edge" # legacy,current?

# Misc
SKIP_BOOTSPLASH="yes"

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
