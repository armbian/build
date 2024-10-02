enable_extension "image-output-qcow2"

#### *run before installing host dependencies*
function add_host_dependencies__ovf_host_deps() {
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} qemu-utils"
}

#### *allow extensions to prepare their own config, after user config is done*
function extension_prepare_config__prepare_ovf_config() {
	declare -g OVF_VM_CPUS="${OVF_VM_CPUS:-4}"        # Number of CPUs
	declare -g OVF_VM_RAM_GB="${OVF_VM_RAM_GB:-4}"    # RAM in Gigabytes
	declare -g OVF_KEEP_QCOW2="${OVF_KEEP_QCOW2:-no}" # keep the qcow2 image after conversion to OVF
	declare -g OVF_KEEP_IMG="${OVF_KEEP_IMG:-no}"     # keep the .img image after conversion to OVF
}

#### *custom post build hook*
function post_build_image__920_create_ovf() {
	local OVF_VM_NAME="${OVF_VM_NAME:-${version}}"            # The name of the VM when imported into Fusion/Player/Workstation; no spaces please
	local original_qcow2_image="${QCOW2_IMAGE_FILE}"          # Original from qcow2 output extension
	local temp_qcow2_image="${DESTIMG}/${version}_temp.qcow2" # shadow qcow2 for resize

	local base_vmware_dirname="${OVF_VM_NAME}_vmware"                   # directory for vmx format, name only
	local full_vmware_dirname="${DESTIMG}/${base_vmware_dirname}"       # directory for vmx format, full path
	local full_vmx_filename="${full_vmware_dirname}/${OVF_VM_NAME}.vmx" # vmx in vmx format dir
	local base_file_vmdk="${OVF_VM_NAME}-disk1-efi-rootfs.vmdk"         # target temp vmdk (filename)
	local full_file_vmdk="${full_vmware_dirname}/${base_file_vmdk}"     # target temp vmdk (full path)
	local final_vmx_zip_file="${DESTIMG}/${OVF_VM_NAME}.vmware.zip"     # final vmx zip artifact - defaults to UEFI boot
	mkdir -p "${full_vmware_dirname}"                                   # pre-create it

	display_alert "Converting image to OVF-compatible VMDK format" "${EXTENSION}" "info"
	run_host_command_logged qemu-img create -f qcow2 -F qcow2 -b "${original_qcow2_image}" "${temp_qcow2_image}" # create a new, temporary, qcow2 with the original as backing image
	run_host_command_logged qemu-img resize "${temp_qcow2_image}" +47G                                           # resize the temporary
	run_host_command_logged qemu-img convert -f qcow2 -O vmdk "${temp_qcow2_image}" "${full_file_vmdk}"          # convert the big temp to vmdk
	run_host_command_logged rm -vf "${temp_qcow2_image}"                                                         # remove the temporary large qcow2, free space
	if [[ "${OVF_KEEP_QCOW2}" != "yes" ]]; then                                                                  # check if told to keep the qcow2 image
		display_alert "Discarding qcow2 image after" "conversion to VMDK" "debug"                                   # debug
		run_host_command_logged rm -vf "${original_qcow2_image}"                                                    # remove the original qcow2, free space
	fi                                                                                                           # /check
	if [[ "${OVF_KEEP_IMG}" != "yes" ]]; then                                                                    # check if told to keep the img image
		display_alert "Discarding .img image after" "conversion to OVF" "debug"                                     # debug
		run_host_command_logged rm -vf "${DESTIMG}/${version}.img" "${DESTIMG}/${version}.img.txt"                  # remove the original .img and .img.txt if there
	fi                                                                                                           # /check
	run_host_command_logged qemu-img info "${full_file_vmdk}"                                                    # show info

	display_alert "Creating .vmx file" "${EXTENSION}" "info"

	cat <<- VMX_FILE > "${full_vmx_filename}"
		.encoding = "UTF-8"
		displayname = "${OVF_VM_NAME}"
		guestos = "ubuntu-64"
		virtualhw.version = "18"
		config.version = "8"
		numvcpus = "${OVF_VM_CPUS}"
		cpuid.coresPerSocket = "${OVF_VM_CPUS}"
		memsize = "$((OVF_VM_RAM_GB * 1024))"
		pciBridge0.present = "TRUE"
		pciBridge4.present = "TRUE"
		pciBridge4.virtualDev = "pcieRootPort"
		pciBridge4.functions = "8"
		pciBridge5.present = "TRUE"
		pciBridge5.virtualDev = "pcieRootPort"
		pciBridge5.functions = "8"
		pciBridge6.present = "TRUE"
		pciBridge6.virtualDev = "pcieRootPort"
		pciBridge6.functions = "8"
		pciBridge7.present = "TRUE"
		pciBridge7.virtualDev = "pcieRootPort"
		pciBridge7.functions = "8"
		vmci0.present = "TRUE"
		floppy0.present = "FALSE"
		mks.enable3d = "true"
		scsi0:0.present = "TRUE"
		scsi0:0.deviceType = "disk"
		scsi0:0.fileName = "${base_file_vmdk}"
		scsi0:0.allowguestconnectioncontrol = "false"
		scsi0:0.mode = "persistent"
		scsi0.virtualDev = "pvscsi"
		scsi0.present = "TRUE"
		ethernet0.present = "TRUE"
		ethernet0.virtualDev = "vmxnet3"
		ethernet0.connectionType = "nat"
		ethernet0.startConnected = "TRUE"
		ethernet0.addressType = "generated"
		ethernet0.wakeonpcktrcv = "false"
		ethernet0.allowguestconnectioncontrol = "true"
		sata0.present = "TRUE"
		vmci0.unrestricted = "false"
		vcpu.hotadd = "true"
		mem.hotadd = "true"
		tools.syncTime = "true"
		toolscripts.afterpoweron = "true"
		toolscripts.afterresume = "true"
		toolscripts.beforepoweroff = "true"
		toolscripts.beforesuspend = "true"
		powerType.powerOff = "soft"
		powerType.reset = "soft"
		powerType.suspend = "soft"
		usb.present = "TRUE"
		ehci.present = "TRUE"
		usb_xhci.present = "TRUE"
		hard-disk.hostBuffer = "enabled"
		ulm.disableMitigations = "TRUE"
		vhv.enable = "TRUE"
		vmx.buildType = "release"
		firmware = "efi"
	VMX_FILE

	# Now wrap the .vmx in a zip, with minimal compression. (release will .zst it later)
	display_alert "Zipping/storing vmx" "${EXTENSION}" "info"
	cd "${DESTIMG}" || false
	run_host_command_logged zip -0 "${final_vmx_zip_file}" "${base_vmware_dirname}"/*
	cd - || false

	display_alert "Done, cleaning up" "${EXTENSION}" "info"
	rm -rf "${full_vmware_dirname}"
	return 0
}
