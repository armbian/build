#!/bin/bash
set -o nounset
set -o errexit
set -o pipefail
shopt -s dotglob

# SPDX-License-Identifier: MIT

# This script should be executed every 5 minutes by a cron job `/etc/cron.d/armbian-check-battery`.
# It checks if battery is discharging and battery level is more than 10%. If less, then start a system shutdown.
# Script uses `batteryinfo` function from `30-armbian-sysinfo` file of Armbian distribution.

BATTERY_PERCENT_MIN='10'

# Include functions:
# getboardtemp()
# batteryinfo()
# ambienttemp()
source /usr/lib/armbian/armbian-allwinner-battery
batteryinfo

# `status_battery_text` has a leading whitespace
if [ "$status_battery_connected" == '1' ] && [[ "$status_battery_text" =~ [[:space:]]*discharging ]]; then
  # When no battery connected, variable `battery_percent` is not defined!
  if [ "$battery_percent" -lt "$BATTERY_PERCENT_MIN" ]; then
    logger --tag cron_check_battery_shutdown "battery_percent = $battery_percent, running shutdown"
    shutdown -h +1
  fi
fi
