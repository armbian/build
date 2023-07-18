# Amlogic S905X3 quad core 4GB RAM SoC GBE USB3 SPI 2 x SATA
BOARD_NAME="Odroid HC4"
BOARDFAMILY="meson-sm1"
BOARD_MAINTAINER=""
BOOTCONFIG="odroid-c4_defconfig" # But also 'odroid-hc4_defconfig', see below at UBOOT_TARGET_MAP
KERNEL_TARGET="current,edge"
FULL_DESKTOP="no"
SERIALCON="ttyAML0"
BOOT_FDT_FILE="amlogic/meson-sm1-odroid-hc4.dtb"
PACKAGE_LIST_BOARD="mtd-utils lm-sensors fancontrol" # SPI, sensors, manual fan control via 'pwmconfig'

# Newer u-boot for the HC4. There's patches in `board_odroidhc4` for the defconfigs used in the UBOOT_TARGET_MAP below.
BOOTBRANCH_BOARD="tag:v2023.01"
BOOTPATCHDIR="v2023.01"

# We build u-boot twice: odroid-hc4_sd_defconfig config for SD cards, and HC4 (with SATA/PCI/SPI) config for SPI.
# Go look at the related patches for speculations on why.
UBOOT_TARGET_MAP="
odroid-hc4_sd_defconfig u-boot-dtb.img;;u-boot.bin.sd.bin:u-boot.bin u-boot-dtb.img
odroid-hc4_defconfig u-boot-dtb.img;;u-boot.bin:u-boot-spi.bin
"

# The SPI version (u-boot-spi.bin, built from odroid-hc4_defconfig above) is then used by nand-sata-install
function write_uboot_platform_mtd() {
	dd if=$1/u-boot-spi.bin of=/dev/mtdblock0
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
