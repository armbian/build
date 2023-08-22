#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#

# tl;dr: this function will return the version and download URL of a package.
# it is very naive, and will only look into a few repos across Debian/Ubuntu.
function apt_find_upstream_package_version_and_download_url() {
	declare sought_package_name="${1}"

	declare -a package_info_download_urls=()
	declare first_letter_of_sought_package_name="${sought_package_name:0:1}"
	declare mirror_with_slash="undetermined/"

	case "${DISTRIBUTION}" in
		Ubuntu) # try both the jammy-updates and jammy repos, use whatever returns first
			package_info_download_urls+=("https://packages.ubuntu.com/${RELEASE}-updates/${ARCH}/${sought_package_name}/download")
			package_info_download_urls+=("https://packages.ubuntu.com/${RELEASE}/${ARCH}/${sought_package_name}/download")
			mirror_with_slash="${UBUNTU_MIRROR}"
			;;

		Debian)
			package_info_download_urls+=("https://packages.debian.org/${RELEASE}/${ARCH}/${sought_package_name}/download")
			mirror_with_slash="${DEBIAN_MIRROR}"
			;;

		*)
			exit_with_error "Unknown distribution '${DISTRIBUTION}'"
			;;
	esac

	# if mirror_with_slash does not end with a slash, add it
	if [[ "${mirror_with_slash}" != */ ]]; then
		mirror_with_slash="${mirror_with_slash}/"
	fi

	declare base_down_url="http://${mirror_with_slash}pool/main/${first_letter_of_sought_package_name}/${sought_package_name}"

	declare index package_info_download_url
	# loop over the package_info_download_urls with index and value
	for index in "${!package_info_download_urls[@]}"; do
		package_info_download_url="${package_info_download_urls[$index]}"
		display_alert "Testing URL" "${package_info_download_url}" "debug"

		declare package_info_download_url_file
		package_info_download_url_file="$(mktemp)"
		curl --silent --show-error --max-time 10 "${package_info_download_url}" > "${package_info_download_url_file}" || true # don't fail
		declare package_info_download_url_file_package_name                                                                   # grep the file for the package name. parse "<kbd>name</kbd>"
		package_info_download_url_file_package_name="$(grep -oP '(?<=<kbd>)[^<]+' "${package_info_download_url_file}" | grep "^${sought_package_name}_" | head -n 1)"
		rm -f "${package_info_download_url_file}"

		display_alert "Package name parsed" "${package_info_download_url_file_package_name}" "debug"
		if [[ "${package_info_download_url_file_package_name}" == "${sought_package_name}_"* ]]; then
			found_package_filename="${package_info_download_url_file_package_name}"
			found_package_down_url="${base_down_url}/${found_package_filename}"
			display_alert "Found package filename" "${found_package_filename} in url ${package_info_download_url}" "debug"
			break
		fi
	done

	if [[ "${found_package_filename}" == "${sought_package_name}_"* ]]; then
		display_alert "Found upstream base-files package filename" "${found_package_filename}" "info"
	else
		display_alert "Could not find package filename for '${sought_package_name}' in '${package_info_download_urls[*]}'" "looking for ${sought_package_name}" "warn"
		return 1
	fi

	# Now we have the package name, lets parse out the version.
	found_package_version="$(echo "${found_package_filename}" | grep -oP '(?<=_)[^_]+(?=_)')"
	display_alert "Found base-files upstream package version" "${found_package_version}" "info"

	# Sanity check...
	declare wanted_package_name="${sought_package_name}_${found_package_version}_${ARCH}.deb"
	if [[ "${found_package_filename}" != "${wanted_package_name}" ]]; then
		display_alert "Found package filename '${found_package_filename}' does not match wanted package name '${wanted_package_name}'" "looking for ${sought_package_name}" "warn"
		return 1
	fi

	# show found_package_down_url
	display_alert "Found package download url" "${found_package_down_url}" "debug"

	return 0
}
