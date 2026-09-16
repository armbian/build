# Rockchip RK3576 octa core 4/8GB RAM SoC
BOARD_NAME="reComputer RK3576 Module Dev Kit"
BOARDFAMILY="seeed-rk3576"
BOOT_SOC="rk3576"
BOARD_MAINTAINER="Pillar1989"
BOARD_VENDOR="seeed-studio"
INTRODUCED="2026"
BOOTCONFIG="recomputer-rk3576-module-devkit_defconfig"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3576-recomputer-rk3576-module-devkit.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
OTA_ENABLE="yes"
SERIALCON="ttyFIQ0,ttyGS0"
BT_UART="/dev/ttyS4"
SEEED_AIC_BLUEZ_ENABLE="no"
SEEED_MORSE_ENABLE="no"
RECOMPUTER_GPU_STACK="panfrost"
MALI_USE_SYSTEM_GBM="yes"
PACKAGE_LIST_BOARD="net-tools rfkill pulseaudio-module-bluetooth fail2ban"

source "${SRC}/config/sources/vendors/seeed-studio/recomputer-rk35xx-common.inc"

function post_family_config__recomputer_rk3576_module_use_seeed_bootscript() {
	display_alert "$BOARD" "Using Seeed bootscript: boot-seeed-rk35xx.cmd -> boot.cmd" "info"
	declare -g BOOTSCRIPT="boot-seeed-rk35xx.cmd:boot.cmd"
}

# EEPROM on module I2C2 @0x50
function post_family_tweaks__recomputer_rk3576_module_eeprom_bus() {
	echo "eeprom_i2c_bus=2" >> "${SDCARD}/boot/armbianEnv.txt"
	echo "eeprom_i2c_addr=0x50" >> "${SDCARD}/boot/armbianEnv.txt"
}

# Install Mali-G52 userspace library for GPU hardware acceleration
# Kernel DDK is g25p0; g24p0 userspace library is ABI-compatible
function pre_install_distribution_specific__recomputer_rk3576_install_libmali() {
	if [[ "${RECOMPUTER_GPU_STACK:-mali}" == "panfrost" ]]; then
		display_alert "Skipping Mali GPU libraries" "Using Panfrost/Mesa userspace" "info"
		return 0
	fi

	display_alert "Installing Mali GPU libraries from APT repo" "libmali-g52" "info"

	seeed_recomputer_install_from_apt libmali-bifrost-g52-g24p0-x11-wayland-gbm

	display_alert "Mali GPU libraries installed successfully" "libmali-g52" "info"
}

# Install camera engine rkaiq for Rockchip ISP
function pre_install_distribution_specific__recomputer_rk3576_install_camera_engine() {
	display_alert "Installing camera engine from APT repo" "camera-engine-rkaiq" "info"

	seeed_recomputer_install_from_apt camera-engine-rkaiq-rk3576

	display_alert "Camera engine installed successfully" "camera-engine-rkaiq" "info"
}

# WQ9201S WiFi/BT driver: DKMS deb from Seeed APT, built in chroot against the image kernel.
function post_family_config__recomputer_rk3576_wq9201s_kernel_headers() {
	declare -g INSTALL_HEADERS="yes"
}

function post_install_kernel_debs__recomputer_rk3576_install_wq9201s() {
	display_alert "Installing WQ9201S WiFi/BT (DKMS, builds in chroot)" "wq9201s" "info"
	chroot_sdcard_apt_get_install gcc
	seeed_recomputer_install_from_apt wq9201s-wifi-bt-dkms
	if_error_find_files_sdcard+=("/var/lib/dkms/wq9201s*/*/build/*.log")
	display_alert "WQ9201S WiFi/BT installed" "wq9201s" "info"
}

# PCIe NPU accelerator card (RK1820 M.2): pcie-rkep DKMS deb from Seeed APT.
function post_install_kernel_debs__recomputer_rk3576_install_pcie_rkep() {
	display_alert "Installing pcie-rkep NPU card driver (DKMS, builds in chroot)" "pcie-rkep" "info"
	chroot_sdcard_apt_get_install gcc
	seeed_recomputer_install_from_apt pcie-rkep-dkms
	if_error_find_files_sdcard+=("/var/lib/dkms/pcie-rkep*/*/build/*.log")
	display_alert "pcie-rkep NPU card driver installed" "pcie-rkep" "info"
}

# Audio naming: HDMI0, DP0, ES8311
function post_family_tweaks__recomputer_rk3576_naming_audios() {
	display_alert "$BOARD" "Renaming recomputer-rk3576-module audios" "info"

	mkdir -p $SDCARD/etc/udev/rules.d/
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi0-sound", ENV{SOUND_DESCRIPTION}="HDMI0 Audio"' > $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8311-sound", ENV{SOUND_DESCRIPTION}="ES8311 Audio"' >> $SDCARD/etc/udev/rules.d/90-naming-audios.rules
}

# Disable suspend and hibernation
function post_family_tweaks__recomputer_rk3576_disable_suspend() {
	display_alert "$BOARD" "Disabling suspend and hibernation" "info"

	mkdir -p $SDCARD/etc/systemd/sleep.conf.d
	cat > $SDCARD/etc/systemd/sleep.conf.d/nosuspend.conf <<-'EOF'
		[Sleep]
		AllowSuspend=no
		AllowHibernation=no
		AllowSuspendThenHibernate=no
		AllowHybridSleep=no
	EOF
}

# Mali GPU access: add gdm to render+video groups (common.inc misses Ubuntu's "gdm").
function post_family_tweaks__recomputer_rk3576_gdm_gpu_groups() {
	chroot_sdcard usermod -aG render,video gdm 2> /dev/null || true
	chroot_sdcard usermod -aG render,video Debian-gdm 2> /dev/null || true
}

# Serial console login: cap plymouth-quit-wait at 2s (headless login fix).
function post_family_tweaks__recomputer_rk3576_plymouth_quit_timeout() {
	mkdir -p "${SDCARD}/etc/systemd/system/plymouth-quit-wait.service.d"
	printf "[Service]\nTimeoutSec=2\n" > "${SDCARD}/etc/systemd/system/plymouth-quit-wait.service.d/timeout.conf"
}
