cat <<EOF
[ "\$1" = "upgrade" ] && touch /var/run/.reboot_required
[ -d "/boot/bin.old" ] && rm -rf /boot/bin.old
[ -d "/boot/bin" ] && mv -f /boot/bin /boot/bin.old
if [ -L "/etc/network/interfaces" ]; then
	cp /etc/network/interfaces /etc/network/interfaces.tmp
	rm /etc/network/interfaces
	mv /etc/network/interfaces.tmp /etc/network/interfaces
fi

# swap
grep -q vm.swappiness /etc/sysctl.conf
case \$? in
0)
	sed -i 's/vm\.swappiness.*/vm.swappiness=100/' /etc/sysctl.conf
	;;
*)
	echo vm.swappiness=100 >>/etc/sysctl.conf
	;;
esac
sysctl -p >/dev/null 2>&1

# remove swap file if it was made by our start script
if [ -f /var/swap ]; then
	if [ "\$(stat -c%s /var/swap 2> /dev/null)" -eq "134217728" ]; then
        swapoff /var/swap
        sed -i '/\/var\/swap/d' /etc/fstab
        rm /var/swap
	fi
fi

# disable power management on network manager
if [ -f /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf ]; then
	sed -i 's/wifi.powersave.*/wifi.powersave = 2/' /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf
	else
	if [ -d /etc/NetworkManager/conf.d ]; then
		echo "[connection]" > /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf
		echo "# Values are 0 (use default), 1 (ignore/don't touch), 2 (disable) or 3 (enable)." >> /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf
		echo "wifi.powersave = 2" >> /etc/NetworkManager/conf.d/default-wifi-powersave-on.conf
	fi
fi

# disable deprecated services
systemctl disable armhwinfo.service >/dev/null 2>&1
#
[ -f "/etc/profile.d/activate_psd_user.sh" ] && rm /etc/profile.d/activate_psd_user.sh
[ -f "/etc/profile.d/check_first_login.sh" ] && rm /etc/profile.d/check_first_login.sh
[ -f "/etc/profile.d/check_first_login_reboot.sh" ] && rm /etc/profile.d/check_first_login_reboot.sh
[ -f "/etc/profile.d/ssh-title.sh" ] && rm /etc/profile.d/ssh-title.sh
#
[ -f "/etc/update-motd.d/10-header" ] && rm /etc/update-motd.d/10-header
[ -f "/etc/update-motd.d/30-sysinfo" ] && rm /etc/update-motd.d/30-sysinfo
[ -f "/etc/update-motd.d/35-tips" ] && rm /etc/update-motd.d/35-tips
[ -f "/etc/update-motd.d/40-updates" ] && rm /etc/update-motd.d/40-updates
[ -f "/etc/update-motd.d/98-autoreboot-warn" ] && rm /etc/update-motd.d/98-autoreboot-warn
[ -f "/etc/update-motd.d/99-point-to-faq" ] && rm /etc/update-motd.d/99-point-to-faq
# Remove Ubuntu junk
[ -f "/etc/update-motd.d/80-esm" ] && rm /etc/update-motd.d/80-esm
[ -f "/etc/update-motd.d/80-livepatch" ] && rm /etc/update-motd.d/80-livepatch
# Remove distro unattended-upgrades config
[ -f "/etc/apt/apt.conf.d/50unattended-upgrades" ] && rm /etc/apt/apt.conf.d/50unattended-upgrades
#
[ -f "/etc/apt/apt.conf.d/02compress-indexes" ] && rm /etc/apt/apt.conf.d/02compress-indexes
[ -f "/etc/apt/apt.conf.d/02periodic" ] && rm /etc/apt/apt.conf.d/02periodic
[ -f "/etc/apt/apt.conf.d/no-languages" ] && rm /etc/apt/apt.conf.d/no-languages
[ -f "/etc/init.d/armhwinfo" ] && rm /etc/init.d/armhwinfo
[ -f "/etc/logrotate.d/armhwinfo" ] && rm /etc/logrotate.d/armhwinfo
[ -f "/etc/init.d/firstrun" ] && rm /etc/init.d/firstrun
[ -f "/etc/init.d/resize2fs" ] && rm /etc/init.d/resize2fs
[ -f "/lib/systemd/system/firstrun-config.service" ] && rm /lib/systemd/system/firstrun-config.service
[ -f "/lib/systemd/system/firstrun.service" ] && rm /lib/systemd/system/firstrun.service
[ -f "/lib/systemd/system/resize2fs.service" ] && rm /lib/systemd/system/resize2fs.service
[ -f "/usr/lib/armbian/apt-updates" ] && rm /usr/lib/armbian/apt-updates
[ -f "/usr/lib/armbian/firstrun-config.sh" ] && rm /usr/lib/armbian/firstrun-config.sh
dpkg-divert --package armbian-${RELEASE} --add --rename \
		--divert /etc/mpv/mpv-dist.conf /etc/mpv/mpv.conf
EOF