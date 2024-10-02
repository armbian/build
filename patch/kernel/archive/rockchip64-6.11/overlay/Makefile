# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_ARCH_ROCKCHIP) += \
	rk3308-s0-ext-antenna.dtbo \
	rk3308-b@1.3ghz.dtbo \
	rk3308-bs.dtbo rk3308-bs@1.3ghz.dtbo \
	rk3308-emmc.dtbo \
	rk3308-sdio@10mhz.dtbo rk3308-sdio@4mhz.dtbo \
	rockchip-rockpi4cplus-usb-host.dtbo \
	rockchip-rockpro64-lcd.dtbo \
	rockchip-rk3318-box-cpu-hs.dtbo \
	rockchip-rk3318-box-emmc-ddr.dtbo \
	rockchip-rk3318-box-emmc-hs200.dtbo \
	rockchip-rk3318-box-led-conf1.dtbo \
	rockchip-rk3318-box-led-conf2.dtbo \
	rockchip-rk3318-box-led-conf3.dtbo \
	rockchip-rk3318-box-led-conf4.dtbo \
	rockchip-rk3318-box-wlan-ap6330.dtbo \
	rockchip-rk3318-box-wlan-ap6334.dtbo \
	rockchip-rk3318-box-wlan-ext.dtbo \
	rockchip-rk3328-i2c0.dtbo \
	rockchip-rk3328-i2s1-pcm5102.dtbo \
	rockchip-rk3328-opp-1.4ghz.dtbo \
	rockchip-rk3328-opp-1.5ghz.dtbo \
	rockchip-rk3328-spi-spidev.dtbo \
	rockchip-rk3328-uart1.dtbo \
	rockchip-rk3399-dwc3-0-host.dtbo \
	rockchip-rk3399-i2c7.dtbo \
	rockchip-rk3399-i2c8.dtbo \
	rockchip-rk3399-opp-2ghz.dtbo \
	rockchip-rk3399-pcie-gen2.dtbo \
	rockchip-rk3399-spi-jedec-nor.dtbo \
	rockchip-rk3399-spi-spidev.dtbo \
	rockchip-rk3399-uart4.dtbo \
	rockchip-rk3399-w1-gpio.dtbo \
	rockchip-rk3566-sata2.dtbo \
	rockchip-rk3568-nanopi-r5c-leds.dtbo \
	rockchip-rk3568-nanopi-r5s-leds.dtbo \
	rockchip-rk3568-hk-i2c0.dtbo \
	rockchip-rk3568-hk-i2c1.dtbo \
	rockchip-rk3568-hk-pwm1.dtbo \
	rockchip-rk3568-hk-pwm2.dtbo \
	rockchip-rk3568-hk-pwm9.dtbo \
	rockchip-rk3568-hk-spi-spidev.dtbo \
	rockchip-rk3568-hk-uart0.dtbo \
	rockchip-rk3568-hk-uart0-rts_cts.dtbo \
	rockchip-rk3568-hk-uart1.dtbo

scr-$(CONFIG_ARCH_ROCKCHIP) += \
       rockchip-fixup.scr

dtbotxt-$(CONFIG_ARCH_ROCKCHIP) += \
       README.rockchip-overlays

dtb-y += $(dtbo-y) $(scr-y) $(dtbotxt-y)

clean-files    := *.dtbo *.scr

