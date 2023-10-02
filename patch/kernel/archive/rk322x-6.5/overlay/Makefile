# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_ARCH_ROCKCHIP) += \
	rk322x-emmc.dtbo	\
	rk322x-emmc-pins.dtbo	\
	rk322x-emmc-ddr-ph45.dtbo \
	rk322x-emmc-ddr-ph180.dtbo \
	rk322x-emmc-hs200.dtbo	\
	rk322x-nand.dtbo	\
	rk322x-led-conf-default.dtbo \
	rk322x-led-conf1.dtbo	\
	rk322x-led-conf2.dtbo	\
	rk322x-led-conf3.dtbo   \
	rk322x-led-conf4.dtbo   \
	rk322x-led-conf5.dtbo   \
	rk322x-led-conf6.dtbo	\
	rk322x-led-conf7.dtbo	\
	rk322x-led-conf8.dtbo   \
	rk322x-cpu-hs.dtbo	\
	rk322x-cpu-hs-lv.dtbo	\
	rk322x-wlan-alt-wiring.dtbo \
	rk322x-cpu-stability.dtbo \
	rk322x-ddr3-330.dtbo \
	rk322x-ddr3-528.dtbo \
	rk322x-ddr3-660.dtbo \
	rk322x-ddr3-800.dtbo \
	rk322x-bt-8723cs.dtbo \
	rk322x-usb-otg-peripheral.dtbo


scr-$(CONFIG_ARCH_ROCKCHIP) += \
       rk322x-fixup.scr

dtbotxt-$(CONFIG_ARCH_ROCKCHIP) += \
       README.rk322x-overlays

targets += $(dtbo-y) $(scr-y) $(dtbotxt-y)

always         := $(dtbo-y) $(scr-y) $(dtbotxt-y)
clean-files    := *.dtbo *.scr

