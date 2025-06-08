#Texas Instruments AM67A quad core 4GB USB3 DDR4 4TOPS

BOARD_NAME="BeagleY-AI"
BOARDFAMILY="k3"
BOARD_MAINTAINER="Grippy98"
BOOTCONFIG="am67a_beagley_ai_a53_defconfig"
BOOTFS_TYPE="fat"
BOOT_FDT_FILE="k3-am67a-beagley-ai.dts"
TIBOOT3_BOOTCONFIG="am67a_beagley_ai_r5_defconfig"
TIBOOT3_FILE="tiboot3-j722s-hs-fs-evm.bin"
DEFAULT_CONSOLE="serial"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
SERIALCON="ttyS2"
ATF_BOARD="lite"
OPTEE_ARGS=""
OPTEE_PLATFORM="k3-am62x"

# Use these branches until BeagleY-AI goes upstream
function post_family_config_branch_current__beagley_ai_use_beagle_kernel_uboot() {
	display_alert "$BOARD" " Beagleboard U-Boot and kernel overrides for $BOARD / $BRANCH" "info"

	declare -g KERNELSOURCE="https://github.com/beagleboard/linux" # BeagleBoard kernel
	declare -g KERNEL_MAJOR_MINOR="6.6"
	declare -g KERNELBRANCH="branch:v6.6.58-ti-arm64-r21"
	declare -g LINUXFAMILY="k3-beagle" # Separate kernel package from the regular `k3` family
	declare -g LINUXCONFIG="linux-k3-${BRANCH}"

	declare -g BOOTSOURCE="https://github.com/glneo/u-boot" # v2025.04-rc3 + BeagleY-AI support
	declare -g BOOTBRANCH="branch:beagley-ai"
	declare -g BOOTPATCHDIR="u-boot-beagle"
}
