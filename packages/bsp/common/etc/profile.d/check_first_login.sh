#!/bin/sh

. /etc/armbian-release

check_abort()
{
	echo -e "\nDisabling user account creation procedure\n"
	rm -f /root/.not_logged_in_yet
	trap - INT
	exit 0
}

add_profile_sync_settings()
{
	/usr/bin/psd >/dev/null 2>&1
	config_file="${HOME}/.config/psd/psd.conf"
	if [ -f "${config_file}" ]; then
		# test for overlayfs
		sed -i 's/#USE_OVERLAYFS=.*/USE_OVERLAYFS="yes"/' "${config_file}"
		case $(/usr/bin/psd p 2>/dev/null | grep Overlayfs) in
			*active*)
				echo -e "\nConfigured profile sync daemon with overlayfs."
				;;
			*)
				echo -e "\nConfigured profile sync daemon."
				sed -i 's/USE_OVERLAYFS="yes"/#USE_OVERLAYFS="no"/' "${config_file}"
				;;
		esac
	fi
	systemctl --user enable psd.service >/dev/null 2>&1
	systemctl --user start psd.service >/dev/null 2>&1
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
	for additionalgroup in sudo netdev audio video dialout plugdev bluetooth systemd-journal ssh; do
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
	# set up profile sync daemon on desktop systems
	which psd >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		echo -e "${RealUserName} ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper" >>/etc/sudoers
		export -f add_profile_sync_settings
		su ${RealUserName} -c "bash -c add_profile_sync_settings" 2>/dev/null
	fi
}

if [ -f /root/.not_logged_in_yet ] && [ -n "$BASH_VERSION" ] && [ "$-" != "${-#*i}" ]; then
	# detect desktop
	desktop_nodm=$(dpkg-query -W -f='${db:Status-Abbrev}\n' nodm 2>/dev/null)
	desktop_lightdm=$(dpkg-query -W -f='${db:Status-Abbrev}\n' lightdm 2>/dev/null)

	if [ -n "$desktop_nodm" ]; then DESKTOPDETECT="nodm"; fi
	if [ -n "$desktop_lightdm" ]; then DESKTOPDETECT="lightdm"; fi

	if [ "$IMAGE_TYPE" != "nightly" ]; then
		echo -e "\n\e[0;31mThank you for choosing Armbian! Support: \e[1m\e[39mwww.armbian.com\x1B[0m\n"
	else
		echo -e "\nYou are using an Armbian nightly build meant only for developers to provide"
		echo -e "constructive feedback to improve build system, OS settings or user experience."
		echo -e "If this does not apply to you, \e[0;31mSTOP NOW!\x1B[0m. Especially don't use this image for"
		echo -e "daily work since things might not work as expected or at all and may break"
		echo -e "anytime with next update. \e[0;31mYOU HAVE BEEN WARNED!\x1B[0m"
		echo -e "\nThis image is provided \e[0;31mAS IS\x1B[0m with \e[0;31mNO WARRANTY\x1B[0m and \e[0;31mNO END USER SUPPORT!\x1B[0m.\n"
	fi
	echo "Creating a new user account. Press <Ctrl-C> to abort"
	[ -n "$DESKTOPDETECT" ] && echo "Desktop environment will not be enabled if you abort the new user creation"
	trap check_abort INT
	while [ -f "/root/.not_logged_in_yet" ]; do
		add_user
	done
	trap - INT TERM EXIT
	# check for H3/legacy kernel to promote h3disp utility
	if [ -f /boot/script.bin ]; then tmp=$(bin2fex </boot/script.bin 2>/dev/null | grep -w "hdmi_used = 1"); fi
	if [ "$LINUXFAMILY" = "sun8i" ] && [ "$BRANCH" = "default" ] && [ -n "$tmp" ]; then
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
	if [ "$DESKTOPDETECT" = nodm ] && [ -n "$RealName" ] ; then
		# enable splash
		# [[ -f /etc/systemd/system/desktop-splash.service ]] && systemctl --no-reload enable desktop-splash.service >/dev/null 2>&1 && service desktop-splash restart
		sed -i "s/NODM_USER=\(.*\)/NODM_USER=${RealUserName}/" /etc/default/nodm
		sed -i "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" /etc/default/nodm
		if [[ -f /var/run/resize2fs-reboot ]]; then
			# Let the user reboot now otherwise start desktop environment
			printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
			printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
		elif [ -z "$ConfigureDisplay" ] || [ "$ConfigureDisplay" = "n" ] || [ "$ConfigureDisplay" = "N" ]; then
			echo -e "\n\e[1m\e[39mNow starting desktop environment...\x1B[0m\n"
			sleep 3
			service nodm stop
			sleep 1
			service nodm start
		fi
	elif [ "$DESKTOPDETECT" = lightdm ] && [ -n "$RealName" ] ; then
			ln -sf /lib/systemd/system/lightdm.service /etc/systemd/system/display-manager.service
		if [[ -f /var/run/resize2fs-reboot ]]; then
			# Let the user reboot now otherwise start desktop environment
			printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
			printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
		elif [ -z "$ConfigureDisplay" ] || [ "$ConfigureDisplay" = "n" ] || [ "$ConfigureDisplay" = "N" ]; then
			echo -e "\n\e[1m\e[39mNow starting desktop environment...\x1B[0m\n"
			sleep 1
			service lightdm start 2>/dev/null
			# logout if logged at console
			[[ -n $(who -la | grep root | grep tty1) ]] && exit 1
		fi
	else
		# Display reboot recommendation if necessary
		if [[ -f /var/run/resize2fs-reboot ]]; then
			printf "\n\n\e[0;91mWarning: a reboot is needed to finish resizing the filesystem \x1B[0m \n"
			printf "\e[0;91mPlease reboot the system now \x1B[0m \n\n"
		fi
	fi
fi
