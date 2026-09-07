# @description Preinstalls OpenMediaVault (OMV), the NAS web management platform, into the image. Runs `armbian-config --api module_omv install` in the chroot after repo customization and appends an `-omv` image suffix. Only supported on Debian `bookworm` and `trixie`; the build errors out on any other release.

function extension_prepare_config__omv() {
	case "${RELEASE}" in
		bookworm|trixie)
			display_alert "Target image will have OpenMediaVault (OMV) preinstalled" "${RELEASE} ${EXTENSION}" "info"
			;;
		*)
			exit_with_error "OpenMediaVault (OMV) is not supported on ${DISTRIBUTION} ${RELEASE}"
			;;
	esac
	EXTRA_IMAGE_SUFFIXES+=("-omv") # global array
}

function post_repo_customize_image__install_omv_packages(){
	display_alert "Adding OpenMediaVault (OMV) package for release ${RELEASE}" "${EXTENSION}" "info"
	chroot_sdcard "armbian-config --api module_omv install"
}
