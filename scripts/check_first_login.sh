#!/bin/bash
# only do this for interactive shells
if [ "$-" != "${-#*i}" ]; then
	if [ -f "$HOME/.not_logged_in_yet" ]; then
		echo -e "\n\e[0;31mThank you for choosing Armbian! Support: \e[1m\e[39mwww.armbian.com\x1B[0m\n"
		echo -e "Creating new account. Please provide a username (eg. your forename): \c"
		read username
		RealUserName="$(echo "${username}" | tr '[:upper:]' '[:lower:]' | tr -d -c '[:alpha:]')"
		adduser ${RealUserName} || reboot
		for additionalgroup in sudo netdev audio video dialout plugdev ; do
			usermod -aG ${additionalgroup} ${RealUserName}
		done
		rm -f "$HOME/.not_logged_in_yet"
		RealName="$(awk -F":" "/^${RealUserName}:/ {print \$5}" </etc/passwd | cut -d',' -f1)"
		echo -e "\nDear ${RealName}, your account ${RealUserName} has been created and is sudo enabled."
		echo -e "Please use this account for your daily work from now on.\n"
		# check whether desktop environment has to be considered
		if [ -f /etc/init.d/nodm ] ; then 
			sed -i "s/NODM_USER=\(.*\)/NODM_USER=${RealUserName}/" /etc/default/nodm
			sed -i "s/NODM_ENABLED=\(.*\)/NODM_ENABLED=true/g" /etc/default/nodm
			# update-rc.d nodm enable >/dev/null 2>&1
			echo -e "\n\e[1m\e[39mOne more reboot necessary...\x1B[0m\n"
			sleep 1
			reboot
		fi
	fi
fi
