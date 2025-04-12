# Allwinner H618 quad core 2/4GB RAM 8GB eMMC SoC WiFi\Bt HDMI SPI USB-C
BOARD_NAME="BananaPi M4 Berry"
BOARDFAMILY="sun50iw9-bpi"
BOARD_MAINTAINER="The-going"
BOOTCONFIG="bananapi_m4_berry_defconfig"

BOOTPATCHDIR="v2025-sunxi"
BOOTBRANCH_BOARD="tag:v2025.04"

OVERLAY_PREFIX="sun50i-h616"
BOOT_FDT_FILE="sun50i-h618-bananapi-m4-berry.dtb"
BOOT_LOGO="desktop"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"

PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"

function post_family_tweaks_bsp__bananapi_module_conf() {

	mkdir -p "${destination}"/etc/modprobe.d/
	display_alert "$BOARD" "Configuring rlt8821cu wifi module" "info"

	cat <<-EOF > "${destination}"/etc/modprobe.d/8821cu.conf
		# https://github.com/morrownr/8821cu-20210916/blob/main/8821cu.conf
		#
		# To see all options that are available:
		#
		# for f in /sys/module/8821cu/parameters/*;do echo "\$(basename \$f): \$(sudo cat \$f)";done
		#
		blacklist rtw88_8821cu
		#
		options 8821cu rtw_led_ctrl=2
	EOF

}
