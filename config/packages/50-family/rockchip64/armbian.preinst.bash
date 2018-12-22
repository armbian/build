cat <<EOF
#!/bin/sh
[ "\$1" = "upgrade" ] && touch /var/run/.reboot_required
EOF
if [[ $FORCE_BOOTSCRIPT_UPDATE == yes ]]; then
cat <<EOF
	# create a bootscript backup
	if [ -f /etc/armbian-release ]; then
		# create a backup
		. /etc/armbian-release
		cp /boot/$bootscript_dst /usr/share/armbian/${bootscript_dst}-\${VERSION} >/dev/null 2>&1
		echo "NOTE: You can find previous bootscript versions in /usr/share/armbian !"
	fi

EOF
fi
cat <<EOF
exit 0
EOF