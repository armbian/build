# Config
function extension_prepare_config__prepare_package_list_utils() {
	export DEBUG_PACKAGE_LISTS=${DEBUG_PACKAGE_LISTS:-false} # =yes for debugging, package list assembly can be confusing.
}

# PACKAGE_LIST_RM is unreliable due to sed bizarreness. Do it forcibly.
function remove_packages_everywhere() {
	for one_pkg in "${@}"; do
		local one_pkg_to_remove=" ${one_pkg}"                                                # with a space
		export PACKAGE_LIST_RM="${PACKAGE_LIST_RM} ${one_pkg_to_remove}"                     # This does not really work.
		export PACKAGE_LIST_BOARD_REMOVE="${PACKAGE_LIST_BOARD_REMOVE} ${one_pkg_to_remove}" # This will cause it to be apt-removed if installed.
		# add a space...
		export DEBOOTSTRAP_LIST=" ${DEBOOTSTRAP_LIST}"
		export PACKAGE_LIST_ADDITIONAL=" ${PACKAGE_LIST_ADDITIONAL}"
		export PACKAGE_LIST=" ${PACKAGE_LIST}"
		# no quotes, let it expand
		export DEBOOTSTRAP_LIST=${DEBOOTSTRAP_LIST//${one_pkg_to_remove}/}
		export PACKAGE_LIST_ADDITIONAL=${PACKAGE_LIST_ADDITIONAL//${one_pkg_to_remove}/}
		export PACKAGE_LIST=${PACKAGE_LIST//${one_pkg_to_remove}/}
	done
}

user_config__200_debug_package_lists_early() {
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list DEBOOTSTRAP_LIST          (early)" "${DEBOOTSTRAP_LIST}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST              (early)" "${PACKAGE_LIST}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_ADDITIONAL   (early)" "${PACKAGE_LIST_ADDITIONAL}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_FAMILY       (early)" "${PACKAGE_LIST_FAMILY}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_BOARD_REMOVE (early)" "${PACKAGE_LIST_BOARD_REMOVE}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_RM           (early)" "${PACKAGE_LIST_RM}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_EXCLUDE      (early)" "${PACKAGE_LIST_EXCLUDE}" "info"
}

user_config_post_aggregate_packages__800_debug_package_lists_after_aggregation() {
	# Show lists:
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list DEBOOTSTRAP_LIST          (super-final)) " "${DEBOOTSTRAP_LIST}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST              (super-final)) " "${PACKAGE_LIST}" "info"
	[[ "${DEBUG_PACKAGE_LISTS}" != "false" ]] && display_alert "Package list PACKAGE_LIST_BOARD_REMOVE (super-final)) " "${PACKAGE_LIST_BOARD_REMOVE}" "info"
}
