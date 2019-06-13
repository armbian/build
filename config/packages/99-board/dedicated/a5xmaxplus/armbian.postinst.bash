cat <<EOF

[ -z "\$(grep -w '^fdtfile=rockchip/rk3328-a5xmaxplus.dtb' /boot/armbianEnv.txt 2> /dev/null)" ] && echo "fdtfile=rockchip/rk3328-a5xmaxplus.dtb" >> /boot/armbianEnv.txt
systemctl --no-reload enable a5xmaxplus-bluetooth.service >/dev/null 2>&1
systemctl --no-reload enable skykirin-ht1628.service >/dev/null 2>&1

EOF