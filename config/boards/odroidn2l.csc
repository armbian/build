# Amlogic S922X hexa core 2GB/4GB RAM SoC 1.8-2.4Ghz eMMC GBE USB3 SPI RTC
BOARD_NAME="Odroid N2L"
BOARDFAMILY="meson-g12b"
BOARD_MAINTAINER=""
KERNEL_TARGET="current,edge"
FULL_DESKTOP="yes"
FORCE_BOOTSCRIPT_UPDATE="yes"
BOOT_LOGO="desktop"
BOOTCONFIG="odroid-n2l_defconfig"
BOOTBRANCH_BOARD="tag:v2023.07.02"
BOOTPATCHDIR="v2023.07.02"
PACKAGE_LIST_BOARD="whiptail"

# MAX might be different for N2/N2+/N2L, for now use N2+'s
# @TODO: remove? cpufreq is not used anymore, instead DT should be patched
CPUMIN=1000000
CPUMAX=2400000
GOVERNOR=performance # some people recommend performance to avoid random hangs after 24+ hours running.

# U-boot has detection code for the ODROID boards.
#    https://github.com/u-boot/u-boot/blob/v2021.04/board/amlogic/odroid-n2/odroid-n2.c#L35-L106
# Unfortunately it uses n2_plus instead of n2-plus as the Kernel expects it.
#    So there is a hack at and around config/bootscripts/boot-meson64.cmd L90
# If needed (eg for extlinux) you can specify the N2/N2+/ DTB in BOOT_FDT_FILE, example for the N2+:
# BOOT_FDT_FILE="amlogic/meson-g12b-odroid-n2l.dtb"

function pre_customize_image__initialize_odroidn2_fanctrl_service() {
if [[ -f "$SRC/packages/bsp/odroid/fanctrl" ]]; then
	mkdir -p $SDCARD/usr/bin/
	display_alert "$BOARD" "Installing ODROID Fan Control" "info"
	install -m 755 $SRC/packages/bsp/odroid/fanctrl $SDCARD/usr/bin/
fi
mkdir -p ${SDCARD}/etc/systemd/system/
cat <<- 'EOD' > "${SDCARD}/etc/systemd/system/fanctrl.service"
[Unit]
Description=ODROID Fan Control
ConditionPathExists=/usr/bin/fanctrl
After=rc-local.service armbian-hardware-optimize.service

[Service]
ExecStart=/usr/bin/fanctrl run &>/dev/null
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOD
chroot_sdcard systemctl enable fanctrl.service
}
