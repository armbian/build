function add_host_dependencies__patch_deboostrap(){
exit 0
	echo "Patching Debootstrap to support Ubuntu Noble"
	DEBOOTSTRAP_FOLDER="/usr/share/debootstrap/scripts"
	if [ -L "${DEBOOTSTRAP_FOLDER}/noble" ] && [ -e "${DEBOOTSTRAP_FOLDER}/noble" ]; then
		:
	else
		if ! command -v sudo &> /dev/null; then
			run_host_command_logged mkdir -p ${DEBOOTSTRAP_FOLDER}; ln -s gutsy ${DEBOOTSTRAP_FOLDER}/noble
		else
			run_host_command_logged sudo mkdir -p ${DEBOOTSTRAP_FOLDER}; sudo ln -s gutsy ${DEBOOTSTRAP_FOLDER}/noble
		fi
	fi

}
