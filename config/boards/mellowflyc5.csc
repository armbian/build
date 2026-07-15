# Allwinner H618 quad core 1GB RAM SoC 100M Ethernet WiFi
BOARD_NAME="Mellow Fly-C5"

BOARD_VENDOR="mellow"
BOARDFAMILY="sun50iw9"
BOARD_MAINTAINER="deece"
INTRODUCED="2026"
BOOTCONFIG="mellow_fly_c5_defconfig"
OVERLAY_PREFIX="sun50i-h616"
BOOT_FDT_FILE="allwinner/sun50i-h618-mellow-fly-c5.dtb"
BOOT_LOGO="desktop"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
FORCE_BOOTSCRIPT_UPDATE="yes"
BOOTENV_FILE="mellowflyc5.txt"


# WiFi RTL8821CS
PACKAGE_LIST_BOARD="rfkill mmc-utils"

# Enable eMMC (mmc2) in the SPL. Without this, CONFIG_MMC_SUNXI_SLOT_EXTRA
# defaults to -1 and the SPL never calls sunxi_mmc_init(2), causing
# "MMC Device 1 not found" when booting from eMMC.
function post_config_uboot_target__mellowflyc5_emmc() {
	display_alert "Enabling eMMC slot" "CONFIG_MMC_SUNXI_SLOT_EXTRA=2" "info"
	run_host_command_logged scripts/config --set-val CONFIG_MMC_SUNXI_SLOT_EXTRA 2
}

function post_family_tweaks__mellowflyc5_console() {
	display_alert "$BOARD" "Enabling serial-getty on ttyS1" "info"
	mkdir -p "${SDCARD}/etc/systemd/system/serial-getty@ttyS1.service.d"
	cat <<- 'EOD' > "${SDCARD}/etc/systemd/system/serial-getty@ttyS1.service.d/override.conf"
		[Service]
		ExecStart=
		ExecStart=-/sbin/agetty -o '-- \u' --noreset --noclear 115200 %I $TERM
	EOD
	chroot_sdcard systemctl enable serial-getty@ttyS1.service
	return 0
}

