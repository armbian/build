# @description Opens an interactive root shell inside the image rootfs during the build, after all other customization. The build continues when the shell exits. Cross-architecture builds run the shell through qemu-user. Needs a terminal; the build stops with an error without one.

#
# SPDX-License-Identifier: GPL-2.0
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# Usage: ./compile.sh BOARD=... ENABLE_EXTENSIONS=interactive-shell

function extension_prepare_config__interactive_shell_image_suffix() {
	EXTRA_IMAGE_SUFFIXES+=("-customized")
}

# Switched to opt-out making possibly created user home dirs in the image persistent
declare -g INCLUDE_HOME_DIR="${INCLUDE_HOME_DIR:-yes}"

# Stop the build if no terminal is available.
function interactive_shell_require_terminal() {
	# Subshell: the redirection must not stick. "<>" tests read and write access.
	if ! (exec <> /dev/tty) 2> /dev/null; then
		exit_with_error "interactive-shell: no terminal available. Run the build from a terminal, or disable the extension."
	fi
}

# Stop processes that the session left in the chroot. They keep its mounts busy.
function interactive_shell_stop_leftovers() {
	declare sdcard_real proc_root pid
	declare -a leftover_pids=()
	sdcard_real="$(realpath "${SDCARD}")"
	for proc_root in /proc/[0-9]*/root; do
		[[ "$(readlink "${proc_root}" 2> /dev/null)" == "${sdcard_real}" ]] || continue
		pid="${proc_root#/proc/}"
		leftover_pids+=("${pid%/root}")
	done
	if [[ ${#leftover_pids[@]} -gt 0 ]]; then
		display_alert "Stopping processes left in the chroot" "PIDs: ${leftover_pids[*]}" "wrn"
		kill -TERM "${leftover_pids[@]}" 2> /dev/null || true
		sleep 2
		kill -KILL "${leftover_pids[@]}" 2> /dev/null || true
	fi
	return 0
}

# Fail early: config time is minutes before the shell starts.
function extension_prepare_config__interactive_shell() {
	if [[ "${CONFIG_DEFS_ONLY}" != "yes" && "${BUILDING_IMAGE}" == "yes" ]]; then
		interactive_shell_require_terminal
	fi
}

# 999: run after all other customization. All apt repos are enabled at this hook.
function post_repo_customize_image__999_interactive_shell() {
	interactive_shell_require_terminal

	# The rootfs has no apt lists at this point. Fetch them, so that "apt install" works at once.
	display_alert "Updating apt lists in the chroot" "${EXTENSION}" "info"
	chroot_sdcard apt-get update || display_alert "apt-get update failed" "run it by hand in the shell" "wrn"

	# Use a terminal type that the rootfs knows.
	declare shell_term="${TERM:-xterm}"
	if [[ ! -e "${SDCARD}/usr/share/terminfo/${shell_term:0:1}/${shell_term}" && ! -e "${SDCARD}/lib/terminfo/${shell_term:0:1}/${shell_term}" ]]; then
		shell_term="xterm"
	fi

	# Clean environment: the build environment holds host paths.
	declare -a shell_env=(
		"HOME=/root" "USER=root" "LOGNAME=root"
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
		"TERM=${shell_term}" "LANG=C.UTF-8"
		"debian_chroot=armbian-build" # shown in the default Debian and Ubuntu prompt
		"HISTFILE=/tmp/.bash_history" # /tmp is a tmpfs here: the history stays out of the image
	)
	if [[ -n "${QEMU_CPU}" ]]; then
		shell_env+=("QEMU_CPU=${QEMU_CPU}") # qemu-user reads it
	fi

	display_alert "Starting interactive shell in the image rootfs" "${BOARD} ${RELEASE} ${ARCH}; 'exit' continues the build" "info"
	display_alert "Not kept in the image" "/tmp /var/tmp /run; the build rewrites /etc/fstab and /etc/resolv.conf" "info"

	# Hook stdin and stdout are not the terminal: use /dev/tty. Close fd 13, the log pipe.
	# No login shell: a login shell starts armbian-firstlogin.
	declare -i shell_rc=0
	printf '\n\n' > /dev/tty # set the prompt apart from the build output
	env -i "${shell_env[@]}" chroot "${SDCARD}" /bin/bash -i < /dev/tty > /dev/tty 2>&1 13>&- || shell_rc=$?
	display_alert "Interactive shell closed" "exit code ${shell_rc}; build continues" "info"

	interactive_shell_stop_leftovers

	# Restore the apt state that the next build steps expect: no lists, no cached packages.
	chroot_sdcard apt-get clean
	run_host_command_logged rm -rf "${SDCARD}/var/lib/apt/lists"
}
