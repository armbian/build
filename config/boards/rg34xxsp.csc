# Anbernic RG34XXSP Gaming Handheld
# Allwinner H700 quad core 2GB RAM SoC WiFi Bluetooth clamshell handheld
#
# EXTENDING SUPPORT TO OTHER ANBERNIC DEVICES:
# This implementation can be extended to support other Anbernic handhelds supported by ROCKNIX.
# Reference: repos_reference/rocknix-distribution/
#
# DEVICE TREE FILES IMPLEMENTED:
# - sun50i-h700-anbernic.dtsi (base H700 Anbernic support)
# - sun50i-h700-anbernic-rg35xx-sp.dts (RG35XX-SP base - inherited by RG34XXSP)
# - sun50i-h700-anbernic-rg34xx-sp.dts (RG34XXSP specific)
# - sun50i-h700-anbernic-rg35xx-2024.dts (RG35XX 2024 variant)
#
# DEVICE TREE FILES NOT YET IMPLEMENTED (available in ROCKNIX):
# Copy from: repos_reference/rocknix-distribution/build.ROCKNIX-H700.arm/linux-6.15.2/arch/arm64/boot/dts/allwinner/
# - sun50i-h700-anbernic-rg35xx-h.dts (RG35XX-H horizontal variant)
# - sun50i-h700-anbernic-rg35xx-plus.dts (RG35XX Plus)
# - sun50i-h700-anbernic-rg40xx-h.dts (RG40XX-H)
# - sun50i-h700-anbernic-rg40xx-v.dts (RG40XX-V)
#
# PANEL FIRMWARE FILES:
# Implemented: anbernic,rg34xx-sp-panel.panel (copy from: repos_reference/rocknix-distribution/packages/kernel/firmware/kernel-firmware/extra-firmware/panels/)
# Available but not implemented:
# - anbernic,rg35xx-sp-panel.panel
# - anbernic,rg35xx-h-panel.panel  
# - anbernic,rg35xx-plus-panel.panel
# - anbernic,rg40xx-panel.panel
#
# TO ADD SUPPORT FOR ANOTHER ANBERNIC DEVICE:
# 1. Copy device tree file from ROCKNIX to: kernel-patches-tracking/arch/arm64/boot/dts/allwinner/
# 2. Copy panel firmware to: packages/bsp/anbernic/panel_firmware/
# 3. Create new board .csc file similar to this one
# 4. Update BOOT_FDT_FILE and device-specific settings
# 5. The anbernic-display-fix.service and basic-lid-screen-off.service should work across devices
#
# ROCKNIX DRIVER PATCHES ALREADY APPLIED:
# - H700-anbernic-rg34xx-sp-pwm-panel.patch (PWM driver, panel-mipi driver, DE33 support, TCON fixes)
# - These patches provide base H700 Anbernic support and should work for all H700-based Anbernic devices

BOARD_NAME="Anbernic RG34XXSP"
BOARD_MAINTAINER="mitswan"
BOARDFAMILY="sun50iw9"
KERNEL_TARGET="current"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="sun50i-h700-anbernic-rg34xx-sp.dtb"
FORCE_BOOTSCRIPT_UPDATE="yes"
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
SERIALCON="ttyS0"

BOOTPATCHDIR="v2025-sunxi"
BOOTBRANCH="tag:v2025.04"
BOOTCONFIG="anbernic_rg34xx_sp_h700_defconfig"

enable_extension "uwe5622-allwinner"


function post_family_tweaks_bsp__rg34xxsp_firmware() {
	display_alert "$BOARD" "Installing panel firmware and display services" "info"
	
	# Install panel firmware files
	mkdir -p "${destination}"/lib/firmware/panels/
	cp -fr $SRC/packages/bsp/anbernic/panel_firmware/* "${destination}"/lib/firmware/panels/
	
	# Install userspace scripts
	mkdir -p "${destination}"/usr/local/bin/
	cp -fv $SRC/packages/bsp/anbernic/systemd_services/basic-lid-screen-off-monitor "${destination}"/usr/local/bin/
	chmod +x "${destination}"/usr/local/bin/basic-lid-screen-off-monitor
	cp -fv $SRC/packages/bsp/anbernic/systemd_services/anbernic-usb-otg-manager "${destination}"/usr/local/bin/
	chmod +x "${destination}"/usr/local/bin/anbernic-usb-otg-manager
	
	# Copy systemd services
	mkdir -p "${destination}"/etc/systemd/system/
	cp -fv $SRC/packages/bsp/anbernic/systemd_services/anbernic-display-fix.service "${destination}"/etc/systemd/system/
	cp -fv $SRC/packages/bsp/anbernic/systemd_services/basic-lid-screen-off.service "${destination}"/etc/systemd/system/
	cp -fv $SRC/packages/bsp/anbernic/systemd_services/anbernic-usb-otg-manager.service "${destination}"/etc/systemd/system/
}

function post_family_tweaks__rg34xxsp_enable_services() {
	display_alert "$BOARD" "Enabling hardware services" "info"
	# Enable the display fix service (required for display to work)
	chroot_sdcard systemctl enable anbernic-display-fix.service
	
	# Enable USB OTG management service (required for USB OTG functionality)
	# chroot_sdcard systemctl enable anbernic-usb-otg-manager.service
	
	# Note: basic-lid-screen-off.service is installed but not enabled
	# Users can enable it manually with: systemctl enable basic-lid-screen-off.service
}

