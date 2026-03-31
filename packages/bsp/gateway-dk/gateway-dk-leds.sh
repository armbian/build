#!/bin/bash
# Mono Gateway DK — switch from U-Boot green LED to white (Linux booted)
echo 0 > /sys/class/leds/status:green/brightness
echo 32 > /sys/class/leds/status:white/brightness
