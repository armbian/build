setenv condev "console=ttyAML0,115200n8"; 

setenv rootdev "/dev/mmcblk1p1"; 

setenv bootargs "root=${rootdev} rootwait rootflags=data=writeback rw rootfstype=ext4 ${condev} no_console_suspend consoleblank=0 fsck.repair=yes loglevel=5 net.ifnames=0";

${bloader} ${initrd_start} /boot/uInitrd


${bloader} ${dtb_mem_addr} boot/dtb/amlogic/meson-gxl-s905x-libretech-cc.dtb; 


fdt addr ${dtb_mem_addr}

${bloader} 0x01080000 boot/uImage; 

bootm 0x01080000 ${initrd_start} ${dtb_mem_addr}; 

