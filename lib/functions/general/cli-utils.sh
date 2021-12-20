# Misc functions from compile.sh



#  Add the variables needed at the beginning of the path
check_args() {
	for p in "$@"; do
		case "${p%=*}" in
			LIB_TAG)
				# Take a variable if the branch exists locally
				if [ "${p#*=}" == "$(git branch |
					gawk -v b="${p#*=}" '{if ( $NF == b ) {print $NF}}')" ]; then
					echo -e "[\e[0;35m warn \x1B[0m] Setting $p"
					eval "$p"
				else
					echo -e "[\e[0;35m warn \x1B[0m] Skip $p setting as LIB_TAG=\"\""
					eval LIB_TAG=""
				fi
				;;
		esac
	done
}

update_src() {
	cd "${SRC}" || exit
	if [[ ! -f "${SRC}"/.ignore_changes ]]; then
		echo -e "[\e[0;32m o.k. \x1B[0m] This script will try to update"

		CHANGED_FILES=$(git diff --name-only)
		if [[ -n "${CHANGED_FILES}" ]]; then
			echo -e "[\e[0;35m warn \x1B[0m] Can't update since you made changes to: \e[0;32m\n${CHANGED_FILES}\x1B[0m"
			while true; do
				echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m or \e[0;33mexit\x1B[0m to abort compilation" \
					", \e[0;33m<Enter>\x1B[0m to ignore and continue, \e[0;33mdiff\x1B[0m to display changes"
				read -r
				if [[ "${REPLY}" == "diff" ]]; then
					git diff
				elif [[ "${REPLY}" == "exit" ]]; then
					exit 1
				elif [[ "${REPLY}" == "" ]]; then
					break
				else
					echo "Unknown command!"
				fi
			done
		elif [[ $(git branch | grep "*" | awk '{print $2}') != "${LIB_TAG}" && -n "${LIB_TAG}" ]]; then
			git checkout "${LIB_TAG:-master}"
			git pull
		fi
	fi

}
