function add_host_dependencies__qcow2_host_deps() {
	[[ "${SKIP_QCOW2}" == "yes" ]] && return 0
	export EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} qemu-utils"
}

function post_build_image__900_convert_to_qcow2_img() {
	[[ "${SKIP_QCOW2}" == "yes" ]] && return 0
	display_alert "Converting image to qcow2" "${EXTENSION}" "info"
	export QCOW2_IMAGE_FILE="${DESTIMG}/${version}.img.qcow2"
	run_host_command_logged qemu-img convert -f raw -O qcow2 "${DESTIMG}/${version}.img" "${QCOW2_IMAGE_FILE}"
	run_host_command_logged qemu-img info "${QCOW2_IMAGE_FILE}"
	if [[ "${QCOW2_RESIZE_AMOUNT}" != "" ]]; then
		display_alert "Resizing qcow2 image by '${QCOW2_RESIZE_AMOUNT}' " "${EXTENSION}" "info"
		qemu-img resize "${QCOW2_IMAGE_FILE}" "${QCOW2_RESIZE_AMOUNT}"
	fi
	if [[ "${QCOW2_KEEP_IMG}" != "yes" ]]; then
		display_alert "Discarding original .img image after" "conversion to qcow2" "info"
		run_host_command_logged rm -vf "${DESTIMG}/${version}.img" "${DESTIMG}/${version}.img.txt"
	fi
}
