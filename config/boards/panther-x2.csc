# Rockchip RK3566 quad core 4GB RAM SoC WIFI/BT eMMC USB2
BOARD_NAME="panther-x2"
BOARD_VENDOR="panther"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
BOOTCONFIG="rock-3c-rk3566_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3566-panther-x2.dtb"
IMAGE_PARTITION_TABLE="gpt"
BOOT_SCENARIO="spl-blobs"
BOOTFS_TYPE="fat"

function post_family_config__use_radxa_rock3_uboot() {
    display_alert "Overriding U-Boot source" "Using Radxa stable-4.19-rock3" "info"
    
    BOOTSOURCE="https://github.com/radxa/u-boot.git"
    BOOTBRANCH="branch:stable-4.19-rock3"
    BOOTPATCHDIR="none"
    BOOTPATCHES="none"
    SKIP_BOOTSPLASH_PATCHES="yes"
}
