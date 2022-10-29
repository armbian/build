ARCH=riscv64
ATF_COMPILE="no"
INITRD_ARCH="riscv"
GOVERNOR="ondemand"
NAME_KERNEL="Image"
NAME_INITRD="uInitrd"
MAIN_CMDLINE="rootflags=data=writeback rw no_console_suspend consoleblank=0 fsck.fix=yes fsck.repair=yes net.ifnames=0 bootsplash.bootfile=bootsplash.rv64os"
KERNEL_IMAGE_TYPE=Image

family_tweaks() {

#	if [[ $BOARD == starfive ]]; then

		install -m 644 $SRC/packages/blobs/riscv64/10-hdmi.conf $SDCARD/etc/X11/xorg.conf.d/10-hdmi.conf

#	fi

}
