#!/usr/bin/env bash

function pre_umount_final_image__install_fake_vcgencmd() {
	display_alert "Installing fake vcgencmd" "${EXTENSION}" "info"

	if [[ $BOARD != rpi4b ]]; then
		run_host_command_logged curl -vo "${MOUNT}"/usr/bin/vcgencmd "https://raw.githubusercontent.com/clach04/fake_vcgencmd/0.0.2/vcgencmd"
		run_host_command_logged chmod -v 755 "${MOUNT}"/usr/bin/vcgencmd

		run_host_command_logged mkdir -vp "${MOUNT}"/usr/share/doc/fake_vcgencmd
		run_host_command_logged curl -vo "${MOUNT}"/usr/share/doc/fake_vcgencmd/LICENSE "https://raw.githubusercontent.com/clach04/fake_vcgencmd/0.0.2/LICENSE"
		run_host_command_logged curl -vo "${MOUNT}"/usr/share/doc/fake_vcgencmd/README.md "https://raw.githubusercontent.com/clach04/fake_vcgencmd/0.0.2/README.md"
	else
		display_alert "Omitting installattion on Raspberry Pi boards as these ship the original vcgencmd" "${EXTENSION}" "info"
	fi
}
