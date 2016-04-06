#!/bin/sh
#
# Simple script to enable CPU cores automatically again if cooling state is
# 3 or lower.
#

set -e

get_cooling_state() {
        echo $(cat /sys/devices/virtual/thermal/cooling_device0/cur_state)
}

enable_cpu() {
        if [ $(cat /sys/devices/system/cpu/cpu$1/online) = 0 ]; then
                echo 1 > /sys/devices/system/cpu/cpu$1/online || true
        fi
}

while true; do
        for c in 0 1 2 3; do
                if [ $(get_cooling_state) -le 3 ]; then
                        enable_cpu $c
                fi
        done
        sleep 5
done
