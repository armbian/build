# Rockchip RK3576 octa core 4-16GB 2x GbE eMMC HDMI WiFi USB3 3x M.2 (B/E/M-Key)

BOARD_NAME="Photonicat2"
BOARDFAMILY="rk35xx"
BOOT_SOC="rk3576"
BOOTCONFIG="photonicat2-rk3576_defconfig"
KERNEL_TARGET="edge"
FULL_DESKTOP="no"
BOOT_FDT_FILE="rockchip/rk3576-photonicat2.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
BOARD_FIRMWARE_INSTALL="-full"
ENABLE_EXTENSIONS="radxa-aic8800"
AIC8800_TYPE="usb"

# Enable Photonicat2 power management and USB watchdog driver (requires SERIAL_DEV_BUS)
function custom_kernel_config__photonicat2_pm() {
	kernel_config_modifying_hashes+=(
		"CONFIG_PHOTONICAT_PM=y"
		"CONFIG_PHOTONICAT_USB_WDT=m"
	)
	if [[ -f .config ]]; then
		kernel_config_set_y PHOTONICAT_PM
		kernel_config_set_m PHOTONICAT_USB_WDT
	fi
}

# Enable PWM subsystem for backlight, beeper, voltage regulation, LEDs
function custom_kernel_config__photonicat2_pwm() {
	kernel_config_modifying_hashes+=(
		"CONFIG_PWM_ROCKCHIP_V4=y"
	)
	if [[ -f .config ]]; then
		kernel_config_set_y PWM_ROCKCHIP_V4
	fi
}

# Add cellular modem support packages
function post_family_config__photonicat2_modem_packages() {
	display_alert "$BOARD" "Adding cellular modem packages" "info"
	add_packages_to_image "modemmanager"
	add_packages_to_image "libqmi-utils"
	add_packages_to_image "libmbim-utils"
	add_packages_to_image "usb-modeswitch"
	add_packages_to_image "libxml2-utils"
}
