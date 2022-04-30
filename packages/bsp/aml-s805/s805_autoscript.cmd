setenv env_addr "0x11400000"
setenv dtb_addr "0x11800000"
setenv kernel_addr "0x14000000"
setenv initrd_addr "0x15000000"
setenv boot_start bootm ${kernel_addr} ${initrd_addr} ${dtb_addr}
if fatload usb 0 ${kernel_addr} uImage; then if fatload usb 0 ${initrd_addr} uInitrd; then if fatload usb 0 ${env_addr} uEnv.txt; then env import -t ${env_addr} ${filesize}; video dev open ${VMODE};fi; if fatload usb 0 ${dtb_addr} ${dtb_name}; then unifykey get mac;setenv bootargs ${bootargs} mac=${mac};run boot_start; else imgread dtb boot ${dtb_addr}; run boot_start;fi;fi;fi;
if fatload usb 1 ${kernel_addr} uImage; then if fatload usb 1 ${initrd_addr} uInitrd; then if fatload usb 1 ${env_addr} uEnv.txt; then env import -t ${env_addr} ${filesize}; video dev open ${VMODE};fi; if fatload usb 1 ${dtb_addr} ${dtb_name}; then unifykey get mac;setenv bootargs ${bootargs} mac=${mac};run boot_start; else imgread dtb boot ${dtb_addr}; run boot_start;fi;fi;fi;
if fatload mmc 1 ${kernel_addr} uImage; then if fatload mmc 1 ${initrd_addr} uInitrd; then if fatload mmc 1 ${env_addr} uEnv.txt; then env import -t ${env_addr} ${filesize}; video dev open ${VMODE};fi; if fatload mmc 1 ${dtb_addr} ${dtb_name}; then unifykey get mac;setenv bootargs ${bootargs} mac=${mac};run boot_start; else imgread dtb boot ${dtb_addr}; run boot_start;fi;fi;fi;
