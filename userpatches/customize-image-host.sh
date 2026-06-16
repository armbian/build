#!/usr/bin/env bash

if [[ "${BOARD:-}" != "orangepi3b" ]]; then
	return 0
fi

armbian_env="${SDCARD}/boot/armbianEnv.txt"

set_armbian_env_key() {
	local key="$1"
	local value="$2"

	if [[ -f "${armbian_env}" ]] && grep -q "^${key}=" "${armbian_env}"; then
		sed -i "s|^${key}=.*|${key}=${value}|" "${armbian_env}"
	else
		printf '%s=%s\n' "${key}" "${value}" >> "${armbian_env}"
	fi
}

append_armbian_env_extraargs_once() {
	local arg current

	for arg in "$@"; do
		[[ -n "${arg}" ]] || continue

		if [[ -f "${armbian_env}" ]] && grep -q '^extraargs=' "${armbian_env}"; then
			current="$(grep -m1 '^extraargs=' "${armbian_env}" | cut -d= -f2-)"
			if [[ " ${current} " != *" ${arg} "* ]]; then
				sed -i "0,/^extraargs=.*/s|^extraargs=.*|& ${arg}|" "${armbian_env}"
			fi
		else
			printf 'extraargs=%s\n' "${arg}" >> "${armbian_env}"
		fi
	done
}

if [[ -n "${FORCE_EXTRAARGS_APPEND:-}" ]]; then
	# shellcheck disable=SC2086
	append_armbian_env_extraargs_once ${FORCE_EXTRAARGS_APPEND}
fi

if [[ -n "${FORCE_FDTFILE:-}" ]]; then
	set_armbian_env_key fdtfile "${FORCE_FDTFILE}"
fi

if [[ "${DSI_OVERLAY_ENABLE:-no}" != "yes" && "${DSI_OVERLAY_INSTALL:-no}" != "yes" ]]; then
	return 0
fi

overlay_dst_dir="${SDCARD}/boot/overlay-user"

install -d "${overlay_dst_dir}"

overlay_names="${DSI_OVERLAY_NAMES:-${DSI_OVERLAY_NAME:-orangepi3b-waveshare-5inch-dsi}}"
for overlay_name in ${overlay_names}; do
	overlay_src="${USERPATCHES_PATH}/overlay/${overlay_name}.dts"
	overlay_dst="${overlay_dst_dir}/${overlay_name}.dtbo"

	if [[ ! -f "${overlay_src}" ]]; then
		echo "Missing DSI overlay source: ${overlay_src}" >&2
		exit 1
	fi

	dtc -@ -I dts -O dtb -o "${overlay_dst}" "${overlay_src}" || exit 1
done

if [[ "${DEFENCEDOG_NOBLE_DTB_INSTALL:-no}" == "yes" ]]; then
	dtb_url="${DEFENCEDOG_NOBLE_DTB_URL:-https://raw.githubusercontent.com/defencedog/orangepi3b_v2.1/main/Armbian_Noble_rk6.1.75/rk3566-orangepi-3b-v2.1.dtb}"
	dtb_sha="${DEFENCEDOG_NOBLE_DTB_SHA256:-55767fad587b27823f34338d620b2ebdf559440fd41b690bc588f2e563e291c7}"
	dtb_dir="${SDCARD}/boot/dtb/rockchip"
	dtb_tmp="${SDCARD}/boot/dtb/rockchip/rk3566-orangepi-3b-v2.1-defencedog-6.1.75.dtb.tmp"
	dtb_dst="${SDCARD}/boot/dtb/rockchip/rk3566-orangepi-3b-v2.1-defencedog-6.1.75.dtb"

	install -d "${dtb_dir}"
	curl -fsSL "${dtb_url}" -o "${dtb_tmp}" || exit 1
	printf '%s  %s\n' "${dtb_sha}" "${dtb_tmp}" | sha256sum -c - || exit 1
	mv "${dtb_tmp}" "${dtb_dst}"
fi

if [[ "${DSI_OVERLAY_ENABLE:-no}" != "yes" ]]; then
	return 0
fi

overlay_name="${DSI_OVERLAY_NAME:-orangepi3b-waveshare-5inch-dsi}"
set_armbian_env_key user_overlays "${overlay_name}"
