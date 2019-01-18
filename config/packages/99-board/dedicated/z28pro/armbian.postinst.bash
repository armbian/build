cat <<EOF

[ -z "\$(grep -w '^fdtfile=rockchip/rk3328-z28pro.dtb' /boot/armbianEnv.txt 2> /dev/null)" ] && echo "fdtfile=rockchip/rk3328-z28pro.dtb" >> /boot/armbianEnv.txt
systemctl --no-reload enable z28pro-bluetooth.service >/dev/null 2>&1

EOF