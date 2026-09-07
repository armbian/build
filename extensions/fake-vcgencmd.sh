#!/usr/bin/env bash
# @description Installs a stub `vcgencmd` so Raspberry Pi software that probes it runs on non-Pi boards. Downloads the script (plus LICENSE/README) from `clach04/fake_vcgencmd` v0.0.2 into `/usr/bin/vcgencmd` and makes it executable. Skipped on `rpi4b`, which ships the genuine `vcgencmd`.

function pre_umount_final_image__install_fake_vcgencmd() {
	display_alert "Extension: ${EXTENSION}: Installing fake vcgencmd" "${EXTENSION}" "info"

	if [[ $BOARD != rpi4b ]]; then
		run_host_command_logged curl -vo "${MOUNT}"/usr/bin/vcgencmd "https://raw.githubusercontent.com/clach04/fake_vcgencmd/0.0.2/vcgencmd"
		run_host_command_logged chmod -v 755 "${MOUNT}"/usr/bin/vcgencmd

		run_host_command_logged mkdir -vp "${MOUNT}"/usr/share/doc/fake_vcgencmd
		run_host_command_logged curl -vo "${MOUNT}"/usr/share/doc/fake_vcgencmd/LICENSE "https://raw.githubusercontent.com/clach04/fake_vcgencmd/0.0.2/LICENSE"
		run_host_command_logged curl -vo "${MOUNT}"/usr/share/doc/fake_vcgencmd/README.md "https://raw.githubusercontent.com/clach04/fake_vcgencmd/0.0.2/README.md"
	else
		display_alert "Extension: ${EXTENSION}: Omitting installation on Raspberry Pi boards as these ship the original vcgencmd" "${EXTENSION}" "info"
	fi
}
