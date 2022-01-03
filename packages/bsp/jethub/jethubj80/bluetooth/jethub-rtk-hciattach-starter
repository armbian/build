#!/bin/bash

# Re-enable bluetooth chip via GPIO
if [ ! -f /sys/class/gpio/gpio497/value ]; then
  echo 497 > /sys/class/gpio/export
  echo out > /sys/class/gpio/gpio497/direction
fi
echo 0 > /sys/class/gpio/gpio497/value && sleep 0.1
sleep 1
echo 1 > /sys/class/gpio/gpio497/value && sleep 0.1

echo 497 > /sys/class/gpio/unexport

# Attach serial devices via UART HCI to BlueZ stack
rtk_hciattach /dev/ttyAML1 -s 115200 rtk_h5 115200 || true
