if test -e mmc 0:1 boot/.next; 
	then setenv condev "console=ttyAML0,115200n8"; 
	else setenv condev "console=ttyS0,115200n8 earlyprintk=aml-uart,0xc81004c0"; fi

if test -e mmc 0:1 boot/.next; 
	then setenv rootdev "/dev/mmcblk1p1"; 
	else setenv rootdev "/dev/mmcblk0p1"; fi

if test -e mmc 0:1 boot/.next; 
	then setenv bootargs "root=${rootdev} rootwait rootflags=data=writeback rw rootfstype=ext4 ${condev} no_console_suspend consoleblank=0 fsck.repair=yes loglevel=5 net.ifnames=0";
	else setenv bootargs "root=${rootdev} rootwait rootflags=data=writeback rw rootfstype=ext4 ${condev} no_console_suspend consoleblank=0 cvbsmode=576cvbs hdmimode=1080p60hz cvbsdrv=0 m_bpp=24 loglevel=5 net.ifnames=0"; fi

${bloader} ${initrd_start} /boot/uInitrd

if test -e mmc 0:1 boot/.next; 
	then ${bloader} ${dtb_mem_addr} boot/dtb/amlogic/meson-gxl-s905x-libretech-cc.dtb; 
	else ${bloader} ${dtb_mem_addr} boot/dtb/meson-gxl-s905x-libretech-cc.dtb; fi

fdt addr ${dtb_mem_addr}

if test -e mmc 0:1 boot/.next; 
	then ${bloader} 0x01080000 boot/uImage; 
	else ${bloader} ${loadaddr} /boot/zImage; fi

if test -e mmc 0:1 boot/.next; 
	then bootm 0x01080000 ${initrd_start} ${dtb_mem_addr}; 
	else booti ${loadaddr} ${initrd_start} ${dtb_mem_addr}; fi
