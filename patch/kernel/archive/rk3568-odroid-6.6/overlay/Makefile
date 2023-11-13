# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_ARCH_ROCKCHIP) += \
	rockchip-spi-spidev.dtbo \
	rockchip-uart0.dtbo \
	rockchip-uart0-rts_cts.dtbo \
	rockchip-uart1.dtbo \
	rockchip-pwm1.dtbo \
	rockchip-pwm2.dtbo \
	rockchip-pwm9.dtbo \
	rockchip-i2c0.dtbo \
	rockchip-i2c1.dtbo \
        rockchip-nanopi-r5s-leds.dtbo

scr-$(CONFIG_ARCH_ROCKCHIP) += \
       rockchip-fixup.scr

dtbotxt-$(CONFIG_ARCH_ROCKCHIP) += \
       README.rockchip-overlays

targets += $(dtbo-y) $(scr-y) $(dtbotxt-y)

always         := $(dtbo-y) $(scr-y) $(dtbotxt-y)
clean-files    := *.dtbo *.scr

