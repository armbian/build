# SPDX-License-Identifier: GPL-2.0
dtbo-$(CONFIG_ARCH_MESON) += \
	meson-i2cA.dtbo \
	meson-i2cB.dtbo \
	meson-uartA.dtbo \
	meson-uartC.dtbo \
	meson-w1-gpio.dtbo \
	meson-w1AB-gpio.dtbo \
	meson-g12-gxl-cma-pool-896MB.dtbo \
	meson-g12-pwm-gpiox-5-fan.dtbo \
	meson-g12a-radxa-zero-gpio-8-led.dtbo \
	meson-g12a-radxa-zero-gpio-10-led.dtbo \
	meson-g12a-radxa-zero-i2c-ao-m0-gpioao-2-gpioao-3.dtbo \
	meson-g12a-radxa-zero-i2c-ee-m1-gpioh-6-gpioh-7.dtbo \
	meson-g12a-radxa-zero-i2c-ee-m1-gpiox-10-gpiox-11.dtbo \
	meson-g12a-radxa-zero-i2c-ee-m3-gpioa-14-gpioa-15.dtbo \
	meson-g12a-radxa-zero-pwm-c-on-gpiox-8.dtbo \
	meson-g12a-radxa-zero-pwmao-a-on-gpioao-11.dtbo \
	meson-g12a-radxa-zero-spi-spidev.dtbo \
	meson-g12a-radxa-zero-uart-ao-a-on-gpioao-0-gpioao-1.dtbo \
	meson-g12a-radxa-zero-uart-ao-b-on-gpioao-2-gpioao-3.dtbo \
	meson-g12a-radxa-zero-uart-ao-b-on-gpioao-8-gpioao-9.dtbo \
	meson-g12a-radxa-zero-uart-ee-c.dtbo \
	meson-g12b-bananapi-cm4-pwm-gpioh-5-fan.dtbo \
	meson-g12b-bananapi-cm4-wifi-freq-200mhz.dtbo \
	meson-g12b-bananapi-m2s-rtl8822cs.dtbo \
	meson-g12b-odroid-n2-spi.dtbo \
	meson-g12b-waveshare-cm4-io-base-usb.dtbo \
	meson-sm1-bananapi-m5-rtl8822cs.dtbo \
	meson-sm1-bananapi-uartA.dtbo \
	meson-sm1-bananapi-uartA_cts_rts.dtbo \
	meson-sm1-bananapi-uartAO_B.dtbo \
	meson-sm1-jethome-jethub-j200-spi.dtbo

scr-$(CONFIG_ARCH_MESON) += \
       meson-fixup.scr

dtbotxt-$(CONFIG_ARCH_MESON) += \
       README.meson-overlays

dtb-y += $(dtbo-y) $(scr-y) $(dtbotxt-y)

clean-files    := *.dtbo *.scr
