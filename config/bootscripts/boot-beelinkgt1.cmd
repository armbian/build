setenv cec "cecf"
setenv m "1080p60hz"
setenv m_bpp "24"
setenv loadaddr "0x11000000"
setenv dtb_loadaddr "0x1000000"
setenv initrd_loadaddr "0x13000000"
setenv condev "console=ttyS0,115200n8 console=tty0 no_console_suspend consoleblank=0"
setenv bootargs "root=LABEL=ROOTFS rootflags=data=writeback rw ${condev} vout=hdmi,enable hdmimode=${m} m_bpp=${m_bpp} cvbsmode=${cvbsmode} cvbsdrv=${cvbs_drv} fsck.repair=yes net.ifnames=0 mac=00:15:18:01:81:31"
setenv boot_start booti ${loadaddr} ${initrd_loadaddr} ${dtb_loadaddr}
if fatload usb 0 ${initrd_loadaddr} uInitrd; then if fatload usb 0 ${loadaddr} zImage; then if fatload usb 0 ${dtb_loadaddr} dtb.img; then run boot_start; else store dtb read $dtb_loadaddr; run boot_start;fi;fi;fi;
if fatload mmc 0 ${initrd_loadaddr} uInitrd; then if fatload mmc 0 ${loadaddr} zImage; then if fatload mmc 0 ${dtb_loadaddr} dtb.img; then run boot_start; else store dtb read $dtb_loadaddr; run boot_start;fi;fi;fi;
