# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_ARCH_MESON) += \
	meson-i2cA.dtbo \
	meson-i2cB.dtbo \
	meson-uartA.dtbo \
	meson-uartC.dtbo \
	meson-w1-gpio.dtbo \
	meson-w1AB-gpio.dtbo \
	meson-g12-gxl-cma-pool-896MB.dtbo \
	meson-g12a-radxa-zero-gpio-8-led.dtbo \
	meson-g12a-radxa-zero-gpio-10-led.dtbo \
	meson-g12b-odroid-n2-spi.dtbo \
	meson-g12b-waveshare-cm4-io-base-usb.dtbo \
	meson-sm1-bananapi-rtl8822cs.dtbo \
	meson-sm1-bananapi-uartA.dtbo \
	meson-sm1-bananapi-uartA_cts_rts.dtbo \
	meson-sm1-bananapi-uartAO_B.dtbo

scr-$(CONFIG_ARCH_MESON) += \
       meson-fixup.scr

dtbotxt-$(CONFIG_ARCH_MESON) += \
       README.meson-overlays

targets += $(dtbo-y) $(scr-y) $(dtbotxt-y)

always         := $(dtbo-y) $(scr-y) $(dtbotxt-y)
clean-files    := *.dtbo *.scr
