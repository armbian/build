# Amlogic S922X hexa core 2GB/4GB RAM SoC 1.8-2.4Ghz eMMC GBE USB3 SPI RTC
BOARD_NAME="Odroid N2"
BOARD_VENDOR="hardkernel"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER="NicoD-SBC"
INTRODUCED="2019"
KERNEL_TARGET="current,edge"
KERNEL_TEST_TARGET="current"
MODULES_BLACKLIST="simpledrm" # SimpleDRM conflicts with Panfrost
FULL_DESKTOP="yes"
FORCE_BOOTSCRIPT_UPDATE="yes"
BOOT_LOGO="desktop"
BOOTCONFIG="odroid-n2_defconfig" # For mainline uboot

# Enable btrfs support in u-boot
enable_extension "uboot-btrfs"
enable_extension "watchdog"

# Newer u-boot for the N2/N2+
BOOTBRANCH_BOARD="tag:v2026.04"
BOOTPATCHDIR="v2026.04"

# Enable writing u-boot to SPI on the N2(+) for current and edge
# @TODO: replace this with an overlay, after meson64 overlay revamp
# To enable the SPI NOR the -spi .dtb is required, because eMMC shares a pin with SPI on the N2(+). To use it:
# fdtfile=amlogic/meson-g12b-odroid-n2-plus-spi.dtb # in armbianEnv.txt and reboot, then run nand-sata-install
UBOOT_TARGET_MAP="u-boot-dtb.img;;u-boot.bin.sd.bin:u-boot.bin u-boot-dtb.img u-boot.bin:u-boot-spi.bin"
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

# MAX might be different for N2/N2+, for now use N2+'s
# @TODO: remove? cpufreq is not used anymore, instead DT should be patched
CPUMIN=1000000
CPUMAX=2400000
GOVERNOR=performance # some people recommend performance to avoid random hangs after 24+ hours running.

# U-boot has detection code for the ODROID boards.
#    https://github.com/u-boot/u-boot/blob/v2021.04/board/amlogic/odroid-n2/odroid-n2.c#L35-L106
# Unfortunately it uses n2_plus instead of n2-plus as the Kernel expects it.
#    So there is a hack at and around config/bootscripts/boot-meson64.cmd L90
# If needed (eg for extlinux) you can specify the N2/N2+/ DTB in BOOT_FDT_FILE, example for the N2+:
# BOOT_FDT_FILE="amlogic/meson-g12b-odroid-n2-plus.dtb"

# FIP blobs; FIP trees 'odroid-n2-plus' and 'odroid-n2' are identical.
function post_uboot_custom_postprocess__odroid_hc4_uboot() {
	display_alert "Signing u-boot FIP" "${BOARD}" "info"
	uboot_g12_postprocess "$SRC"/cache/sources/amlogic-boot-fip/odroid-n2 g12b
}

# Enable extra u-boot .config options, this way we avoid patching defconfig
function post_config_uboot_target__extra_configs_for_odroid_hc4() {
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable preboot & flash user LED in preboot" "info"
	run_host_command_logged scripts/config --enable CONFIG_USE_PREBOOT
	run_host_command_logged scripts/config --set-str CONFIG_PREBOOT "'led n2:blue on; sleep 0.1; led n2:blue off'" # double quotes required due to run_host_command_logged's quirks

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable EFI debugging commands" "info"
	run_host_command_logged scripts/config --enable CMD_EFIDEBUG
	run_host_command_logged scripts/config --enable CMD_NVEDIT_EFI

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable more compression support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LZO
	run_host_command_logged scripts/config --enable CONFIG_BZIP2
	run_host_command_logged scripts/config --enable CONFIG_ZSTD

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable gpio LED support" "info"
	run_host_command_logged scripts/config --enable CONFIG_LED
	run_host_command_logged scripts/config --enable CONFIG_LED_GPIO

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable networking cmds" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_NFS
	run_host_command_logged scripts/config --enable CONFIG_CMD_WGET
	run_host_command_logged scripts/config --enable CONFIG_CMD_DNS
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP
	run_host_command_logged scripts/config --enable CONFIG_PROT_TCP_SACK

	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: enable LWIP (new networking stack)" "info"
	run_host_command_logged scripts/config --enable CONFIG_CMD_MII
	run_host_command_logged scripts/config --enable CONFIG_NET_LWIP
}
