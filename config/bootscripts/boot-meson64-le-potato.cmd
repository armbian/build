setenv bootargs "root=/dev/mmcblk0p1 ${consoleargs} hdmimode=${hdmimode} hdmitx=cecf logo=osd1,loaded,${fb_addr},${hdmimode} initrd=${initrd_start},${initrd_size}"
${bloader} ${loadaddr} /boot/zImage
${bloader} ${dtb_mem_addr} /boot/dtb/gxl_p212_2g.dtb
fdt addr ${dtb_mem_addr}
${bloader} ${initrd_start} /boot/uInitrd

if test -e mmc 0:1 boot/.next; then ${bloader} ${dtb_mem_addr} boot/dtb/amlogic/meson-gxl-s905x-libretech-cc.dtb; fi
if test -e mmc 0:1 boot/.next; then ${bloader} 0x01080000 boot/uImage; fi
if test -e mmc 0:1 boot/.next; then bootm 0x01080000 ${initrd_start} ${dtb_loadaddr}; else booti ${loadaddr} ${initrd_start} ${dtb_loadaddr}; fi
