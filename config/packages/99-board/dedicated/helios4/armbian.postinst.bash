cat <<'EOF'
MDADM_CONF=/etc/mdadm/mdadm.conf
MDADM_HOOK=/usr/share/initramfs-tools/hooks/mdadm

# Mdadm tweaks
grep -q "PROGRAM" $MDADM_CONF
if [ "$?" -ne 0 ]; then
	cat <<-EOS >> $MDADM_CONF

	# Trigger Fault Led script when an event is detected
	PROGRAM /usr/sbin/mdadm-fault-led.sh

	EOS
fi

# Fix for "mdadm: initramfs boot message: /scripts/local-bottom/mdadm: rm: not found"
# Refer to https://wiki.kobol.io/mdadm/#fix-mdadm
grep -q "^[[:blank:]]*copy_exec /bin/rm /bin" $MDADM_HOOK
if [ "$?" -ne 0 ]; then
	sed -i '/copy_exec \/sbin\/mdmon \/sbin/ a\copy_exec /bin/rm /bin' $MDADM_HOOK
	update-initramfs -u
fi

EOF
