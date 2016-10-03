setenv cec "cecf"
setenv loadaddr "0x11000000"
setenv dtb_loadaddr "0x1000000"
setenv initrd_loadaddr "0x13000000"
setenv condev "console=ttyS0,115200n8 console=tty0 consoleblank=0"
setenv bootargs "root=LABEL=ROOTFS rootwait rootflags=data=writeback rw ${condev} no_console_suspend hdmimode=${hdmimode} m_bpp=${display_bpp} fsck.repair=yes net.ifnames=0"
setenv boot_start booti ${loadaddr} ${initrd_loadaddr} ${dtb_loadaddr}
if fatload usb 0 ${initrd_loadaddr} uInitrd; then if fatload usb 0 ${loadaddr} zImage; then if fatload usb 0 ${dtb_loadaddr} dtb.img; then run boot_start; else store dtb read $dtb_loadaddr; run boot_start;fi;fi;fi;
if fatload mmc 0 ${initrd_loadaddr} uInitrd; then if fatload mmc 0 ${loadaddr} zImage; then if fatload mmc 0 ${dtb_loadaddr} dtb.img; then run boot_start; else store dtb read $dtb_loadaddr; run boot_start;fi;fi;fi;
