#!/bin/bash

online=$(cat /sys/class/power_supply/gpio-charger/online)
[[ $online == 0 ]] && exit 0

# Export GPIO
# AUTO_ON_D
echo 153 > /sys/class/gpio/export
# AUTO_EN_CLK
echo 154 > /sys/class/gpio/export

echo out > /sys/class/gpio/gpio153/direction
echo out > /sys/class/gpio/gpio154/direction

# Toggling the D Flip-Flop
echo 0 > /sys/class/gpio/gpio153/value
echo 0 > /sys/class/gpio/gpio154/value
sleep 0.1
echo 1 > /sys/class/gpio/gpio154/value
sleep 0.1
echo 0 > /sys/class/gpio/gpio154/value
