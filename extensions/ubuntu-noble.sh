function add_host_dependencies__patch_deboostrap(){

	echo "Patching Debootstrap to support Ubuntu Noble"
	NOBLE_SYMLINK=/usr/share/debootstrap/scripts/noble
	if [ -L ${NOBLE_SYMLINK} ] && [ -e ${NOBLE_SYMLINK} ]; then
		:
	else
		if ! command -v sudo &> /dev/null; then
			run_host_command_logged ln -s gutsy ${NOBLE_SYMLINK}
		else
			run_host_command_logged sudo ln -s gutsy ${NOBLE_SYMLINK}
		fi
	fi

}
