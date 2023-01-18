function check_windows_wsl2() {
	declare wsl2_type
	wsl2_detect_type
	case "${wsl2_type}" in
		"none")
			return 0 # not on any type of WSDL1/2/Windows, move along
			;;
		"WSL2")
			display_alert "Detected WSL2 - experimental support" "Windows Subsystem for Linux 2" "info"
			wsl2_pester_user_for_terminal # Pester user for a correct terminal
			return 0
			;;
		*)
			exit_with_error "Unsupported Windows scenario: ${wsl2_type}"
			;;
	esac
}

function wsl2_pester_user_for_terminal() {
	[[ "x${SSH_CLIENT}x" != "xx" ]] && return 0 # not if being accessed over SSH
	[[ "x${WT_SESSION}x" != "xx" ]] && return 0 # WT_SESSION from Windows Terminal # From info in https://stackoverflow.com/questions/59733731/how-to-detect-if-running-in-the-new-windows-terminal

	if [[ "${PESTER_TERMINAL}" != "no" ]]; then # Or, send a PR with detection code for your favorite Windows UTF-8 capable terminal.
		display_alert "Please use a terminal that supports UTF-8. For example:" "Windows Terminal" "warn"
		display_alert "Get it at the Microsoft Store" "https://apps.microsoft.com/store/detail/windows-terminal/9N0DX20HK701" "warn"
		exit_if_countdown_not_aborted 10 "WSL2 Terminal does not support UTF-8" # This pauses & exits if error if ENTER is not pressed in 10 seconds
	fi

	return 0
}

# From info in https://github.com/microsoft/WSL/issues/4071
function wsl2_detect_type() {
	wsl2_type="none" # outer scope var
	declare unameOut
	unameOut="$(uname -a)"
	case "${unameOut}" in
		*"microsoft-standard-WSL2"*) wsl2_type="WSL2" ;;
		*"Microsoft"*) wsl2_type="WSL1" ;; # @TODO: do these catch Azure? send a PR!
		*"microsoft"*) wsl2_type="WSL2" ;;
		"CYGWIN"*) wsl2_type="cygwin" ;;
		"MINGW"*) wsl2_type="windows" ;;
		*"Msys") wsl2_type="windows" ;;
	esac
}
