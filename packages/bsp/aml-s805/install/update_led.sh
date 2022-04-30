#!/bin/sh

while true
do
    echo 1 > /sys/class/leds/c1\:blue\:alive/brightness
    sleep 1
    echo 0 > /sys/class/leds/c1\:blue\:alive/brightness
    sleep 1
done
