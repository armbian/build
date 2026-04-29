#!/usr/bin/env bash
#
# Appliance image provisioning extension.
#
# This extension turns an Armbian image into an appliance-style image that boots
# with a preinstalled binary, a managed systemd service, precreated users, and
# first-run prompts disabled.
#
# Enable with:
#   ENABLE_EXTENSIONS="appliance-image"
#
# Required:
#   APPLIANCE_IMAGE_BINARY_SOURCE_PATH or APPLIANCE_IMAGE_BINARY_URL
#
# Common optional settings:
#   APPLIANCE_IMAGE_SERVICE_NAME
#   APPLIANCE_IMAGE_LOGIN_USER
#   APPLIANCE_IMAGE_LOGIN_PASSWORD
#   APPLIANCE_IMAGE_HOSTNAME
#   APPLIANCE_IMAGE_OVERLAY_DIR
#   APPLIANCE_IMAGE_OPEN_PORTS
#   APPLIANCE_IMAGE_ENABLE_SSH=yes

function appliance_image__shell_quote() {
	printf '%q' "$1"
}

function appliance_image__resolve_path() {
	local requested_path="$1"
	if [[ -e "${requested_path}" ]]; then
		echo "${requested_path}"
		return 0
	fi

	if [[ -e "${SRC}/${requested_path}" ]]; then
		echo "${SRC}/${requested_path}"
		return 0
	fi

	exit_with_error "Extension: ${EXTENSION}: unable to find path '${requested_path}'"
}

function appliance_image__write_password_file() {
	local username="$1"
	local password="$2"
	local password_file="$3"

	printf '%s:%s\n' "${username}" "${password}" > "${password_file}"
	chmod 600 "${password_file}"
}

