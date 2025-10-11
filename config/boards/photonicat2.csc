# Rockchip RK3576 octa core 4-16GM 2x GbE eMMC HDMI WiFi USB3 3x M.2 (B/E/M-Key)

BOARD_NAME="Photonicat2"
BOARDFAMILY="rk35xx"
BOOT_SOC="rk3576"
BOOTCONFIG="photonicat2-rk3576_defconfig"
KERNEL_TARGET="edge"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3576-photonicat2.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
ENABLE_EXTENSIONS="radxa-aic8800"
AIC8800_TYPE="usb"

# Enable Photonicat2 power management driver
function custom_kernel_config__photonicat2_pm() {
	kernel_config_modifying_hashes+=(
		"CONFIG_PHOTONICAT_PM=y"
	)
	if [[ -f .config ]]; then
		kernel_config_set_y PHOTONICAT_PM
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
	add_packages_to_image "modemmanager"    # Essential for cellular modem management
	add_packages_to_image "libqmi-utils"    # QMI protocol tools for Qualcomm-based modems
	add_packages_to_image "libmbim-utils"   # MBIM protocol tools for some modems
	add_packages_to_image "usb-modeswitch"  # Switches USB modems from storage mode to modem mode
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
