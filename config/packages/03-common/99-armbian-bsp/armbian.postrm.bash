cat <<EOF
#!/bin/sh
if [ remove = "\$1" ] || [ abort-install = "\$1" ]; then
	systemctl disable armbian-hardware-monitor.service armbian-hardware-optimize.service armbian-zram-config.service armbian-ramlog.service >/dev/null 2>&1
fi
exit 0
EOF