function extension_prepare_config__appliance_image_defaults() {
	: "${APPLIANCE_IMAGE_SERVICE_NAME:=appliance}"
	: "${APPLIANCE_IMAGE_LOGIN_USER:=${APPLIANCE_IMAGE_SERVICE_NAME}}"
	: "${APPLIANCE_IMAGE_HOSTNAME:=${APPLIANCE_IMAGE_SERVICE_NAME}}"
	: "${APPLIANCE_IMAGE_SERVICE_USER:=${APPLIANCE_IMAGE_SERVICE_NAME}}"
	: "${APPLIANCE_IMAGE_SERVICE_GROUP:=${APPLIANCE_IMAGE_SERVICE_USER}}"
	: "${APPLIANCE_IMAGE_SERVICE_DESCRIPTION:=${APPLIANCE_IMAGE_SERVICE_NAME} appliance service}"
	: "${APPLIANCE_IMAGE_BINARY_INSTALL_PATH:=/usr/local/bin/${APPLIANCE_IMAGE_SERVICE_NAME}}"
	: "${APPLIANCE_IMAGE_EXEC_START:=${APPLIANCE_IMAGE_BINARY_INSTALL_PATH}}"
	: "${APPLIANCE_IMAGE_BINARY_URL_EXTRACT_MODE:=none}"
	: "${APPLIANCE_IMAGE_BINARY_ARCHIVE_MEMBER:=$(basename "${APPLIANCE_IMAGE_BINARY_INSTALL_PATH}")}"
	: "${APPLIANCE_IMAGE_WORKING_DIR:=/var/lib/${APPLIANCE_IMAGE_SERVICE_NAME}}"
	: "${APPLIANCE_IMAGE_DATA_DIR:=${APPLIANCE_IMAGE_WORKING_DIR}/data}"
	: "${APPLIANCE_IMAGE_EXTRA_DIRECTORIES:=}"
	: "${APPLIANCE_IMAGE_LOGIN_SHELL:=/bin/bash}"
	: "${APPLIANCE_IMAGE_PACKAGES:=avahi-daemon ufw udisks2}"
	: "${APPLIANCE_IMAGE_OPEN_PORTS:=80/tcp}"
	: "${APPLIANCE_IMAGE_ENABLE_SSH:=no}"
	: "${APPLIANCE_IMAGE_CREATE_LOGIN_USER:=yes}"
	: "${APPLIANCE_IMAGE_DISABLE_FIRST_RUN:=yes}"
	: "${APPLIANCE_IMAGE_ENABLE_UFW:=yes}"
	: "${APPLIANCE_IMAGE_ENABLE_AVAHI:=yes}"
	: "${APPLIANCE_IMAGE_AVAHI_SERVICE_PORT:=}"
	: "${APPLIANCE_IMAGE_AVAHI_SERVICE_TYPE:=_http._tcp}"
	: "${APPLIANCE_IMAGE_AVAHI_SERVICE_NAME:=${APPLIANCE_IMAGE_SERVICE_NAME^} on %h}"
	: "${APPLIANCE_IMAGE_SERVICE_RESTART:=always}"
	: "${APPLIANCE_IMAGE_SYSTEMD_ENVIRONMENT:=}"
	: "${APPLIANCE_IMAGE_SYSTEMD_STANDARD_OUTPUT:=}"
	: "${APPLIANCE_IMAGE_SYSTEMD_STANDARD_ERROR:=}"
	: "${APPLIANCE_IMAGE_LOGIN_USER_GROUPS:=}"
	: "${APPLIANCE_IMAGE_SERVICE_USER_GROUPS:=}"
	: "${APPLIANCE_IMAGE_PASSWORDLESS_SUDO:=no}"
	: "${APPLIANCE_IMAGE_SUDOERS_FILENAME:=${APPLIANCE_IMAGE_SERVICE_NAME}}"
	: "${APPLIANCE_IMAGE_SUDOERS_CONTENT:=}"

	declare -g APPLIANCE_IMAGE_BINARY_SOURCE_PATH_RESOLVED=""
	declare -g APPLIANCE_IMAGE_OVERLAY_DIR_RESOLVED=""
	declare -g APPLIANCE_IMAGE_SHARED_USER_ACCOUNT="no"

	if [[ -n "${APPLIANCE_IMAGE_BINARY_SOURCE_PATH}" ]]; then
		APPLIANCE_IMAGE_BINARY_SOURCE_PATH_RESOLVED="$(appliance_image__resolve_path "${APPLIANCE_IMAGE_BINARY_SOURCE_PATH}")"
	fi

	if [[ -n "${APPLIANCE_IMAGE_OVERLAY_DIR}" ]]; then
		APPLIANCE_IMAGE_OVERLAY_DIR_RESOLVED="$(appliance_image__resolve_path "${APPLIANCE_IMAGE_OVERLAY_DIR}")"
		[[ -d "${APPLIANCE_IMAGE_OVERLAY_DIR_RESOLVED}" ]] || exit_with_error "Extension: ${EXTENSION}: overlay path '${APPLIANCE_IMAGE_OVERLAY_DIR}' is not a directory"
	fi

	declare -g -a APPLIANCE_IMAGE_PACKAGE_LIST=()
	read -r -a APPLIANCE_IMAGE_PACKAGE_LIST <<< "${APPLIANCE_IMAGE_PACKAGES}"
	if [[ "${APPLIANCE_IMAGE_ENABLE_SSH}" == "yes" ]]; then
		APPLIANCE_IMAGE_PACKAGE_LIST+=(openssh-server)
	fi

	declare -g -a APPLIANCE_IMAGE_PORT_LIST=()
	read -r -a APPLIANCE_IMAGE_PORT_LIST <<< "${APPLIANCE_IMAGE_OPEN_PORTS}"

	declare -g -a APPLIANCE_IMAGE_LOGIN_GROUP_LIST=()
	read -r -a APPLIANCE_IMAGE_LOGIN_GROUP_LIST <<< "${APPLIANCE_IMAGE_LOGIN_USER_GROUPS}"

	declare -g -a APPLIANCE_IMAGE_SERVICE_GROUP_LIST=()
	read -r -a APPLIANCE_IMAGE_SERVICE_GROUP_LIST <<< "${APPLIANCE_IMAGE_SERVICE_USER_GROUPS}"

	declare -g -a APPLIANCE_IMAGE_EXTRA_DIR_LIST=()
	read -r -a APPLIANCE_IMAGE_EXTRA_DIR_LIST <<< "${APPLIANCE_IMAGE_EXTRA_DIRECTORIES}"

	declare -g -a APPLIANCE_IMAGE_SYSTEMD_ENVIRONMENT_LIST=()
	read -r -a APPLIANCE_IMAGE_SYSTEMD_ENVIRONMENT_LIST <<< "${APPLIANCE_IMAGE_SYSTEMD_ENVIRONMENT}"

	if [[ "${APPLIANCE_IMAGE_CREATE_LOGIN_USER}" == "yes" && "${APPLIANCE_IMAGE_SERVICE_USER}" == "${APPLIANCE_IMAGE_LOGIN_USER}" ]]; then
		APPLIANCE_IMAGE_SHARED_USER_ACCOUNT="yes"
	fi
}

