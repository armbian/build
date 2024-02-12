#!/bin/bash
# shellcheck disable=SC2034

GPIO_DIRECTION_OUTPUT=0
GPIO_DIRECTION_INPUT=1

GPIO_ACTIVE_LOW=0
GPIO_ACTIVE_HIGH=1

GPIOS=(
  # Discrete inputs: 1, 2, 3
  "2  8 ${GPIO_DIRECTION_INPUT} ${GPIO_ACTIVE_HIGH}"
  "2  9 ${GPIO_DIRECTION_INPUT} ${GPIO_ACTIVE_HIGH}"
  "2 10 ${GPIO_DIRECTION_INPUT} ${GPIO_ACTIVE_HIGH}"
  # Relays: 1, 2
  "2  0 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  "2  1 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  # UXM1 module: RESET, BOOT
  "2  4 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  "2  5 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  # UXM2 module: RESET, BOOT
  "2  6 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  "2  7 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  # Button
  "1 10 ${GPIO_DIRECTION_INPUT} ${GPIO_ACTIVE_LOW}"
)


# Set LED states
LEDS=(
)


reset_uxm1() {
    echo "${0}: Reset UXM1 module ..."
    gpio_set 2 5 1 ${GPIO_ACTIVE_HIGH}
    gpio_set 2 6 1 ${GPIO_ACTIVE_HIGH}
    sleep 1
    gpio_set 2 6 0 ${GPIO_ACTIVE_HIGH}
}

reset_uxm2() {
    echo "${0}: Reset UXM2 module ..."
    gpio_set 2 7 1 ${GPIO_ACTIVE_HIGH}
    gpio_set 2 6 1 ${GPIO_ACTIVE_HIGH}
    sleep 1
    gpio_set 2 6 0 ${GPIO_ACTIVE_HIGH}
}

config_1wire() {
    echo "${0}: Configure 1-Wire ..."
    if ! modprobe ds2482; then
        echo "${0}: *** Error: Failed to load DS2482 kernel module"
        exit 1
    fi
}

ADDITIONALFUNC="reset_uxm1 reset_uxm2 config_1wire"
