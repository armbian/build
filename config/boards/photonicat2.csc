# Rockchip RK3576 SoC octa core 4-16GB LPDDR5 RAM SoC 2x GbE eMMC USB3 HDMI WIFI

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

# Ensure common USB modem drivers are auto-loaded in the built image
function post_family_tweaks__photonicat2() {
	display_alert "$BOARD" "Installing Photonicat2 modem module list" "info"
	mkdir -p "${destination}"/etc/modprobe.d
	mkdir -p "${destination}"/etc/modules-load.d

	# Modules that are commonly required for USB cellular modems and WWAN devices.
	# Adjust this list if you know your modem needs a different driver.
	cat > "${destination}"/etc/modules-load.d/photonicat2-modems.conf <<- EOT
	cdc-wdm
	qmi_wwan
	cdc_mbim
	cdc_ncm
	option
	usbserial
	EOT

	return 0
}

# Set PHOTONICAT_PM driver to module for Photonicat2 kernel builds
# This hook runs during kernel config (see kernel-config.sh call_extensions_kernel_config)
function custom_kernel_config__photonicat2() {
	kernel_config_modifying_hashes+=("photonicat2-photonicat-pm")
	if [[ -f .config ]]; then
		# Use kernel's scripts/config if available to set tristate to 'm'
		if [[ -x scripts/config ]]; then
			# set PHOTONICAT_PM to built-in (y)
			./scripts/config --set-val PHOTONICAT_PM y || true
		else
			# fallback: sed replace - best effort (olddefconfig will validate later)
			sed -i 's/^CONFIG_PHOTONICAT_PM=.*/CONFIG_PHOTONICAT_PM=y/' .config || true
			# ensure entry exists
			if ! grep -q '^CONFIG_PHOTONICAT_PM=' .config; then
				echo 'CONFIG_PHOTONICAT_PM=y' >> .config
			fi
		fi
	fi
	return 0
}
