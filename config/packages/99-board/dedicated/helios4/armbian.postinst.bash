cat <<'EOF'

# read config
[ -f /etc/armbian-release ] && . /etc/armbian-release

# copy fancontrol config
case $BRANCH in
default)
	cp /usr/share/helios4/fancontrol_pwm-fan-mvebu-default.conf /etc/fancontrol
	;;
next)
	cp /usr/share/helios4/fancontrol_pwm-fan-mvebu-next.conf /etc/fancontrol
	;;
esac

# enable wol
systemctl --no-reload enable helios4-wol.service

# mdadm tweaks
MDADM_CONF=/etc/mdadm/mdadm.conf
MDADM_HOOK=/usr/share/initramfs-tools/hooks/mdadm

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

# enable helios4-wol.service
systemctl --no-reload enable helios4-wol.service >/dev/null 2>&1

EOF
