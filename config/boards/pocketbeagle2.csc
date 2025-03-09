#Texas Instruments AM62 dual core 1GB USB2 DDR4

BOARD_NAME="PocketBeagle 2"
BOARDFAMILY="k3"
BOARD_MAINTAINER="Grippy98"
BOOTCONFIG="am6232_pocketbeagle2_a53_defconfig"
BOOTFS_TYPE="fat"
BOOT_FDT_FILE="k3-am6232-pocketbeagle2.dts"
TIBOOT3_BOOTCONFIG="am6232_pocketbeagle2_r5_defconfig"
TIBOOT3_FILE="tiboot3-am62x-hs-fs-evm.bin"
DEFAULT_CONSOLE="serial"
KERNEL_TARGET="edge"
KERNEL_TEST_TARGET="edge"
SERIALCON="ttyS2"
ATF_BOARD="lite"

#Until PB2 goes upstream, use this branch
function post_family_config_branch_edge__pocketbeagle2_use_beagle_kernel_uboot() {
	display_alert "$BOARD" " beagleboard (next branch) u-boot and kernel overrides for $BOARD / $BRANCH" "info"

	declare -g KERNELSOURCE="https://github.com/beagleboard/linux" # BeagleBoard kernel
	declare -g KERNEL_MAJOR_MINOR="6.12"
	declare -g KERNELBRANCH="branch:v6.12.13-ti-arm64-r24"
	declare -g LINUXFAMILY="k3-beagle" # Separate kernel package from the regular `k3` family

	declare -g BOOTSOURCE="https://github.com/beagleboard/u-boot" # BeagleBoard u-boot
	declare -g BOOTBRANCH="branch:v2025.01-pocketbeagle2"
}
