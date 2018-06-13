#!/bin/sh

if [ -f "${HOME}/.activate_psd" ]; then
	rm -f ${HOME}/.activate_psd
	/usr/bin/psd >/dev/null 2>&1
	config_file="${HOME}/.config/psd/psd.conf"
	if [ -f "${config_file}" ]; then
		# test for overlayfs
		# TODO: don't enable on btrfs
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
fi
