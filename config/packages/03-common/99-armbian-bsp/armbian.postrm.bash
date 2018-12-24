cat <<EOF
if [ remove = "\$1" ] || [ abort-install = "\$1" ]; then
	dpkg-divert --package armbian-${RELEASE} --remove --rename --divert /etc/mpv/mpv-dist.conf /etc/mpv/mpv.conf
	systemctl disable armbian-hardware-monitor.service >/dev/null 2>&1
	systemctl disable armbian-hardware-optimize.service >/dev/null 2>&1
	systemctl disable armbian-zram-config.service >/dev/null 2>&1
	systemctl disable armbian-ramlog.service >/dev/null 2>&1
fi
EOF