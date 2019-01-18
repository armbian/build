cat <<EOF
[ "\$1" = "upgrade" ] && touch /var/run/.reboot_required
EOF
if [[ $FORCE_BOOTSCRIPT_UPDATE == yes ]]; then
cat <<EOT

# create a bootscript backup
if [ -f /etc/armbian-release ]; then
	. /etc/armbian-release
	mkdir -p /usr/share/armbian/
	cp /boot/$bootscript_dst /usr/share/armbian/${bootscript_dst}-\${VERSION} >/dev/null 2>&1
	echo "NOTE: You can find previous bootscript versions in /usr/share/armbian !"
fi
EOT
fi