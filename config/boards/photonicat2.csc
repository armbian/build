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
		"CONFIG_SERIAL_DEV_BUS=y"
		"CONFIG_SERIAL_DEV_CTRL_TTYPORT=y"
		"CONFIG_PHOTONICAT_PM=y"
		"CONFIG_PHOTONICAT_USB_WDT=m"
	)
	if [[ -f .config ]]; then
		kernel_config_set_y SERIAL_DEV_BUS
		kernel_config_set_y SERIAL_DEV_CTRL_TTYPORT
		kernel_config_set_y PHOTONICAT_PM
		kernel_config_set_m PHOTONICAT_USB_WDT
	fi
}

# Enable PWM subsystem for backlight, beeper, voltage regulation, LEDs
function custom_kernel_config__photonicat2_pwm() {
	kernel_config_modifying_hashes+=(
		"CONFIG_PWM=y"
		"CONFIG_ROCKCHIP_MFPWM=y"
		"CONFIG_PWM_ROCKCHIP_V4=y"
		"CONFIG_ROCKCHIP_PWM_CAPTURE=y"
		"CONFIG_INPUT_PWM_BEEPER=y"
		"CONFIG_REGULATOR_PWM=y"
		"CONFIG_LEDS_PWM=y"
	)
	if [[ -f .config ]]; then
		kernel_config_set_y PWM
		kernel_config_set_y ROCKCHIP_MFPWM
		kernel_config_set_y PWM_ROCKCHIP_V4
		kernel_config_set_y ROCKCHIP_PWM_CAPTURE
		kernel_config_set_y INPUT_PWM_BEEPER
		kernel_config_set_y REGULATOR_PWM
		kernel_config_set_y LEDS_PWM
	fi
}

# Enable LCD backlight control (depends on PWM subsystem)
function custom_kernel_config__photonicat2_backlight() {
	kernel_config_modifying_hashes+=(
		"CONFIG_BACKLIGHT_CLASS_DEVICE=y"
		"CONFIG_BACKLIGHT_PWM=y"
		"CONFIG_BACKLIGHT_GPIO=y"
	)
	if [[ -f .config ]]; then
		kernel_config_set_y BACKLIGHT_CLASS_DEVICE
		kernel_config_set_y BACKLIGHT_PWM
		kernel_config_set_y BACKLIGHT_GPIO
	fi
}

# Enable STMMAC ethernet drivers for the 2x RJ45 Gigabit Ethernet ports
function custom_kernel_config__photonicat2_ethernet() {
	kernel_config_modifying_hashes+=(
		"CONFIG_STMMAC_ETH=y"
		"CONFIG_STMMAC_PLATFORM=y"
	)
	if [[ -f .config ]]; then
		kernel_config_set_y STMMAC_ETH
		kernel_config_set_y STMMAC_PLATFORM
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

# Enable WWAN subsystem and USB modem drivers for M.2 B-Key cellular modules over USB
# Supports 4G/5G modems (e.g., Quectel RM520N-GL) via QMI, MBIM, NCM
function custom_kernel_config__photonicat2_usb_modem() {
	kernel_config_modifying_hashes+=(
		"CONFIG_USB_WDM=m"
		"CONFIG_USB_NET_QMI_WWAN=m"
		"CONFIG_USB_NET_CDC_MBIM=m"
		"CONFIG_USB_NET_CDC_NCM=m"
		"CONFIG_USB_SERIAL=m"
		"CONFIG_USB_SERIAL_OPTION=m"
		"CONFIG_USB_SERIAL_WWAN=m"
		"CONFIG_USB_SERIAL_QUALCOMM=m"
		"CONFIG_QCOM_QMI_HELPERS=m"
	)
	if [[ -f .config ]]; then
		kernel_config_set_m USB_WDM
		kernel_config_set_m USB_NET_QMI_WWAN
		kernel_config_set_m USB_NET_CDC_MBIM
		kernel_config_set_m USB_NET_CDC_NCM
		kernel_config_set_m USB_SERIAL
		kernel_config_set_m USB_SERIAL_OPTION
		kernel_config_set_m USB_SERIAL_WWAN
		kernel_config_set_m USB_SERIAL_QUALCOMM
		kernel_config_set_m QCOM_QMI_HELPERS
	fi
}

# Enable PCIe WiFi support (Qualcomm ath11k for QCNFA765/wcn6855)
# MHI_BUS and QRTR must be built-in to avoid race condition with ath11k probe
function custom_kernel_config__photonicat2_pcie_wifi() {
	kernel_config_modifying_hashes+=(
		"CONFIG_ATH11K=m"
		"CONFIG_ATH11K_PCI=m"
		"CONFIG_MHI_BUS=y"
		"CONFIG_MHI_BUS_PCI_GENERIC=m"
		"CONFIG_QRTR=y"
		"CONFIG_QRTR_MHI=y"
		"CONFIG_QRTR_TUN=m"
	)
	if [[ -f .config ]]; then
		kernel_config_set_m ATH11K
		kernel_config_set_m ATH11K_PCI
		kernel_config_set_y MHI_BUS
		kernel_config_set_m MHI_BUS_PCI_GENERIC
		kernel_config_set_y QRTR
		kernel_config_set_y QRTR_MHI
		kernel_config_set_m QRTR_TUN
	fi
}

