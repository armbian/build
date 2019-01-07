cat <<EOF

# read config
[ -f /etc/armbian-release ] && . /etc/armbian-release


# enable services
systemctl --no-reload enable olinuxino-bluetooth.service >/dev/null 2>&1

EOF
