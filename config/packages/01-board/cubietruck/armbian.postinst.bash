cat <<EOF
#!/bin/sh
#
# ${BOARD_NAME} post installation script
#

MACADDR=\$(printf '43:29:B1:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256])
cat <<-EOT > /etc/default/brcm40183
MAC_ADDR=\${MACADDR}
PORT=ttyS1
EOT
systemctl enable brcm40183-patch
service brcm40183-patch start
exit 0
EOF