cat <<'EOF'
MDADM_CONF=/etc/mdadm/mdadm.conf

# Patch fancontrol
patch --silent --forward --no-backup-if-mismatch -r - /usr/sbin/fancontrol /usr/share/${DPKG_MAINTSCRIPT_PACKAGE}/fancontrol.patch >/dev/null 2>&1

# Mdadm tweaks
grep -q "PROGRAM" $MDADM_CONF
if [ "$?" -ne 0 ]; then
	cat <<-EOS >> $MDADM_CONF

	# Trigger Fault Led script when an event is detected
	PROGRAM /usr/sbin/mdadm-fault-led.sh

	EOS
fi

EOF
