cat <<EOF
#!/bin/sh
#
# ${FAMILY} post installation script
#

systemctl --no-reload enable odroid-c1-hdmi.service >/dev/null 2>&1
exit 0
EOF