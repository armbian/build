# Rockchip RK3566T quad core 1GB RAM WiFi6/BT USB3 HDMI
BOARD_NAME="Quartz64 Zero"
BOARD_VENDOR="pine64"
BOARDFAMILY="rockchip64"
BOARD_MAINTAINER=""
INTRODUCED="2024"
BOOT_SOC="rk3566"
BOOTCONFIG="quartz64-zero-rk3566_defconfig"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="rockchip/rk3566-quartz64-zero.dtb"
IMAGE_PARTITION_TABLE="gpt"

# Onboard AIC8800DC Wi-Fi on SDIO, as on the Rock 3C.
enable_extension "radxa-aic8800"
AIC8800_TYPE="sdio"

# Onboard AIC8800DC Bluetooth: UART HCI on ttyS1 (uart1, RTS/CTS).
# i2c-tools: for rk817-input-limit.service (below).
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools i2c-tools"

# VCC_SYS -- the input of every buck and of the USB port power switches -- comes
# out of the RK817 charger's power path. Mainline leaves its input current limit
# (PMIC_CHRG_IN, 0xe5) at the reset value 0xc8; the board then resets whenever
# the Wi-Fi radio starts (DPD calibration, scan, Bluetooth), under GPU load or
# with a USB device attached. Pine64's Android kernel sets 0xdf; do the same,
# before udev loads the Wi-Fi driver.
function post_family_tweaks_bsp__quartz64_zero_rk817_input_limit() {
	display_alert "$BOARD" "Installing RK817 input current limit service" "info"
	mkdir -p "${destination}"/usr/sbin "${destination}"/usr/lib/systemd/system
	cat > "${destination}"/usr/sbin/rk817-input-limit <<- 'EOT'
		#!/bin/sh
		# Raise the RK817 charger input current limit (PMIC_CHRG_IN, 0xe5) to
		# Pine64's Android value; mainline leaves the reset default 0xc8.
		modprobe i2c-dev 2> /dev/null
		/usr/sbin/i2cset -f -y 0 0x20 0xe5 0xdf
		v=$(/usr/sbin/i2cget -f -y 0 0x20 0xe5)
		echo "rk817-input-limit: PMIC_CHRG_IN=$v" > /dev/kmsg
		[ "$v" = 0xdf ]
	EOT
	chmod 755 "${destination}"/usr/sbin/rk817-input-limit
	cat > "${destination}"/usr/lib/systemd/system/rk817-input-limit.service <<- EOT
		[Unit]
		Description=RK817: raise the charger input current limit (VCC_SYS power path)
		DefaultDependencies=no
		After=systemd-modules-load.service
		Before=systemd-udev-trigger.service sysinit.target

		[Service]
		Type=oneshot
		ExecStart=/usr/sbin/rk817-input-limit

		[Install]
		WantedBy=sysinit.target
	EOT
}

function post_family_tweaks__quartz64_zero_enable_rk817_input_limit() {
	display_alert "$BOARD" "Enabling RK817 input current limit service" "info"
	chroot_sdcard systemctl --no-reload enable rk817-input-limit.service
}

function post_family_tweaks_bsp__quartz64_zero_bluetooth() {
	display_alert "$BOARD" "Installing AIC8800 Bluetooth service" "info"
	mkdir -p "${destination}"/usr/lib/systemd/system
	cat > "${destination}"/usr/lib/systemd/system/aic8800-bluetooth.service <<- EOT
		[Unit]
		Description=AIC8800DC Bluetooth (UART HCI on ttyS1)
		After=sys-subsystem-net-devices-wlan0.device bluetooth.service
		Wants=sys-subsystem-net-devices-wlan0.device bluetooth.service

		[Service]
		Type=simple
		ExecStartPre=/usr/sbin/modprobe aic8800_btlpm_sdio
		ExecStartPre=/usr/sbin/rfkill unblock bluetooth
		ExecStart=/usr/bin/hciattach -n -s 1500000 /dev/ttyS1 any 1500000 flow nosleep
		Restart=on-failure
		RestartSec=2

		[Install]
		WantedBy=multi-user.target
	EOT
}

function post_family_tweaks__quartz64_zero_enable_bluetooth() {
	display_alert "$BOARD" "Enabling AIC8800 Bluetooth service" "info"
	chroot_sdcard systemctl --no-reload enable aic8800-bluetooth.service
}

# Mainline U-Boot. The board DT, -u-boot.dtsi and defconfig are plain files in
# patch/u-boot/v2026.10/{dt_upstream_rockchip,dt_uboot,defconfig}; only the
# RK817 input-limit change is a patch (board_quartz64-zero).
function post_family_config__quartz64_zero_use_mainline_uboot() {
	display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"

	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
	declare -g BOOTBRANCH="tag:v2026.10"
	declare -g BOOTPATCHDIR="v2026.10"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"

	# Disable stuff from rockchip64_common; we're using binman here which does all the work already
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# Just use the binman-provided u-boot-rockchip.bin, which is ready-to-go
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
