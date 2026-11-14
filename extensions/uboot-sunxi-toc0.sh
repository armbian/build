# @description Builds a TOC0-signed U-Boot SPL for Allwinner boxes with the secure-boot eFuse burned. Set TOC0_ROOT_KEY to a PEM RSA private key, or put one at userpatches/u-boot/toc0/root_key.pem. TOC0_ROOT_KEY=generate creates a new RSA-2048 key there, if none exists.

#
# SPDX-License-Identifier: GPL-2.0
# Copyright (c) 2026 Armbian
# This file is a part of the Armbian Build Framework https://github.com/armbian/build/
#
# No key is shipped. The BROM accepts any root key while the ROTPK_HASH eFuse
# is not programmed. A device with a programmed ROTPK hash boots only with
# its matching key. Keep the key.

function extension_prepare_config__uboot_sunxi_toc0_key() {
	declare -g TOC0_KEY_FILE="${USERPATCHES_PATH}/u-boot/toc0/root_key.pem"

	if [[ "${TOC0_ROOT_KEY}" == "generate" ]]; then
		command -v openssl > /dev/null || exit_with_error "TOC0: openssl is not installed" "openssl"
		mkdir -p "$(dirname "${TOC0_KEY_FILE}")"
		# One key only, also with parallel builds: check and create under a lock,
		# and publish the complete file with a rename.
		# The subshell returns 0 on success: compile.sh runs with errexit.
		(
			flock 9 || exit 1
			if [[ -f "${TOC0_KEY_FILE}" ]]; then
				display_alert "TOC0: key exists, using it" "${TOC0_KEY_FILE}" "info"
				exit 0
			fi
			umask 077
			openssl genrsa -out "${TOC0_KEY_FILE}.tmp" 2048 || exit 1
			mv -f "${TOC0_KEY_FILE}.tmp" "${TOC0_KEY_FILE}" || exit 1
			display_alert "TOC0: generated a new RSA-2048 root key" "${TOC0_KEY_FILE}" "warn"
		) 9> "${TOC0_KEY_FILE}.lock" || exit_with_error "TOC0: key generation failed" "${TOC0_KEY_FILE}"
	elif [[ -n "${TOC0_ROOT_KEY}" ]]; then
		[[ -f "${TOC0_ROOT_KEY}" ]] || exit_with_error "TOC0_ROOT_KEY does not exist" "${TOC0_ROOT_KEY}"
		# Absolute: the U-Boot build runs in another directory.
		TOC0_KEY_FILE="$(realpath "${TOC0_ROOT_KEY}")"
	elif [[ ! -f "${TOC0_KEY_FILE}" ]]; then
		exit_with_error "TOC0: no root key" "Set TOC0_ROOT_KEY=/path/to/key.pem, or TOC0_ROOT_KEY=generate"
	fi

	# Different keys give different U-Boot artifacts.
	declare key_id
	key_id="$(sha256sum < "${TOC0_KEY_FILE}" | cut -c1-16)"
	# The variables hash in the artifact version is short: add the key id in full.
	declare -g UBOOT_HASH_EXTRA="${UBOOT_HASH_EXTRA:+${UBOOT_HASH_EXTRA}:}toc0=${key_id}"
	declare -g UBOOT_ARTIFACT_VERSION_SUFFIX="${UBOOT_ARTIFACT_VERSION_SUFFIX:+${UBOOT_ARTIFACT_VERSION_SUFFIX}-}toc0${key_id}"
	display_alert "TOC0: signing key" "${TOC0_KEY_FILE} (${key_id})" "info"
}

function post_config_uboot_target__uboot_sunxi_toc0() {
	display_alert "${BOARD}: secure boot" "TOC0-signed SPL" "info"
	run_host_command_logged scripts/config --disable CONFIG_SPL_IMAGE_TYPE_SUNXI_EGON --enable CONFIG_SPL_IMAGE_TYPE_SUNXI_TOC0
}

function uboot_make_config__uboot_sunxi_toc0_keydir() {
	# mkimage -T sunxi_toc0 signs with ${KEYDIR}/root_key.pem.
	declare keydir
	keydir="$(mktemp -d)" # below WORKDIR, removed at the end of the build
	install -m 0600 "${TOC0_KEY_FILE}" "${keydir}/root_key.pem"
	uboot_make_envs+=("KEYDIR=${keydir@Q}")
}
