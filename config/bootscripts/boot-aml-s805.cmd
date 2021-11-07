setenv env_addr "0x11400000"
setenv dtb_addr "0x11800000"
setenv kernel_addr "0x14000000"
setenv initrd_addr "0x15000000"
setenv boot_start bootm ${kernel_addr} ${initrd_addr} ${dtb_addr}
if fatload usb 0 ${env_addr} uEnv.txt; then env import -t ${env_addr} ${filesize}; setenv bootargs ${APPEND}; video dev open ${VMODE}; if fatload usb 0 ${kernel_addr} ${LINUX}; then if fatload usb 0 ${initrd_addr} ${INITRD}; then if fatload usb 0 ${dtb_addr} ${FDT}; then run boot_start; fi; fi; fi; fi;
if fatload mmc 0 ${env_addr} uEnv.txt; then env import -t ${env_addr} ${filesize}; setenv bootargs ${APPEND}; video dev open ${VMODE}; if fatload mmc 0 ${kernel_addr} ${LINUX}; then if fatload mmc 0 ${initrd_addr} ${INITRD}; then if fatload mmc 0 ${dtb_addr} ${FDT}; then run boot_start; fi; fi; fi; fi;
#video dev open 1080P50HZ
