defenv
setenv bootcmd 'run start_autoscript; run storeboot;'
setenv start_autoscript 'if usb start; then run start_usb_autoscript; fi; if mmcinfo; then run start_mmc_autoscript; fi; run start_emmc_autoscript;'
setenv start_emmc_autoscript 'if fatload mmc 0 11000000 emmc_autoscript; then autoscr 11000000; fi; if ext4load mmc 0:${system_part} 11000000 emmc_autoscript; then autoscr 11000000; fi; if fatload mmc 1 11000000 emmc_autoscript; then autoscr 11000000; fi; if ext4load mmc 1:${system_part} 11000000 emmc_autoscript; then autoscr 11000000; fi;'
setenv start_mmc_autoscript 'if fatload mmc 0 11000000 s805_autoscript; then autoscr 11000000; fi;'
setenv start_usb_autoscript 'if fatload usb 0 11000000 s805_autoscript; then autoscr 11000000; fi; if fatload usb 1 11000000 s805_autoscript; then autoscr 11000000; fi; if fatload usb 2 11000000 s805_autoscript; then autoscr 11000000; fi; if fatload usb 3 11000000 s805_autoscript; then autoscr 11000000; fi;'
setenv system_part "b"
setenv reboot_mode normal
saveenv
reset
