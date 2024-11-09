# Amlogic S905X3 quad core 4GB RAM SoC GBE USB3 SPI 2 x SATA
BOARD_NAME="Odroid HC4"
BOARDFAMILY="meson-sm1"
BOARD_MAINTAINER="igorpecovnik"
BOOTCONFIG="odroid-c4_defconfig" # for the SD card; but also 'odroid-hc4_defconfig', see below at pre_config_uboot_target
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="simpledrm" # SimpleDRM conflicts with Panfrost
FULL_DESKTOP="no"
SERIALCON="ttyAML0"
BOOT_FDT_FILE="amlogic/meson-sm1-odroid-hc4.dtb"
PACKAGE_LIST_BOARD="lm-sensors fancontrol" # SPI, sensors, manual fan control via 'pwmconfig'

# Newer u-boot for the HC4. There's patches in `board_odroidhc4` for the defconfigs used in the UBOOT_TARGET_MAP below.
BOOTBRANCH_BOARD="tag:v2024.04"
BOOTPATCHDIR="v2024.04"

# We build u-boot twice: C4 config for SD cards, and HC4 (with SATA/PCI/SPI) config for SPI.
UBOOT_TARGET_MAP="
armbian_target=sd u-boot-dtb.img;;u-boot.bin.sd.bin:u-boot.bin u-boot-dtb.img
armbian_target=spi u-boot-dtb.img;;u-boot.bin:u-boot-spi.bin
"

# The SPI version (u-boot-spi.bin, built from odroid-hc4_defconfig above) is then used by nand-sata-install / armbian-install
function write_uboot_platform_mtd() {
	declare -a extra_opts_flashcp=("--verbose")
	if flashcp -h | grep -q -e '--partition'; then
		echo "Confirmed flashcp supports --partition -- read and write only changed blocks." >&2
		extra_opts_flashcp+=("--partition")
	else
		echo "flashcp does not support --partition, will write full SPI flash blocks." >&2
	fi
	flashcp "${extra_opts_flashcp[@]}" "${1}/u-boot-spi.bin" /dev/mtd0
}

# FIP blobs; the C4 & HC4 fip blobs are actually the same, still LE carries both.
function post_uboot_custom_postprocess__odroid_hc4_uboot() {
	display_alert "Signing u-boot FIP" "${BOARD}" "info"
	uboot_g12_postprocess "${SRC}"/cache/sources/amlogic-boot-fip/odroid-hc4 g12a
}

# switch defconfig according to target, so we can still use the same post_config_uboot_target for both.
function pre_config_uboot_target__odroidhc4_defconfig_per_target() {
	case "${target_make}" in
		"armbian_target=spi "*)
			BOOTCONFIG="odroid-hc4_defconfig"
			;;
		"armbian_target=sd "*)
			BOOTCONFIG="odroid-c4_defconfig"
			;;
		*)
			exit_with_error "Unknown target_make: '${target_make}', unknown BOOTCONFIG."
			;;
	esac
	display_alert "setting BOOTCONFIG for target" "${target_make}: '${BOOTCONFIG}'" "info"
}

# Enable extra u-boot .config options, this way we avoid patching defconfig
function post_config_uboot_target__extra_configs_for_odroid_hc4() {
	display_alert "u-boot for ${BOARD}" "u-boot: enable preboot & pci+usb start in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'run boot_pci_enum; usb start'" # double quotes required due to run_host_command_logged's quirks

	display_alert "u-boot for ${BOARD}" "u-boot: enable EFI debugging command" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	## WAIT ## display_alert "u-boot for ${BOARD}" "u-boot: disable EFI Video Framebuffer" "info"
	## WAIT ## run_host_command_logged scripts/config --disable CONFIG_VIDEO_DT_SIMPLEFB # "Enables the code to pass the framebuffer to the kernel as a simple framebuffer in the device tree."
	## WAIT ## # CONFIG_VIDEO_EFI is unrelated: its about _using_ an EFI framebuffer when booted by an EFI-capable bootloader earlier in the chain. Not about _providing_ an EFI framebuffer. That's simplefb.
	## WAIT ## # CONFIG_FDT_SIMPLEFB seems to be rpi-specific and 100% unrelated here

	display_alert "u-boot for ${BOARD}" "u-boot: enable I2C support" "info"
	run_host_command_logged scripts/config --enable CONFIG_DM_I2C
	run_host_command_logged scripts/config --enable CONFIG_SYS_I2C_MESON
	run_host_command_logged scripts/config --enable CONFIG_CMD_I2C

	display_alert "u-boot for ${BOARD}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK
}

# @TODO: this is no longer needed in `edge` branch -- Neil has sent a patch with a trip for the cooling map in the DT - also doesn't hurt.
function post_family_tweaks__config_odroidhc4_fancontrol() {
	display_alert "Configuring fancontrol" "for Odroid HC4" "info"
	cat <<- FANCONTROL > "${SDCARD}"/etc/fancontrol
		# Default config for the Odroid HC4 -- adjust to your needs (MINTEMP=40)
		INTERVAL=10
		DEVPATH=hwmon0=devices/virtual/thermal/thermal_zone0 hwmon2=devices/platform/pwm-fan
		DEVNAME=hwmon0=cpu_thermal hwmon2=pwmfan
		FCTEMPS=hwmon2/pwm1=hwmon0/temp1_input
		FCFANS= hwmon2/pwm1=hwmon2/fan1_input
		MINTEMP=hwmon2/pwm1=40
		MAXTEMP=hwmon2/pwm1=60
		MINSTART=hwmon2/pwm1=150
		MINSTOP=hwmon2/pwm1=30
		MAXPWM=hwmon2/pwm1=180
	FANCONTROL
	chroot_sdcard systemctl enable fancontrol.service
}
