#!/bin/sh
# Only run on systems where logrotate is a cron job
systemctl is-active --quiet logrotate.timer && exit 0
/usr/lib/armbian/armbian-ramlog write >/dev/null 2>&1
