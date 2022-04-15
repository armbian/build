add_apt_sources() {
	local potential_paths=""
	local sub_dirs_to_check=". "
	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		sub_dirs_to_check+="config_${SELECTED_CONFIGURATION}"
	fi

	# @TODO: rpardini: The logic here is meant to be evolved over time. Originally, all of this only ran when BUILD_DESKTOP=yes.
	#                  Igor had bumped it to run on all builds, but that adds external sources to cli and minimal.
	#                  Here I'm tuning it down to 1/4th of the original, eg: no nala on my cli builds, thanks.
	[[ "${BUILD_MINIMAL}" != "yes" ]] && get_all_potential_paths "${DEBOOTSTRAP_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}" "sources/apt"
	[[ "${BUILD_DESKTOP}" == "yes" ]] && get_all_potential_paths "${CLI_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}" "sources/apt"
	[[ "${BUILD_DESKTOP}" == "yes" ]] && get_all_potential_paths "${DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS}" "." "sources/apt"
	[[ "${BUILD_DESKTOP}" == "yes" ]] && get_all_potential_paths "${DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS}" "${DESKTOP_APPGROUPS_SELECTED}" "sources/apt"

	display_alert "Adding additional apt sources" "add_apt_sources()" "debug"

	for apt_sources_dirpath in ${potential_paths}; do
		if [[ -d "${apt_sources_dirpath}" ]]; then
			for apt_source_filepath in "${apt_sources_dirpath}/"*.source; do
				apt_source_filepath=$(echo "${apt_source_filepath}" | sed -re 's/(^.*[^/])\.[^./]*$/\1/')
				local new_apt_source
				local apt_source_gpg_filepath
				local apt_source_gpg_filename
				local apt_source_filename

				new_apt_source="$(cat "${apt_source_filepath}.source")"
				apt_source_gpg_filepath="${apt_source_filepath}.gpg"
				apt_source_gpg_filename="$(basename "${apt_source_gpg_filepath}")"
				apt_source_filename="$(basename "${apt_source_filepath}").list"

				display_alert "Adding APT Source" "${new_apt_source}" "info"

				# @TODO: rpardini, why do PPAs get apt-key and others get keyrings GPG?

				if [[ "${new_apt_source}" == ppa* ]]; then
					chroot_sdcard add-apt-repository -y -n "${new_apt_source}" # -y -> Assume yes, -n -> no apt-get update
					if [[ -f "${apt_source_gpg_filepath}" ]]; then
						display_alert "Adding GPG Key" "via apt-key add (deprecated): ${apt_source_gpg_filename}" "warn"
						run_host_command_logged cp -pv "${apt_source_gpg_filepath}" "${SDCARD}/tmp/${apt_source_gpg_filename}"
						chroot_sdcard apt-key add "/tmp/${apt_source_gpg_filename}"
					fi
				else
					# installation without software-common-properties, sources.list + key.gpg
					echo "${new_apt_source}" > "${SDCARD}/etc/apt/sources.list.d/${apt_source_filename}"
					if [[ -f "${apt_source_gpg_filepath}" ]]; then
						display_alert "Adding GPG Key" "via keyrings: ${apt_source_gpg_filename}" "warn"
						mkdir -p "${SDCARD}"/usr/share/keyrings/
						run_host_command_logged cp -pv "${apt_source_gpg_filepath}" "${SDCARD}"/usr/share/keyrings/
					fi
				fi

			done
		fi
	done
}
