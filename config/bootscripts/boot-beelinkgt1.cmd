setenv m "1080p60hz"
setenv cec "cecf"
setenv m_bpp "24"
setenv loadaddr "0x11000000"
setenv dtb_loadaddr "0x1000000"
setenv initrd_loadaddr "0x13000000"
setenv condev "console=ttyS0,115200n8 console=tty0 consoleblank=0"
setenv bootargs "root=LABEL=ROOTFS rootwait rootflags=data=writeback rw ${condev} no_console_suspend hdmimode=${m} m_bpp=${m_bpp} fsck.repair=yes net.ifnames=0"
setenv boot_start booti ${loadaddr} ${initrd_loadaddr} ${dtb_loadaddr}
if fatload usb 0:1 ${dtb_loadaddr} dtb.img; then setenv dtb_img "1"; else if store dtb read $dtb_loadaddr; then setenv dtb_img "1"; else setenv dtb_img "0";fi;fi;
if fatload usb 0:1 ${initrd_loadaddr} uInitrd; then if fatload usb 0:1 ${loadaddr} zImage; then if test "${dtb_img}" = "1"; then run boot_start;fi;fi;fi;
if fatload mmc 0:1 ${dtb_loadaddr} dtb.img; then setenv dtb_img "1"; else if store dtb read $dtb_loadaddr; then setenv dtb_img "1"; else setenv dtb_img "0";fi;fi;
if fatload mmc 0:1 ${initrd_loadaddr} uInitrd; then if fatload mmc 0:1 ${loadaddr} zImage; then if test "${dtb_img}" = "1"; then run boot_start;fi;fi;fi;
# Recompile with:
# mkimage -C none -A arm -T script -d /boot/s912_autoscript.cmd /boot/s912_autoscript
