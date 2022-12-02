#!/usr/bin/env bash
install_ppa_prerequisites() {

	# Myy : So... The whole idea is that, a good bunch of external sources
	# are PPA.
	# Adding PPA without add-apt-repository is poorly conveninent since
	# you need to reconstruct the URL by hand, and find the GPG key yourself.
	# add-apt-repository does that automatically, and in a way that allows you
	# to remove it cleanly through the same tool.

	# Myy : TODO Try to find a way to install this package only when
	# we encounter a PPA.
	run_on_sdcard "DEBIAN_FRONTEND=noninteractive apt-get -yqq update; apt-get install -yqq software-properties-common"

}

add_apt_sources() {

	local potential_paths=""
	local sub_dirs_to_check=". "
	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		sub_dirs_to_check+="config_${SELECTED_CONFIGURATION}"
	fi
	get_all_potential_paths "${DEBOOTSTRAP_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}" "sources/apt"
	get_all_potential_paths "${CLI_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}" "sources/apt"
	get_all_potential_paths "${DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS}" "." "sources/apt"
	get_all_potential_paths "${DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS}" "${DESKTOP_APPGROUPS_SELECTED}" "sources/apt"

	display_alert "Adding additional apt sources"

	for apt_sources_dirpath in ${potential_paths}; do
		if [[ -d "${apt_sources_dirpath}" ]]; then
			for apt_source_filepath in "${apt_sources_dirpath}/"*.source; do
				apt_source_filepath=$(echo $apt_source_filepath | sed -re 's/(^.*[^/])\.[^./]*$/\1/')
				local new_apt_source="$(cat "${apt_source_filepath}.source")"
				local apt_source_gpg_filepath="${apt_source_filepath}.gpg"

				# extract filenames
				local apt_source_gpg_filename="$(basename ${apt_source_gpg_filepath})"
				local apt_source_filename="$(basename ${apt_source_filepath}).list"

				display_alert "Adding APT Source ${new_apt_source}"

				if [[ "${new_apt_source}" == ppa* ]]; then
					install_ppa_prerequisites
					# ppa with software-common-properties
					run_on_sdcard "add-apt-repository -y -n \"${new_apt_source}\""
					# add list with apt-add
					# -y -> Assumes yes to all queries
					# -n -> Do not update package cache after adding
					if [[ -f "${apt_source_gpg_filepath}" ]]; then
						display_alert "Adding GPG Key ${apt_source_gpg_filepath}"
						cp "${apt_source_gpg_filepath}" "${SDCARD}/tmp/${apt_source_gpg_filename}"
						run_on_sdcard "apt-key add \"/tmp/${apt_source_gpg_filename}\""
						echo "APT Key returned : $?"
					fi
				else
					# installation without software-common-properties, sources.list + key.gpg
					echo "${new_apt_source}" > "${SDCARD}/etc/apt/sources.list.d/${apt_source_filename}"
					if [[ -f "${apt_source_gpg_filepath}" ]]; then
						display_alert "Adding GPG Key ${apt_source_gpg_filepath}"
						#						local apt_source_gpg_filename="$(basename ${apt_source_gpg_filepath})"
						mkdir -p "${SDCARD}"/usr/share/keyrings/
						cp "${apt_source_gpg_filepath}" "${SDCARD}"/usr/share/keyrings/
					fi

				fi

			done
		fi
	done

}

add_desktop_package_sources() {

	# Myy : I see Snap and Flatpak coming up in the next releases
	# so... let's prepare for that

	add_apt_sources

	ls -l "${SDCARD}/usr/share/keyrings" >> "${DEST}"/${LOG_SUBPATH}/install.log
	ls -l "${SDCARD}/etc/apt/sources.list.d" >> "${DEST}"/${LOG_SUBPATH}/install.log
	cat "${SDCARD}/etc/apt/sources.list" >> "${DEST}"/${LOG_SUBPATH}/install.log

}
