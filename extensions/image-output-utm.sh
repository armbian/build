enable_extension "image-output-qcow2"

#### *allow extensions to prepare their own config, after user config is done*
function extension_prepare_config__prepare_utm_config() {
	export UTM_VM_CPUS="${UTM_VM_CPUS:-4}"        # Number of CPUs
	export UTM_VM_RAM_GB="${UTM_VM_RAM_GB:-16}"   # RAM in Gigabytes
	export UTM_KEEP_QCOW2="${UTM_KEEP_QCOW2:-no}" # keep the qcow2 image after conversion to UTM
	export UTM_KEEP_IMG="${UTM_KEEP_IMG:-no}"     # keep the .img image after conversion to UTM
}

function user_config__metadata_cloud_config() {
	display_alert "Preparing UTM config" "${EXTENSION}" "info"
	export SERIALCON="ttyS0" # UTM's serial at ttyS0, for x86 @TODO: arm64? ttyAML0?
	display_alert "Prepared UTM config" "${EXTENSION}: SERIALCON: '${SERIALCON}'" "debug"
}

#### *custom post build hook*
function post_build_image__920_create_utm_plist() {
	local UTM_VM_NAME="${UTM_VM_NAME:-${version}}"            # The name of the VM when imported into Fusion/Player/Workstation; no spaces please
	local original_qcow2_image="${QCOW2_IMAGE_FILE}"          # Original from qcow2 output extension
	local temp_qcow2_image="${DESTIMG}/${version}_temp.qcow2" # shadow qcow2 for resize

	local base_utm_dirname="${UTM_VM_NAME}.utm"                           # directory for vmx format, name only
	local full_utm_dirname="${DESTIMG}/${base_utm_dirname}"               # directory for vmx format, full path
	local full_plist_filename="${full_utm_dirname}/config.plist"          # vmx in vmx format dir
	local base_file_rootdisk="${UTM_VM_NAME}-disk1-efi-rootfs.qcow2"      # target temp vmdk (filename)
	local dir_file_rootdisk="${full_utm_dirname}/Images"                  # "Images" is for UTM 3.x, and "Data" for 4.x
	local full_file_rootdisk="${dir_file_rootdisk}/${base_file_rootdisk}" # target temp vmdk (full path)
	local final_plist_zip_file="${DESTIMG}/${UTM_VM_NAME}.utm.zip"        # final vmx zip artifact - defaults to UEFI boot
	mkdir -p "${full_utm_dirname}" "${dir_file_rootdisk}"                 # pre-create it

	display_alert "Converting image to UTM VM format" "${EXTENSION}" "info"
	run_host_command_logged qemu-img create -f qcow2 -F qcow2 -b "${original_qcow2_image}" "${temp_qcow2_image}" # create a new, temporary, qcow2 with the original as backing image
	run_host_command_logged qemu-img resize "${temp_qcow2_image}" +92G                                           # resize the temporary
	run_host_command_logged qemu-img convert -f qcow2 -O qcow2 "${temp_qcow2_image}" "${full_file_rootdisk}"     # convert the big temp to vmdk
	run_host_command_logged rm -vf "${temp_qcow2_image}"                                                         # remove the temporary large qcow2, free space
	if [[ "${UTM_KEEP_QCOW2}" != "yes" ]]; then                                                                  # check if told to keep the qcow2 image
		display_alert "Discarding qcow2 image after" "conversion to UTM VM" "debug"                                 # debug
		run_host_command_logged rm -vf "${original_qcow2_image}"                                                    # remove the original qcow2, free space
	fi                                                                                                           # /check
	if [[ "${UTM_KEEP_IMG}" != "yes" ]]; then                                                                    # check if told to keep the qcow2 image
		display_alert "Discarding .img image after" "conversion to UTM VM" "debug"                                  # debug
		run_host_command_logged rm -vf "${DESTIMG}/${version}.img" "${DESTIMG}/${version}.img.txt"                  # remove the original .img and .img.txt if there
	fi                                                                                                           # /check
	run_host_command_logged qemu-img info "${full_file_rootdisk}"                                                # show info

	local UTM_ARCH UTM_CPU UTM_TARGET
	case "${ARCH}" in
		amd64)
			display_alert "Creating UTM 3.x config.plist file" "${EXTENSION} - amd64" "info"
			UTM_ARCH="x86_64"
			UTM_CPU="host"
			UTM_TARGET="q35"
			;;
		arm64)
			display_alert "Creating UTM 3.x config.plist file" "${EXTENSION} - arm64" "info"
			UTM_ARCH="aarch64"
			UTM_CPU="default"
			UTM_TARGET="virt"
			;;
	esac

	# @TODO: this is for UTM 3.x
	cat <<- UTM_3X_CONFIG_PLIST > "${full_plist_filename}"
		<?xml version="1.0" encoding="UTF-8"?>
		<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
		<plist version="1.0">
		    <dict>
		        <key>ConfigurationVersion</key>
		        <integer>2</integer>
		        <key>Debug</key>
		        <dict/>
		        <key>Display</key>
		        <dict>
		            <key>ConsoleFont</key>
		            <string>Menlo</string>
		            <key>ConsoleFontSize</key>
		            <integer>12</integer>
		            <key>ConsoleOnly</key>
		            <true/>
		            <key>ConsoleTheme</key>
		            <string>Default</string>
		            <key>DisplayCard</key>
		            <string>virtio-vga-gl</string>
		            <key>DisplayDownscaler</key>
		            <string>linear</string>
		            <key>DisplayFitScreen</key>
		            <true/>
		            <key>DisplayUpscaler</key>
		            <string>nearest</string>
		        </dict>
		        <key>Drives</key>
		        <array>
		            <dict>
		                <key>DriveName</key>
		                <string>drive0</string>
		                <key>ImagePath</key>
		                <string>${base_file_rootdisk}</string>
		                <key>ImageType</key>
		                <string>disk</string>
		                <key>InterfaceType</key>
		                <string>virtio</string>
		            </dict>
		        </array>
		        <key>Info</key>
		        <dict>
		            <key>Icon</key>
		            <string>linux</string>
		        </dict>
		        <key>Input</key>
		        <dict>
		            <key>InputLegacy</key>
		            <true/>
		        </dict>
		        <key>Networking</key>
		        <dict>
		            <key>NetworkCard</key>
		            <string>virtio-net-pci</string>
		            <key>NetworkMode</key>
		            <string>shared</string>
		        </dict>
		        <key>Printing</key>
		        <dict/>
		        <key>Sharing</key>
		        <dict>
		            <key>ClipboardSharing</key>
		            <false/>
		            <key>DirectoryReadOnly</key>
		            <false/>
		            <key>DirectorySharing</key>
		            <false/>
		            <key>Usb3Support</key>
		            <false/>
		            <key>UsbRedirectMax</key>
		            <integer>3</integer>
		        </dict>
		        <key>Sound</key>
		        <dict>
		            <key>SoundCard</key>
		            <string>intel-hda</string>
		            <key>SoundEnabled</key>
		            <false/>
		        </dict>
		        <key>System</key>
		        <dict>
		            <key>Architecture</key>
		            <string>${UTM_ARCH}</string>
		            <key>BootDevice</key>
		            <string></string>
		            <key>BootUefi</key>
		            <true/>
		            <key>CPU</key>
		            <string>${UTM_CPU}</string>
		            <key>CPUCount</key>
		            <integer>${UTM_VM_CPUS}</integer>
		            <key>ForcePS2Controller</key>
		            <false/>
		            <key>Memory</key>
		            <integer>$((UTM_VM_RAM_GB * 1024))</integer>
		            <key>RTCUseLocalTime</key>
		            <true/>
		            <key>RngEnabled</key>
		            <true/>
		            <key>Target</key>
		            <string>${UTM_TARGET}</string>
		            <key>UseHypervisor</key>
		            <true/>
		        </dict>
		    </dict>
		</plist>
	UTM_3X_CONFIG_PLIST

	# Now wrap the .vmx in a zip, with minimal compression. (release will .zst it later)
	display_alert "Zipping/storing UTM VM" "${EXTENSION}" "info"
	cd "${DESTIMG}" || false
	run_host_command_logged tree -h .
	run_host_command_logged zip -r -0 "${final_plist_zip_file}" "${base_utm_dirname}"/*
	cd - || false

	display_alert "Done, cleaning up" "${EXTENSION}" "info"
	rm -rf "${full_utm_dirname}"
	return 0
}
