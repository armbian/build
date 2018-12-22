cat <<EOF
#!/bin/sh
#
# Armbian common post installation script
#


# enable ramlog only if it was enabled before
if [ -n "\$(service log2ram status 2> /dev/null)" ]; then
	systemctl --no-reload enable armbian-ramlog.service
fi

# check if it was disabled in config and disable in new service
if [ -n "\$(grep -w '^ENABLED=false' /etc/default/log2ram 2> /dev/null)" ]; then
	sed -i "s/^ENABLED=.*/ENABLED=false/" /etc/default/armbian-ramlog
fi

# now cleanup and remove old ramlog service
systemctl disable log2ram.service >/dev/null 2>&1
[ -f "/usr/sbin/log2ram" ] && rm /usr/sbin/log2ram
[ -f "/usr/share/log2ram/LICENSE" ] && rm -r /usr/share/log2ram
[ -f "/lib/systemd/system/log2ram.service" ] && rm /lib/systemd/system/log2ram.service
[ -f "/etc/cron.daily/log2ram" ] && rm /etc/cron.daily/log2ram
[ -f "/etc/default/log2ram.dpkg-dist" ] && rm /etc/default/log2ram.dpkg-dist

[ ! -f "/etc/network/interfaces" ] && cp /etc/network/interfaces.default /etc/network/interfaces
ln -sf /var/run/motd /etc/motd
rm -f /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text

if [ ! -f "/etc/default/armbian-motd" ]; then
	mv /etc/default/armbian-motd.dpkg-dist /etc/default/armbian-motd
fi
if [ ! -f "/etc/default/armbian-ramlog" ]; then
	mv /etc/default/armbian-ramlog.dpkg-dist /etc/default/armbian-ramlog
fi
if [ ! -f "/etc/default/armbian-zram-config" ]; then
	mv /etc/default/armbian-zram-config.dpkg-dist /etc/default/armbian-zram-config
fi

if [ -L "/usr/lib/chromium-browser/master_preferences.dpkg-dist" ]; then
	mv /usr/lib/chromium-browser/master_preferences.dpkg-dist /usr/lib/chromium-browser/master_preferences
fi

systemctl --no-reload enable armbian-hardware-monitor.service armbian-hardware-optimize.service armbian-zram-config.service >/dev/null 2>&1
exit 0
EOF