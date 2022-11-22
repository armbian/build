#!/usr/bin/env bash

add_apt_sources() {
	# AGGREGATED_APT_SOURCES and AGGREGATED_APT_SOURCES_DICT are pre-resolved by aggregation.py
	display_alert "Adding additional apt sources" "add_apt_sources()" "debug"
	mkdir -p "${SDCARD}"/usr/share/keyrings/

	for apt_source in "${AGGREGATED_APT_SOURCES[@]}"; do
		apt_source_base="${AGGREGATED_APT_SOURCES_DICT["${apt_source}"]}"
		apt_source_file="${SRC}/${apt_source_base}.source"
		gpg_file="${SRC}/${apt_source_base}.gpg"

		display_alert "Adding APT Source" "${apt_source}" "info"
		# installation without software-common-properties, sources.list + key.gpg
		run_host_command_logged cp -pv "${apt_source_file}" "${SDCARD}/etc/apt/sources.list.d/${apt_source}.list"
		if [[ -f "${gpg_file}" ]]; then
			# @TODO good chance to test the key for expiration date, and WARN if < 60 days, and ERROR if < 30 days
			display_alert "Adding GPG Key" "via keyrings: ${apt_source}.list"
			run_host_command_logged cp -pv "${gpg_file}" "${SDCARD}/usr/share/keyrings/${apt_source}.gpg"
		fi
	done
}
