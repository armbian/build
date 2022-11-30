#!/usr/bin/env bash
# Myy : Menu configuration for choosing desktop configurations
show_menu() {
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3
	# Myy : I don't know why there's a TTY_Y - 8...
	#echo "Provided title : $provided_title"
	#echo "Provided backtitle : $provided_backtitle"
	#echo "Provided menuname : $provided_menuname"
	#echo "Provided options : " "${@:4}"
	#echo "TTY X: $TTY_X Y: $TTY_Y"
	dialog --stdout --title "$provided_title" --backtitle "${provided_backtitle}" \
		--menu "$provided_menuname" $TTY_Y $TTY_X $((TTY_Y - 8)) "${@:4}"
}

# Myy : FIXME Factorize
show_select_menu() {
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3
	dialog --stdout --title "${provided_title}" --backtitle "${provided_backtitle}" \
		--checklist "${provided_menuname}" $TTY_Y $TTY_X $((TTY_Y - 8)) "${@:4}"
}

function distro_menu() {
	# create a select menu for choosing a distribution based EXPERT status

	local distrib_dir="${1}"

	if [[ -d "${distrib_dir}" && -f "${distrib_dir}/support" ]]; then
		local support_level="$(cat "${distrib_dir}/support")"
		if [[ "${support_level}" != "supported" && $EXPERT != "yes" ]]; then
			:
		else
			local distro_codename="$(basename "${distrib_dir}")"
			local distro_fullname="$(cat "${distrib_dir}/name")"
			local expert_infos=""
			[[ $EXPERT == "yes" ]] && expert_infos="(${support_level})"
			options+=("${distro_codename}" "${distro_fullname} ${expert_infos}")
		fi
	fi

}

function distros_options() {
	for distrib_dir in "${DISTRIBUTIONS_DESC_DIR}/"*; do
		distro_menu "${distrib_dir}"
	done
}

show_developer_warning() {
	local temp_rc
	temp_rc=$(mktemp)
	cat <<- 'EOF' > "${temp_rc}"
		screen_color = (WHITE,RED,ON)
	EOF
	local warn_text="You are switching to the \Z1EXPERT MODE\Zn

	This allows building experimental configurations that are provided
	\Z1AS IS\Zn to developers and expert users,
	\Z1WITHOUT ANY RESPONSIBILITIES\Zn from the Armbian team:

	- You are using these configurations \Z1AT YOUR OWN RISK\Zn
	- Bug reports related to the dev kernel, CSC, WIP and EOS boards
	\Z1will be closed without a discussion\Zn
	- Forum posts related to dev kernel, CSC, WIP and EOS boards
	should be created in the \Z2\"Community forums\"\Zn section
	"
	DIALOGRC=$temp_rc dialog --title "Expert mode warning" --backtitle "${backtitle}" --colors --defaultno --no-label "I do not agree" \
		--yes-label "I understand and agree" --yesno "$warn_text" "${TTY_Y}" "${TTY_X}"
	[[ $? -ne 0 ]] && exit_with_error "Error switching to the expert mode"
	SHOW_WARNING=no
}