function extension_prepare_config__appliance_image_validate() {
	if [[ -n "${APPLIANCE_IMAGE_BINARY_SOURCE_PATH}" && -n "${APPLIANCE_IMAGE_BINARY_URL}" ]]; then
		exit_with_error "Extension: ${EXTENSION}: set only one of APPLIANCE_IMAGE_BINARY_SOURCE_PATH or APPLIANCE_IMAGE_BINARY_URL"
	fi

	if [[ -z "${APPLIANCE_IMAGE_BINARY_SOURCE_PATH}" && -z "${APPLIANCE_IMAGE_BINARY_URL}" ]]; then
		exit_with_error "Extension: ${EXTENSION}: APPLIANCE_IMAGE_BINARY_SOURCE_PATH or APPLIANCE_IMAGE_BINARY_URL must be set"
	fi

	if [[ "${APPLIANCE_IMAGE_CREATE_LOGIN_USER}" == "yes" && -z "${APPLIANCE_IMAGE_LOGIN_USER}" ]]; then
		exit_with_error "Extension: ${EXTENSION}: APPLIANCE_IMAGE_LOGIN_USER must be set when APPLIANCE_IMAGE_CREATE_LOGIN_USER=yes"
	fi

	if [[ -z "${APPLIANCE_IMAGE_SERVICE_NAME}" ]]; then
		exit_with_error "Extension: ${EXTENSION}: APPLIANCE_IMAGE_SERVICE_NAME must not be empty"
	fi
}

function extension_prepare_config__appliance_image_suffix() {
	EXTRA_IMAGE_SUFFIXES+=("-appliance")
}

