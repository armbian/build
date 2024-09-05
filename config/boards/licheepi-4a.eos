# RISC-V LicheePi 4A
BOARD_NAME="LicheePi 4A"
BOARDFAMILY="thead"
BOARD_MAINTAINER="chainsx"
KERNEL_TARGET="legacy,current,edge"
KERNEL_TEST_TARGET="current"
BOOT_FDT_FILE="thead/th1520-lichee-pi-4a.dtb"
SRC_EXTLINUX="yes"
SRC_CMDLINE="console=ttyS0,115200 rootwait rw earlycon clk_ignore_unused loglevel=7 eth=\$ethaddr tsched=0 rootrwoptions=rw,noatime rootrwreset=yes"
BOOTCONFIG="light_lpi4a_defconfig"
BOOTFS_TYPE="ext4"
BOOTSIZE="512"

function post_family_tweaks__licheepi4a() {
	display_alert "Applying boot blobs"
	cp -v "$SRC/packages/blobs/riscv64/thead/light_aon_fpga.bin" "$SDCARD/boot/light_aon_fpga.bin"
	cp -v "$SRC/packages/blobs/riscv64/thead/light_c906_audio.bin" "$SDCARD/boot/light_c906_audio.bin"
	cp -v "$SRC/packages/blobs/riscv64/thead/fw_dynamic.bin" "$SDCARD/boot/fw_dynamic.bin"

	display_alert "Applying bt blobs"
	cp -v "$SRC/packages/blobs/riscv64/thead/rtlbt/rtk-hciattach.service" "$SDCARD/etc/systemd/system/rtk-hciattach.service"
	cp -v "$SRC/packages/blobs/riscv64/thead/rtlbt/rtk_hciattach" "$SDCARD/usr/local/bin/rtk_hciattach"
	cp -v "$SRC/packages/blobs/riscv64/thead/rtlbt/rtl8723d_config" "$SDCARD/lib/firmware/rtlbt/rtl8723d_config"
	cp -v "$SRC/packages/blobs/riscv64/thead/rtlbt/rtl8723d_fw" "$SDCARD/lib/firmware/rtlbt/rtl8723d_fw"

	display_alert "Temp add HDMI audio output on Volume control"
	mkdir -p $SDCARD/etc/pulse/
	echo "load-module module-alsa-sink device=hw:0,2" >> "$SDCARD/etc/pulse/default.pa"
}
