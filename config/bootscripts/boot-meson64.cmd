ext4load mmc 0:1 ${loadaddr} /boot/zImage
ext4load mmc 0:1 ${dtb_mem_addr} /boot/dtb/${dtb_name}
ext4load mmc 0:1 ${dtb_mem_addr} /boot/dtb/gxbb_p200_2G.dtb
ext4load mmc 0:1 ${initrd_start} /boot/uInitrd
setenv bootargs "root=/dev/mmcblk0p1 ${consoleargs} hdmimode=${hdmimode} hdmitx=cecf logo=osd1,loaded,${fb_addr},${hdmimode} initrd=${initrd_start},${initrd_size}"
booti ${loadaddr} ${initrd_start} ${dtb_mem_addr};