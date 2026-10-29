# Rockchip RK3576 SoC octa core 4GB SoC 2xGBe eMMC USB3 NvME CAN RS485 mini-PCIe
BOARD_NAME="reComputer RK3576 Industrial"
BOARDFAMILY="rk35xx"
BOOT_SOC="rk3576"
BOARD_MAINTAINER="Pillar1989"
BOARD_VENDOR="seeed-studio"
INTRODUCED="2026"
BOOTCONFIG="recomputer-rk3576-industrial_defconfig"
KERNEL_TARGET="vendor"
KERNEL_TEST_TARGET="vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3576-recomputer-industrial.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
OTA_ENABLE="yes"
SERIALCON="ttyFIQ0,ttyGS0"
BT_UART="/dev/ttyS4"
# No AIC8800 / Morse silicon on this board: WiFi/BT is WQ9201S (DKMS below).
SEEED_AIC_BLUEZ_ENABLE="no"
SEEED_MORSE_ENABLE="no"
# Open-source panfrost driver + Mesa userspace for the Mali-G52. "mali"
# (closed blob) would need MALI_USE_SYSTEM_GBM=yes.
RECOMPUTER_GPU_STACK="panfrost"
PACKAGE_LIST_BOARD="net-tools rfkill pulseaudio-module-bluetooth fail2ban"

source "${SRC}/config/sources/vendors/seeed-studio/recomputer-rk35xx-common.inc"

function post_family_config__recomputer_rk3576_industrial_use_seeed_bootscript() {
	display_alert "$BOARD" "Using Seeed bootscript: boot-seeed-rk35xx.cmd -> boot.cmd" "info"
	declare -g BOOTSCRIPT="boot-seeed-rk35xx.cmd:boot.cmd"
}

# EEPROM on module I2C2 @0x50
function post_family_tweaks__recomputer_rk3576_industrial_eeprom_bus() {
	echo "eeprom_i2c_bus=2" >> "${SDCARD}/boot/armbianEnv.txt"
	echo "eeprom_i2c_addr=0x50" >> "${SDCARD}/boot/armbianEnv.txt"
}

# DKMS packages below build in chroot against the image kernel; ship headers.
function post_family_config__recomputer_rk3576_industrial_kernel_headers() {
	declare -g INSTALL_HEADERS="yes"
}

# Install fixed btattach (bluez-btattach) from Seeed APT; drop when the distro
# ships a fixed binary (glibc 2.42+ toolchain turns -S baud into B0 hangup —
# hits wq9201s-bt-attach's `btattach -S 1500000` on resolute-class releases).
function post_install_kernel_debs__recomputer_rk3576_industrial_install_bluez_btattach() {
	if [[ "${SEEED_BLUEZ_BTATTACH_ENABLE:-"${SEEED_DEFAULT_ENABLE:-"yes"}"}" == "no" ]]; then
		display_alert "Skipping bluez-btattach workaround" "SEEED_BLUEZ_BTATTACH_ENABLE=no" "info"
		return 0
	fi

	display_alert "Installing bluez-btattach (workaround for btattach baud bug)" "bluez-btattach" "info"

	seeed_recomputer_install_from_apt bluez-btattach

	display_alert "bluez-btattach installed" "bluez-btattach" "info"
}

# WQ9201S WiFi/BT driver: DKMS deb from Seeed APT, built in chroot against the image kernel.
function post_install_kernel_debs__recomputer_rk3576_industrial_install_wq9201s() {
	display_alert "Installing WQ9201S WiFi/BT (DKMS, builds in chroot)" "wq9201s" "info"
	chroot_sdcard_apt_get_install gcc
	seeed_recomputer_install_from_apt wq9201s-wifi-bt-dkms
	if_error_find_files_sdcard+=("/var/lib/dkms/wq9201s*/*/build/*.log")
	display_alert "WQ9201S WiFi/BT installed" "wq9201s" "info"
}

# PCIe NPU accelerator card (RK1820 M.2): pcie-rkep DKMS deb from Seeed APT.
function post_install_kernel_debs__recomputer_rk3576_industrial_install_pcie_rkep() {
	display_alert "Installing pcie-rkep NPU card driver (DKMS, builds in chroot)" "pcie-rkep" "info"
	chroot_sdcard_apt_get_install gcc
	seeed_recomputer_install_from_apt pcie-rkep-dkms
	if_error_find_files_sdcard+=("/var/lib/dkms/pcie-rkep*/*/build/*.log")
	display_alert "pcie-rkep NPU card driver installed" "pcie-rkep" "info"
}

