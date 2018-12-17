cat <<EOF
#!/bin/sh
#
# ${BOARD_NAME} post installation script
#

# read config
[ -f /etc/armbian-release ] && . /etc/armbian-release

# enable services
systemctl --no-reload enable lime-a64-bluetooth.service >/dev/null 2>&1

exit 0
EOF
