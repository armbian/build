#!/bin/bash
# shellcheck disable=SC2034

GPIO_DIRECTION_OUTPUT=0
GPIO_DIRECTION_INPUT=1

GPIO_ACTIVE_LOW=0
GPIO_ACTIVE_HIGH=1


GPIOS=(
  # Zigbee module: RESET, BOOT
  "0 6 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  "0 9 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  # Z-Wave module: RESET, SUSPEND
  "1 89 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  "1 90 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
  # LED
  "1 73 ${GPIO_DIRECTION_OUTPUT} ${GPIO_ACTIVE_HIGH}"
)

# Set LED states
LEDS=(
    # LED
    "1 73 0 ${GPIO_ACTIVE_HIGH}"
)

reset_zigbee() {
    echo "${0}: Reset Zigbee module ..."
    gpio_set 0 9 1 ${GPIO_ACTIVE_HIGH}
    gpio_set 0 6 1 ${GPIO_ACTIVE_HIGH}
    sleep 1
    gpio_set 0 6 0 ${GPIO_ACTIVE_HIGH}
}

reset_zwave() {
    echo "${0}: Reset Z-Wave module ..."
    # Optional SUSPEND pin
    # gpio_set 1 90 1 ${GPIO_ACTIVE_HIGH}
    gpio_set 1 89 1 ${GPIO_ACTIVE_HIGH}
    sleep 1
    gpio_set 1 89 0 ${GPIO_ACTIVE_HIGH}
}

eth_leds() {
    echo "${0}: Configure Ethernet leds ..."
    /usr/sbin/jethub_set-eth_leds
}

ADDITIONALFUNC="eth_leds reset_zigbee"
# Enable for second module
#ADDITIONALFUNC="${ADDITIONALFUNC} reset_zwave"