# Maxio MAE0621A PHY (GMAC1): the generic C22 driver runs the link; this DKMS
# module adds the RJ45 LED programming (and a fixup against MDIO bind races).
# autoload fails via udev, hence the modules-load entry it ships.
function post_install_kernel_debs__recomputer_rk3576_industrial_install_maxio_phy() {
	display_alert "Installing Maxio MAE0621A PHY driver (DKMS, builds in chroot)" "maxio-phy-dkms" "info"
	chroot_sdcard_apt_get_install gcc
	seeed_recomputer_install_from_apt maxio-phy-dkms
	if_error_find_files_sdcard+=("/var/lib/dkms/maxio-phy*/*/build/*.log")
	display_alert "Maxio MAE0621A PHY driver installed" "maxio-phy-dkms" "info"
}

# Audio naming: HDMI, DP0, ES8311 (node names per rk3576-recomputer-industrial.dts)
function post_family_tweaks__recomputer_rk3576_industrial_naming_audios() {
	display_alert "$BOARD" "Renaming recomputer-rk3576-industrial audios" "info"

	mkdir -p "${SDCARD}/etc/udev/rules.d/"
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-hdmi-sound", ENV{SOUND_DESCRIPTION}="HDMI Audio"' > "${SDCARD}/etc/udev/rules.d/90-naming-audios.rules"
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-dp0-sound", ENV{SOUND_DESCRIPTION}="DP0 Audio"' >> "${SDCARD}/etc/udev/rules.d/90-naming-audios.rules"
	echo 'SUBSYSTEM=="sound", ENV{ID_PATH}=="platform-es8311-sound", ENV{SOUND_DESCRIPTION}="ES8311 Audio"' >> "${SDCARD}/etc/udev/rules.d/90-naming-audios.rules"
}

# Disable suspend and hibernation
function post_family_tweaks__recomputer_rk3576_industrial_disable_suspend() {
	display_alert "$BOARD" "Disabling suspend and hibernation" "info"

	mkdir -p "${SDCARD}/etc/systemd/sleep.conf.d"
	cat > "${SDCARD}/etc/systemd/sleep.conf.d/nosuspend.conf" <<-'EOF'
		[Sleep]
		AllowSuspend=no
		AllowHibernation=no
		AllowSuspendThenHibernate=no
		AllowHybridSleep=no
	EOF
}

# Mali GPU access: add gdm to render+video groups (common.inc misses Ubuntu's "gdm").
function post_family_tweaks__recomputer_rk3576_industrial_gdm_gpu_groups() {
	chroot_sdcard usermod -aG render,video gdm 2> /dev/null || true
	chroot_sdcard usermod -aG render,video Debian-gdm 2> /dev/null || true
}

# Serial console login: cap plymouth-quit-wait at 2s (headless login fix).
function post_family_tweaks__recomputer_rk3576_industrial_plymouth_quit_timeout() {
	mkdir -p "${SDCARD}/etc/systemd/system/plymouth-quit-wait.service.d"
	printf "[Service]\nTimeoutSec=2\n" > "${SDCARD}/etc/systemd/system/plymouth-quit-wait.service.d/timeout.conf"
}

# External PCF8563T watchdog on I2C3 (nxp,timer-watchdog, INT wired to the SoC
# reset line): have systemd (PID 1) own /dev/watchdog and ping it at half the
# timeout. RuntimeWatchdogSec=30 bounds hang-detection latency at a 15 s ping
# cadence (keep in sync with the kernel DTS timeout-sec). The external chip
# keeps counting across the SoC reset and nobody
# pings it until the next boot's PID 1 re-arms /dev/watchdog, so
# RebootWatchdogSec must cover reboot + U-Boot + kernel boot (~10 s here) with
# margin -- 30 s, still well below upstream's 10-minute default.
function post_family_tweaks__recomputer_rk3576_industrial_watchdog_systemd() {
	display_alert "$BOARD" "Enabling systemd hardware watchdog (PCF8563T)" "info"

	mkdir -p "${SDCARD}/etc/systemd/system.conf.d"
	cat > "${SDCARD}/etc/systemd/system.conf.d/watchdog.conf" <<-'EOF'
		[Manager]
		RuntimeWatchdogSec=30
		RebootWatchdogSec=30
	EOF
}
