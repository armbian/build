#!/bin/bash
# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
	if [ -f "$HOME/.not_logged_in_yet" ]; then
		echo -e "\n\e[0;31mThank you for choosing Armbian! Support: \e[1m\e[39mwww.armbian.com\x1B[0m\n"
		echo -e "Creating new account. Please provide a username (eg. your forename): \c"
		read username
		RealUserName="$(echo "${username}" | tr '[:upper:]' '[:lower:]' | tr -d -c '[:alnum:]')"
		adduser ${RealUserName} || reboot
		for additionalgroup in sudo netdev audio video dialout plugdev bluetooth ; do
			usermod -aG ${additionalgroup} ${RealUserName} 2>/dev/null
		done
		# fix for gksu in Xenial
		touch /home/$RealUserName/.Xauthority
		chown $RealUserName:$RealUserName /home/$RealUserName/.Xauthority
		rm -f "$HOME/.not_logged_in_yet"
		RealName="$(awk -F":" "/^${RealUserName}:/ {print \$5}" </etc/passwd | cut -d',' -f1)"
		echo -e "\nDear ${RealName}, your account ${RealUserName} has been created and is sudo enabled."
		echo -e "Please use this account for your daily work from now on.\n"

		# check for H3/legacy kernel to promote h3disp utility
		HARDWARE=$(awk '/Hardware/ {print $3}' </proc/cpuinfo)
		if [[ "X${HARDWARE}" = "Xsun8i" && $(bin2fex <"/boot/script.bin" 2>/dev/null | grep -w "hdmi_used = 1") ]]; then
			setterm -default
			echo -e "\nYour display settings are currently 720p (1280x720). To change this use the"
			echo -e "h3disp utility. Do you want to change display settings now? [nY] \c"
			read -n1 ConfigureDisplay
			if [ "X${ConfigureDisplay}" != "Xn" -a "X${ConfigureDisplay}" != "XN" ]; then
				echo -e "\n" ; /usr/local/bin/h3disp
			else
				echo -e "\n"
			fi
		fi

		# check whether desktop environment has to be considered
		if [ -f /etc/init.d/nodm ] ; then
			sed -i "s/NODM_USER=\(.*\)/NODM_USER=${RealUserName}/" /etc/default/nodm
			sed -i "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" /etc/default/nodm
			if [[ -z $ConfigureDisplay || $ConfigureDisplay == n || $ConfigureDisplay == N ]]; then
				echo -e "\n\e[1m\e[39mNow starting desktop environment...\x1B[0m\n"
				sleep 3
				service nodm stop
				sleep 1
				service nodm start
			fi
		fi
	fi
fi