function extension_prepare_config__appliance_image_packages() {
	if (( ${#APPLIANCE_IMAGE_PACKAGE_LIST[@]} > 0 )); then
		display_alert "Extension: ${EXTENSION}" "adding appliance packages to image" "info"
		add_packages_to_image "${APPLIANCE_IMAGE_PACKAGE_LIST[@]}"
	fi
}

function pre_customize_image__appliance_image_copy_payload() {
	local binary_dir
	local systemd_unit_path
	binary_dir="$(dirname "${APPLIANCE_IMAGE_BINARY_INSTALL_PATH}")"
	systemd_unit_path="${SDCARD}/lib/systemd/system/${APPLIANCE_IMAGE_SERVICE_NAME}.service"
	run_host_command_logged mkdir -pv "${SDCARD}${binary_dir}"

	if [[ -n "${APPLIANCE_IMAGE_BINARY_SOURCE_PATH_RESOLVED}" ]]; then
		run_host_command_logged install -Dm755 "${APPLIANCE_IMAGE_BINARY_SOURCE_PATH_RESOLVED}" "${SDCARD}${APPLIANCE_IMAGE_BINARY_INSTALL_PATH}"
	elif [[ "${APPLIANCE_IMAGE_BINARY_URL_EXTRACT_MODE}" == "targz" ]]; then
		local archive_path extract_dir extracted_binary_path
		archive_path="${SDCARD}/tmp/${APPLIANCE_IMAGE_SERVICE_NAME}.tar.gz"
		extract_dir="${SDCARD}/tmp/${APPLIANCE_IMAGE_SERVICE_NAME}-extract"
		extracted_binary_path="${extract_dir}/${APPLIANCE_IMAGE_BINARY_ARCHIVE_MEMBER}"
		run_host_command_logged mkdir -pv "${extract_dir}"
		run_host_command_logged curl -fsSL "${APPLIANCE_IMAGE_BINARY_URL}" -o "${archive_path}"
		run_host_command_logged tar -xzf "${archive_path}" -C "${extract_dir}" "${APPLIANCE_IMAGE_BINARY_ARCHIVE_MEMBER}"
		run_host_command_logged install -Dm755 "${extracted_binary_path}" "${SDCARD}${APPLIANCE_IMAGE_BINARY_INSTALL_PATH}"
		run_host_command_logged rm -rf "${archive_path}" "${extract_dir}"
	else
		run_host_command_logged curl -fsSL "${APPLIANCE_IMAGE_BINARY_URL}" -o "${SDCARD}${APPLIANCE_IMAGE_BINARY_INSTALL_PATH}"
		run_host_command_logged chmod 755 "${SDCARD}${APPLIANCE_IMAGE_BINARY_INSTALL_PATH}"
	fi

	if [[ -n "${APPLIANCE_IMAGE_OVERLAY_DIR_RESOLVED}" ]]; then
		run_host_command_logged cp -a "${APPLIANCE_IMAGE_OVERLAY_DIR_RESOLVED}/." "${SDCARD}/"
	fi

	run_host_command_logged mkdir -pv "${SDCARD}/etc/avahi/services"

	cat <<- APPLIANCE_IMAGE_SYSTEMD_SERVICE > "${systemd_unit_path}"
		[Unit]
		Description=${APPLIANCE_IMAGE_SERVICE_DESCRIPTION}
		Wants=network-online.target
		After=network-online.target

		[Service]
		Type=simple
		User=${APPLIANCE_IMAGE_SERVICE_USER}
		Group=${APPLIANCE_IMAGE_SERVICE_GROUP}
		WorkingDirectory=${APPLIANCE_IMAGE_WORKING_DIR}
		ExecStart=${APPLIANCE_IMAGE_EXEC_START}
		Restart=${APPLIANCE_IMAGE_SERVICE_RESTART}
		RestartSec=2
	APPLIANCE_IMAGE_SYSTEMD_SERVICE

	for systemd_env in "${APPLIANCE_IMAGE_SYSTEMD_ENVIRONMENT_LIST[@]}"; do
		echo "Environment=\"${systemd_env}\"" >> "${systemd_unit_path}"
	done

	if [[ -n "${APPLIANCE_IMAGE_SYSTEMD_STANDARD_OUTPUT}" ]]; then
		echo "StandardOutput=${APPLIANCE_IMAGE_SYSTEMD_STANDARD_OUTPUT}" >> "${systemd_unit_path}"
	fi

	if [[ -n "${APPLIANCE_IMAGE_SYSTEMD_STANDARD_ERROR}" ]]; then
		echo "StandardError=${APPLIANCE_IMAGE_SYSTEMD_STANDARD_ERROR}" >> "${systemd_unit_path}"
	fi

	cat <<- APPLIANCE_IMAGE_SYSTEMD_INSTALL >> "${systemd_unit_path}"

		[Install]
		WantedBy=multi-user.target
	APPLIANCE_IMAGE_SYSTEMD_INSTALL

	if [[ "${APPLIANCE_IMAGE_ENABLE_AVAHI}" == "yes" && -n "${APPLIANCE_IMAGE_AVAHI_SERVICE_PORT}" ]]; then
		cat <<- APPLIANCE_IMAGE_AVAHI_XML > "${SDCARD}/etc/avahi/services/${APPLIANCE_IMAGE_SERVICE_NAME}.service"
			<?xml version="1.0" standalone='no'?>
			<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
			<service-group>
			  <name replace-wildcards="yes">${APPLIANCE_IMAGE_AVAHI_SERVICE_NAME}</name>
			  <service>
			    <type>${APPLIANCE_IMAGE_AVAHI_SERVICE_TYPE}</type>
			    <port>${APPLIANCE_IMAGE_AVAHI_SERVICE_PORT}</port>
			  </service>
			</service-group>
		APPLIANCE_IMAGE_AVAHI_XML
	fi
}

function post_customize_image__appliance_image_provision() {
	local service_user_q service_group_q working_dir_q data_dir_q exec_path_q login_user_q login_shell_q hostname_q
	local extra_dir
	service_user_q="$(appliance_image__shell_quote "${APPLIANCE_IMAGE_SERVICE_USER}")"
	service_group_q="$(appliance_image__shell_quote "${APPLIANCE_IMAGE_SERVICE_GROUP}")"
	working_dir_q="$(appliance_image__shell_quote "${APPLIANCE_IMAGE_WORKING_DIR}")"
	data_dir_q="$(appliance_image__shell_quote "${APPLIANCE_IMAGE_DATA_DIR}")"
	exec_path_q="$(appliance_image__shell_quote "${APPLIANCE_IMAGE_BINARY_INSTALL_PATH}")"
	login_user_q="$(appliance_image__shell_quote "${APPLIANCE_IMAGE_LOGIN_USER}")"
	login_shell_q="$(appliance_image__shell_quote "${APPLIANCE_IMAGE_LOGIN_SHELL}")"
	hostname_q="$(appliance_image__shell_quote "${APPLIANCE_IMAGE_HOSTNAME}")"

	display_alert "Extension: ${EXTENSION}" "provisioning appliance image" "info"

	chroot_sdcard "getent group ${service_group_q} >/dev/null 2>&1 || groupadd --system ${service_group_q}"
	if [[ "${APPLIANCE_IMAGE_SHARED_USER_ACCOUNT}" != "yes" ]]; then
		chroot_sdcard "id -u ${service_user_q} >/dev/null 2>&1 || useradd --system --home-dir ${working_dir_q} --shell /usr/sbin/nologin --gid ${service_group_q} ${service_user_q}"
	fi

	if [[ "${APPLIANCE_IMAGE_CREATE_LOGIN_USER}" == "yes" ]]; then
		if [[ "${APPLIANCE_IMAGE_SHARED_USER_ACCOUNT}" == "yes" ]]; then
			chroot_sdcard "id -u ${login_user_q} >/dev/null 2>&1 || useradd --create-home --shell ${login_shell_q} --gid ${service_group_q} ${login_user_q}"
		else
			chroot_sdcard "id -u ${login_user_q} >/dev/null 2>&1 || useradd --create-home --shell ${login_shell_q} ${login_user_q}"
		fi
		if [[ -n "${APPLIANCE_IMAGE_LOGIN_PASSWORD}" ]]; then
			appliance_image__write_password_file "${APPLIANCE_IMAGE_LOGIN_USER}" "${APPLIANCE_IMAGE_LOGIN_PASSWORD}" "${SDCARD}/tmp/appliance-image-login.passwd"
			chroot_sdcard "chpasswd < /tmp/appliance-image-login.passwd"
			run_host_command_logged rm -f "${SDCARD}/tmp/appliance-image-login.passwd"
		else
			chroot_sdcard "passwd -l ${login_user_q} >/dev/null 2>&1 || true"
		fi

		for login_group in "${APPLIANCE_IMAGE_LOGIN_GROUP_LIST[@]}"; do
			local login_group_q
			login_group_q="$(appliance_image__shell_quote "${login_group}")"
			chroot_sdcard "getent group ${login_group_q} >/dev/null 2>&1 && usermod -aG ${login_group_q} ${login_user_q}"
		done

		if [[ "${APPLIANCE_IMAGE_PASSWORDLESS_SUDO}" == "yes" ]]; then
			cat <<- APPLIANCE_IMAGE_SUDOERS > "${SDCARD}/etc/sudoers.d/90-${APPLIANCE_IMAGE_LOGIN_USER}-appliance"
				${APPLIANCE_IMAGE_LOGIN_USER} ALL=(ALL) NOPASSWD:ALL
			APPLIANCE_IMAGE_SUDOERS
			run_host_command_logged chmod 440 "${SDCARD}/etc/sudoers.d/90-${APPLIANCE_IMAGE_LOGIN_USER}-appliance"
		fi
	fi

	chroot_sdcard "install -d -o ${service_user_q} -g ${service_group_q} ${working_dir_q} ${data_dir_q}"
	for extra_dir in "${APPLIANCE_IMAGE_EXTRA_DIR_LIST[@]}"; do
		local extra_dir_q
		extra_dir_q="$(appliance_image__shell_quote "${extra_dir}")"
		chroot_sdcard "install -d -o ${service_user_q} -g ${service_group_q} ${extra_dir_q}"
	done
	chroot_sdcard "chmod 755 ${exec_path_q}"

	for service_group_extra in "${APPLIANCE_IMAGE_SERVICE_GROUP_LIST[@]}"; do
		local service_group_extra_q
		service_group_extra_q="$(appliance_image__shell_quote "${service_group_extra}")"
		chroot_sdcard "getent group ${service_group_extra_q} >/dev/null 2>&1 && usermod -aG ${service_group_extra_q} ${service_user_q}"
	done

	printf '%s\n' "${APPLIANCE_IMAGE_HOSTNAME}" > "${SDCARD}/etc/hostname"
	run_host_command_logged sed -i '/^127\.0\.1\.1[[:space:]]/d' "${SDCARD}/etc/hosts"
	printf '127.0.1.1\t%s\n' "${APPLIANCE_IMAGE_HOSTNAME}" >> "${SDCARD}/etc/hosts"

	if [[ -n "${APPLIANCE_IMAGE_SUDOERS_CONTENT}" ]]; then
		printf '%s\n' "${APPLIANCE_IMAGE_SUDOERS_CONTENT}" > "${SDCARD}/etc/sudoers.d/${APPLIANCE_IMAGE_SUDOERS_FILENAME}"
		run_host_command_logged chmod 440 "${SDCARD}/etc/sudoers.d/${APPLIANCE_IMAGE_SUDOERS_FILENAME}"
	fi

	chroot_sdcard "systemctl --no-reload enable ${APPLIANCE_IMAGE_SERVICE_NAME}.service"

	if [[ "${APPLIANCE_IMAGE_ENABLE_AVAHI}" == "yes" ]]; then
		chroot_sdcard "systemctl --no-reload enable avahi-daemon.service"
	fi

	if [[ "${APPLIANCE_IMAGE_ENABLE_SSH}" == "yes" ]]; then
		chroot_sdcard "systemctl --no-reload enable ssh.service"
	fi

	if [[ "${APPLIANCE_IMAGE_ENABLE_UFW}" == "yes" ]]; then
		chroot_sdcard "ufw --force reset"
		chroot_sdcard "ufw default deny incoming"
		chroot_sdcard "ufw default allow outgoing"
		for open_port in "${APPLIANCE_IMAGE_PORT_LIST[@]}"; do
			local open_port_q
			open_port_q="$(appliance_image__shell_quote "${open_port}")"
			chroot_sdcard "ufw allow ${open_port_q}"
		done
		chroot_sdcard "ufw --force enable"
	fi

	if [[ "${APPLIANCE_IMAGE_DISABLE_FIRST_RUN}" == "yes" ]]; then
		run_host_command_logged rm -f "${SDCARD}/etc/profile.d/armbian-check-first-login.sh"
		run_host_command_logged rm -f "${SDCARD}/boot/armbian_first_run.txt.template"
		run_host_command_logged rm -f "${SDCARD}/root/.not_logged_in_yet"
		chroot_sdcard "systemctl --no-reload disable armbian-firstrun.service >/dev/null 2>&1 || true"
	fi
}