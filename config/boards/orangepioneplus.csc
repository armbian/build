# Allwinner H6 quad core 1GB RAM SoC GBE
BOARD_NAME="Orange Pi One+"
BOARD_VENDOR="xunlong"
BOARDFAMILY="sun50iw6"
BOARD_MAINTAINER=""
BOOTCONFIG="orangepi_one_plus_defconfig"
KERNEL_TARGET="current,edge,legacy"
KERNEL_TEST_TARGET="current"
CRUSTCONFIG="pine_h64_defconfig"

function post_family_config__use_orangepioneplus_uboot() {
	case $BRANCH in
		* )
			declare -g ATFBRANCH="tag:lts-v2.12.9"
			declare -g BOOTPATCHDIR="v2026.01"
			declare -g BOOTBRANCH_BOARD="tag:${BOOTPATCHDIR}"
			declare -g BOOTBRANCH="${BOOTBRANCH_BOARD}"
			;;
	esac
}
