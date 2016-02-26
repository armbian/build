#!/bin/bash
# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
	if [ -f "$HOME/.not_logged_in_yet" ]; then
		echo -e "\n\e[0;31mThank you for choosing Armbian! Support: \e[1m\e[39mwww.armbian.com\x1B[0m\n"
		echo -e "Creating new account. Please provide a username (eg. your forename): \c"
		read username
		RealUserName="$(echo "${username}" | tr '[:upper:]' '[:lower:]' | tr -d -c '[:alpha:]')"
		adduser ${RealUserName} || reboot
		usermod -aG sudo ${RealUserName}
		rm -f "$HOME/.not_logged_in_yet"
		# check whether desktop environment has to be considered
		if [ -f /etc/init.d/nodm ] ; then 
			sed -i "s/NODM_USER=root/NODM_USER=${RealUserName}/" /etc/default/nodm
			usermod -aG netdev ${RealUserName}
			update-rc.d nodm enable >/dev/null 2>&1
			echo -e "\n\e[1m\e[39mReboot necessary...\x1B[0m\n"
			reboot
		fi
	fi
fi
