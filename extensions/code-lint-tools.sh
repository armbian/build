function fetch_sources_tools__code_lint_tools() {
	# install lint tools
	sudo apt-get install -y shfmt
	sudo apt-get install -y shellcheck
	sudo bash -c "curl -1sLf 'https://dl.cloudsmith.io/public/evilmartians/lefthook/setup.deb.sh' | sudo -E bash"
	sudo apt install lefthook
}

function build_host_tools__code_lint_tools() {
	# check
	local REQUISITES=('shfmt' 'shellcheck' 'lefthook')
	echo 'Checking code lint tools: '${REQUISITES[@]}
	for cmd in ${REQUISITES[@]}; do
		if [[ -z $(command -v $cmd) ]]; then
			display_alert "${cmd} not installed." "code-lint-tools" "Info"
		fi
	done
}
