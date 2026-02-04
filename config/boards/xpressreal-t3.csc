# Realtek rtd1619b quad core 4GB Mem/32GB eMMC 1x HDMI 1x USB 3.2 1x USB 2.0
BOARD_NAME="XpressReal T3"
BOARD_VENDOR="xpressreal"
BOARDFAMILY="realtek-rtd1619b"
BOARD_MAINTAINER="wei633"
KERNEL_TARGET="vendor"
DEFAULT_CONSOLE="both"
SERIALCON="ttyS0:460800"
FULL_DESKTOP="yes"
BOOT_FDT_FILE="realtek/rtd1619b-bleedingedge-4gb.dtb"

ROOTFS_TYPE="ext4"
ROOT_FS_LABEL="ROOT"

BOOTFS_TYPE="fat"
BOOT_FS_LABEL="BOOT"
BOOTSIZE=512

declare -g BLUETOOTH_HCIATTACH_PARAMS="/dev/ttyS1 any 1500000 flow"
declare -g BLUETOOTH_HCIATTACH_RKFILL_NUM="all"
enable_extension "bluetooth-hciattach"

declare -g AIC8800_TYPE="sdio"
enable_extension "radxa-aic8800"

function post_family_tweaks_bsp__xpressreal_load_modules() {
	display_alert "$BOARD" "Installing AIC8800 Tweaks" "info"

	mkdir -p "${destination}"/etc/modprobe.d
	mkdir -p "${destination}"/etc/modules-load.d

	# AIC8800 wireless drivers
	cat > "${destination}"/etc/modprobe.d/aic8800-wireless.conf <<- EOT
		options aic8800_fdrv_sdio aicwf_dbg_level=0 custregd=0 ps_on=0
	EOT

	# block RTK devices drivers autoload
	cat > "${destination}"/etc/modprobe.d/rtk-devices.conf <<- EOT
		blacklist rtk_fw_remoteproc
		blacklist rpmsg_rtk
		blacklist rtk_rpc_mem
		blacklist rtk_krpc_agent
		blacklist rtk_urpc_service
		blacklist snd_soc_hifi_realtek
		blacklist snd_soc_realtek
		blacklist rtk_drm
	EOT

	# bluetooth modules
	cat > "${destination}"/etc/modules-load.d/10-bluetooth.conf <<- EOT
		hidp
		rfcomm
		bnep
		aic8800_btlpm_sdio
	EOT

	display_alert "Install custom service to load RTK modules in strict order" "info"
	# load RTK modules in order with custom script
	install -d -m 0755 "${destination}/usr/local/sbin"
	install -m 0755 "${SRC}/packages/bsp/xpressreal-t3/load-rtk-modules.sh" "${destination}/usr/local/sbin/load-rtk-modules.sh"
	install -d -m 0755 "${destination}/usr/lib/systemd/system"
	install -m 0644 "${SRC}/packages/bsp/xpressreal-t3/load-rtk-modules.service" "${destination}/usr/lib/systemd/system/load-rtk-modules.service"
}

function post_family_tweaks__xpressreal_load_module_service() {
	display_alert "$BOARD" "Enable XpressReal modules loading service" "info"
	if chroot_sdcard test -f /lib/systemd/system/load-rtk-modules.service || chroot_sdcard test -f /etc/systemd/system/load-rtk-modules.service; then
		chroot_sdcard systemctl --no-reload enable load-rtk-modules.service
	else
		display_alert "$BOARD" "load-rtk-modules.service not found in image; skipping enable" "warn"
	fi
}
