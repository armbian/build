enable_extension "image-output-qcow2"

#### *run before installing host dependencies*
function add_host_dependencies__vhdx_host_deps() {
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} qemu-utils"
}

#### *allow extensions to prepare their own config, after user config is done*
function extension_prepare_config__prepare_vhdx_config() {
	declare -g VHDX_KEEP_QCOW2="${VHDX_KEEP_QCOW2:-no}" # keep the qcow2 image after conversion to OVF
	declare -g VHDX_KEEP_IMG="${VHDX_KEEP_IMG:-no}"     # keep the .img image after conversion to OVF
}

#### *custom post build hook*
function post_build_image__920_create_vhdx() {
	local VHDX_VM_NAME="${VHDX_VM_NAME:-${version}}"          # The name of the VM when imported into Fusion/Player/Workstation; no spaces please
	local original_qcow2_image="${QCOW2_IMAGE_FILE}"          # Original from qcow2 output extension
	local temp_qcow2_image="${DESTIMG}/${version}_temp.qcow2" # shadow qcow2 for resize

	local base_hyperv_dir="${VHDX_VM_NAME}_hyperv"                                 # directory for vmx format, name only
	local full_hyperv_dirname="${DESTIMG}/${base_hyperv_dir}"                      # directory for vmx format, full path
	local full_pwsh_filename="${full_hyperv_dirname}/${VHDX_VM_NAME}.createVM.ps1" # vmx in vmx format dir
	local base_file_vhdx="${VHDX_VM_NAME}-disk1-efi-rootfs.vhdx"                   # target temp vhdx (filename)
	local full_file_vhdx="${full_hyperv_dirname}/${base_file_vhdx}"                # target temp vhdx (full path)
	local final_vmx_zip_file="${DESTIMG}/${VHDX_VM_NAME}.hyperv.zip"               # final vmx zip artifact - defaults to UEFI boot
	mkdir -p "${full_hyperv_dirname}"                                              # pre-create it

	display_alert "Converting image to Microsoft Hyper-V VHDX format" "${EXTENSION}" "info"
	run_host_command_logged qemu-img create -f qcow2 -F qcow2 -b "${original_qcow2_image}" "${temp_qcow2_image}"             # create a new, temporary, qcow2 with the original as backing image
	run_host_command_logged qemu-img resize "${temp_qcow2_image}" +47G                                                       # resize the temporary
	run_host_command_logged qemu-img convert -f qcow2 -O vhdx -o subformat=dynamic "${temp_qcow2_image}" "${full_file_vhdx}" # convert the big temp to vhdx
	run_host_command_logged rm -vf "${temp_qcow2_image}"                                                                     # remove the temporary large qcow2, free space
	if [[ "${VHDX_KEEP_QCOW2}" != "yes" ]]; then                                                                             # check if told to keep the qcow2 image
		display_alert "Discarding qcow2 image after" "conversion to VHDX" "debug"                                               # debug
		run_host_command_logged rm -vf "${original_qcow2_image}"                                                                # remove the original qcow2, free space
	fi                                                                                                                       # /check
	if [[ "${VHDX_KEEP_IMG}" != "yes" ]]; then                                                                               # check if told to keep the img image
		display_alert "Discarding .img image after" "conversion to VHDX" "debug"                                                # debug
		run_host_command_logged rm -vf "${DESTIMG}/${version}.img" "${DESTIMG}/${version}.img.txt"                              # remove the original .img and .img.txt if there
	fi                                                                                                                       # /check
	run_host_command_logged qemu-img info "${full_file_vhdx}"                                                                # show info

	display_alert "Creating powershell script file" "${EXTENSION}" "info"

	cat <<- POWERSHELL > "${full_pwsh_filename}"
		# some powershell stuff @TODO
	POWERSHELL

	# Now wrap the .vmx in a zip, with minimal compression. (release will .zst it later)
	display_alert "Zipping/storing Hyper-V VHDX" "${EXTENSION}" "info"
	cd "${DESTIMG}" || false
	run_host_command_logged zip -0 "${final_vmx_zip_file}" "${base_hyperv_dir}"/*
	cd - || false

	display_alert "Done, cleaning up" "${EXTENSION}" "info"
	rm -rf "${full_hyperv_dirname}"
	return 0
}
