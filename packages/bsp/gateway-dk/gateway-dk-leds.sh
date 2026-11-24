#!/bin/bash
set -e
# Mono Gateway DK — switch from U-Boot green LED to white (Linux booted)
# The status LED is one multicolor LED class device; multi_index names the
# order of its channels, so light only the white one.
LED="/sys/class/leds/status:rgbw"
[[ -w "${LED}/multi_intensity" ]] || exit 0
intensity=()
for color in $(< "${LED}/multi_index"); do
	if [[ "${color}" == "white" ]]; then intensity+=(255); else intensity+=(0); fi
done
echo "${intensity[*]}" > "${LED}/multi_intensity"
echo 32 > "${LED}/brightness"
