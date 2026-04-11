# shellcheck shell=bash

function extension_finish_config__install_kernel_headers_for_bcmdhd_spacemit_dkms() {

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]]; then
		display_alert "Kernel version has no working headers package" "skipping bcmdhd-spacemit dkms for kernel v${KERNEL_MAJOR_MINOR}" "warn"
		return 0
	fi
	declare -g INSTALL_HEADERS="yes"
	display_alert "Forcing INSTALL_HEADERS=yes; for use with bcmdhd-spacemit dkms" "${EXTENSION}" "debug"
}

function post_install_kernel_debs__install_bcmdhd_spacemit_dkms_package() {

	[[ "${INSTALL_HEADERS}" != "yes" ]] || [[ "${KERNEL_HAS_WORKING_HEADERS}" != "yes" ]] && return 0
	[[ -z ${BCMDHD_SPACEMIT_TAG} ]] && return 0
	[[ -z ${BCMDHD_SPACEMIT_TYPE} ]] && return 0

	local file_name=
	local pcie_url="https://codeberg.org/sven-ola/bcmdhd-spacemit-dkms/releases/download/${BCMDHD_SPACEMIT_TAG}/bcmdhd-spacemit-pcie-dkms_${BCMDHD_SPACEMIT_TAG#v}_all.deb"
	local sdio_url="https://codeberg.org/sven-ola/bcmdhd-spacemit-dkms/releases/download/${BCMDHD_SPACEMIT_TAG}/bcmdhd-spacemit-sdio-dkms_${BCMDHD_SPACEMIT_TAG#v}_all.deb"
	local usb_url="https://codeberg.org/sven-ola/bcmdhd-spacemit-dkms/releases/download/${BCMDHD_SPACEMIT_TAG}/bcmdhd-spacemit-usb-dkms_${BCMDHD_SPACEMIT_TAG#v}_all.deb"

	case "${BCMDHD_SPACEMIT_TYPE}" in
		"pcie")
			file_name=bcmdhd-spacemit-pcie-dkms_${BCMDHD_SPACEMIT_TAG#v}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${pcie_url} -P /tmp"
			;;
		"sdio")
			file_name=bcmdhd-spacemit-sdio-dkms_${BCMDHD_SPACEMIT_TAG#v}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${sdio_url} -P /tmp"
			;;
		"usb")
			file_name=bcmdhd-spacemit-usb-dkms_${BCMDHD_SPACEMIT_TAG#v}_all.deb
			use_clean_environment="yes" chroot_sdcard "wget ${usb_url} -P /tmp"
			;;
		*)
			return 0
			;;
	esac
	display_alert "Install bcmdhd-spacemit packages, will build kernel module in chroot" "${EXTENSION}" "info"
	# shellcheck disable=SC2034
	declare -ag if_error_find_files_sdcard=("/var/lib/dkms/bcmdhd*/*/build/*.log")
	use_clean_environment="yes" chroot_sdcard_apt_get_install /tmp/"${file_name}"
	use_clean_environment="yes" chroot_sdcard "rm -f /tmp/bcmdhd*.deb"
}
