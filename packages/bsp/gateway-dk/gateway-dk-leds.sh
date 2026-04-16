#!/bin/bash
set -e
# Mono Gateway DK — switch from U-Boot green LED to white (Linux booted)
GREEN="/sys/class/leds/status:green/brightness"
WHITE="/sys/class/leds/status:white/brightness"
[[ -w "$GREEN" ]] && echo 0 > "$GREEN"
[[ -w "$WHITE" ]] && echo 32 > "$WHITE"
