#!/bin/sh

. /etc/armbian-release

check_abort()
{
	echo -e "\nDisabling user account creation procedure\n"
	rm -f /root/.not_logged_in_yet
	trap - INT
	exit 0
}

add_user()
{
	read -t 0 temp
	echo -e "\nPlease provide a username (eg. your forename): \c"
	read -e username
	RealUserName="$(echo "$username" | tr '[:upper:]' '[:lower:]' | tr -d -c '[:alnum:]')"
	[ -z "$RealUserName" ] && return
	echo "Trying to add user $RealUserName"
	adduser $RealUserName || return
	for additionalgroup in sudo netdev audio video dialout plugdev bluetooth ; do
		usermod -aG ${additionalgroup} ${RealUserName} 2>/dev/null
	done
	# fix for gksu in Xenial
	touch /home/$RealUserName/.Xauthority
	chown $RealUserName:$RealUserName /home/$RealUserName/.Xauthority
	RealName="$(awk -F":" "/^${RealUserName}:/ {print \$5}" </etc/passwd | cut -d',' -f1)"
	[ -z "$RealName" ] && RealName=$RealUserName
	echo -e "\nDear ${RealName}, your account ${RealUserName} has been created and is sudo enabled."
	echo -e "Please use this account for your daily work from now on.\n"
	rm -f /root/.not_logged_in_yet
}

if [ -f /root/.not_logged_in_yet ] && [ -n "$BASH_VERSION" ] && [ "$-" != "${-#*i}" ]; then
	if [ "$IMAGE_TYPE" != "nightly" ]; then
		echo -e "\n\e[0;31mThank you for choosing Armbian! Support: \e[1m\e[39mwww.armbian.com\x1B[0m\n"
	else
		echo -e "\nYou are using Armbian nightly build."
		echo -e "\nIt is provided \e[0;31mAS IS\x1B[0m with \e[0;31mNO WARRANTY\x1B[0m and \e[0;31mNO END USER SUPPORT\x1B[0m.\n"
	fi
	echo "Creating a new user account. Press <Ctrl-C> to abort"
	[ -f "/etc/init.d/nodm" ] && echo "Desktop environment will not be enabled if you abort the new user creation"
	trap check_abort INT
	while [ -f "/root/.not_logged_in_yet" ]; do
		add_user
	done
	trap - INT TERM EXIT
	# check for H3/legacy kernel to promote h3disp utility
	if [ "$LINUXFAMILY" = "sun8i" ] && [ "$BRANCH" = "default" ] && [ -n $(bin2fex </boot/script.bin 2>/dev/null | grep -w "hdmi_used = 1") ]; then
		setterm -default
		echo -e "\nYour display settings are currently 720p (1280x720). To change this use the"
		echo -e "h3disp utility. Do you want to change display settings now? [nY] \c"
		read -n1 ConfigureDisplay
		if [ "$ConfigureDisplay" != "n" ] && [ "$ConfigureDisplay" != "N" ]; then
			echo -e "\n" ; h3disp
		else
			echo -e "\n"
		fi
	fi
	# check whether desktop environment has to be considered
	if [ -f "/etc/init.d/nodm" ] && [ -n "$RealName" ] ; then
		# enable splash
		# [[ -f /etc/systemd/system/desktop-splash.service ]] && systemctl --no-reload enable desktop-splash.service >/dev/null 2>&1 && service desktop-splash restart
		sed -i "s/NODM_USER=\(.*\)/NODM_USER=${RealUserName}/" /etc/default/nodm
		sed -i "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" /etc/default/nodm
		if [ -z "$ConfigureDisplay" ] || [ "$ConfigureDisplay" = "n" ] || [ "$ConfigureDisplay" = "N" ]; then
			echo -e "\n\e[1m\e[39mNow starting desktop environment...\x1B[0m\n"
			sleep 3
			service nodm stop
			sleep 1
			service nodm start
		fi
	fi
fi
