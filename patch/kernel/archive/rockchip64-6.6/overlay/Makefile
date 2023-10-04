# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_ARCH_ROCKCHIP) += \
	rockchip-i2c7.dtbo \
	rockchip-i2c8.dtbo \
	rockchip-pcie-gen2.dtbo \
    rockchip-rk3328-i2c0.dtbo \
    rockchip-rk3328-uart1.dtbo \
	rockchip-rk3328-opp-1.4ghz.dtbo \
	rockchip-rk3328-opp-1.5ghz.dtbo \
	rockchip-rk3399-opp-2ghz.dtbo \
	rockchip-rockpi4cplus-usb-host.dtbo \
	rockchip-rockpro64-lcd.dtbo \
	rockchip-spi-jedec-nor.dtbo \
	rockchip-spi-spidev.dtbo \
	rockchip-uart4.dtbo \
	rockchip-dwc3-0-host.dtbo \
	rockchip-w1-gpio.dtbo \
	rockchip-rk3318-box-led-conf1.dtbo \
	rockchip-rk3318-box-led-conf2.dtbo \
	rockchip-rk3318-box-led-conf3.dtbo \
	rockchip-rk3318-box-led-conf4.dtbo \
	rockchip-rk3318-box-emmc-ddr.dtbo \
	rockchip-rk3318-box-wlan-ap6334.dtbo \
	rockchip-rk3318-box-wlan-ext.dtbo \
	rockchip-rk3318-box-wlan-ap6330.dtbo \
	rockchip-rk3318-box-cpu-hs.dtbo \
	rockchip-rk3318-box-emmc-hs200.dtbo \
	rockchip-rk3328-i2s1-pcm5102.dtbo \
        rk3308-bs.dtbo rk3308-bs@1.3ghz.dtbo \
        rk3308-sdio@10mhz.dtbo rk3308-sdio@4mhz.dtbo \
        rk3308-emmc.dtbo
        

scr-$(CONFIG_ARCH_ROCKCHIP) += \
       rockchip-fixup.scr

dtbotxt-$(CONFIG_ARCH_ROCKCHIP) += \
       README.rockchip-overlays

targets += $(dtbo-y) $(scr-y) $(dtbotxt-y)

always         := $(dtbo-y) $(scr-y) $(dtbotxt-y)
clean-files    := *.dtbo *.scr

