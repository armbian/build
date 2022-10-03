# get_package_list_hash
#
# returns md5 hash for current package list and rootfs cache version

get_package_list_hash()
{
	local package_arr exclude_arr
	local list_content
	read -ra package_arr <<< "${DEBOOTSTRAP_LIST} ${PACKAGE_LIST}"
	read -ra exclude_arr <<< "${PACKAGE_LIST_EXCLUDE}"
	(
		printf "%s\n" "${package_arr[@]}"
		printf -- "-%s\n" "${exclude_arr[@]}"
	) | sort -u | md5sum | cut -d' ' -f 1
}

