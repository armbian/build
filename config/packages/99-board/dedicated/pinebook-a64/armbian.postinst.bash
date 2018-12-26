cat <<EOF
#!/bin/sh
#
# ${BOARD_NAME} post installation script
#

# read config
[ -f /etc/armbian-release ] && . /etc/armbian-release


if [ "\$BRANCH" = "default" ]; then
# enable services
systemctl --no-reload enable pinebook-bluetooth.service pinebook-enable-sound.service >/dev/null 2>&1
systemctl --no-reload enable pinebook-store-sound-on-suspend.service pinebook-restore-sound-after-resume.service >/dev/null 2>&1
fi

exit 0
EOF