cat <<EOF

MACADDR=\$(printf '43:29:B1:%02X:%02X:%02X\n' $[RANDOM%256] $[RANDOM%256] $[RANDOM%256])
cat <<-EOT > /etc/default/brcm4330
MAC_ADDR=\${MACADDR}
PORT=ttymxc3
EOT
systemctl enable brcm4330-patch
service brcm4330-patch start

EOF
