#!/bin/bash
# KickPi K2B V2: install the prebuilt FFmpeg v4l2-request build (Kwiboo FFmpeg 8.1,
# cedrus HW decode + libx264 encode) into the image at build time.
#
# Sourced by config/boards/kickpi-k2b-v2.csc from its post_family_tweaks__ hook, so it
# runs with build-framework context: ${SDCARD}, display_alert and chroot_sdcard.
#
# Follow-up to #10902 ("Plan C"):
# - the 40 MB pack is a GitHub Release asset on the contributor fork, never in git
# - guards: Debian dpkg status present, glibc >= 2.41 (prebuilt = aarch64/trixie)
# - every failure path is fail-soft: warn, clean up, and let the image build continue
#
# shellcheck disable=SC2154 # build-framework globals: SDCARD

# sha256 of ffmpeg-v4l2-request-pack.tar.gz (contents: README-BUILD.md, SHA256SUMS,
# bin/{ffmpeg,ffprobe}, scripts/*, src/kwiboo-ffmpeg-v4l2-request-n8.1.tgz)
kickpi_k2b_v2_ffmpeg_pack_sha256="4b20d322778030d685e690e5c08e48a7091234e1506f2357401f478fac508b01"
kickpi_k2b_v2_ffmpeg_pack_release="https://github.com/Novice-PG/build/releases/download/ffmpeg-v4l2-request-v1/ffmpeg-v4l2-request-pack.tar.gz"
# Fallback mirrors for builders where direct github.com is unreachable; the gh.acmsz
# prefix measured ~10x faster than gh-proxy for this 41 MB asset on the target board.
kickpi_k2b_v2_ffmpeg_pack_mirror="https://gh.acmsz.top/https://github.com/Novice-PG/build/releases/download/ffmpeg-v4l2-request-v1/ffmpeg-v4l2-request-pack.tar.gz"
kickpi_k2b_v2_ffmpeg_pack_mirror2="https://gh-proxy.com/https://github.com/Novice-PG/build/releases/download/ffmpeg-v4l2-request-v1/ffmpeg-v4l2-request-pack.tar.gz"

function kickpi_k2b_v2_ffmpeg_install() {
	# ---- guards (all fail-soft: skip install, keep building) ----
	if [[ ! -f "${SDCARD}/var/lib/dpkg/status" ]]; then
		display_alert "ffmpeg-v4l2" "no dpkg status in image, skipping" "warn"
		return 0
	fi

	local libc6_version=""
	libc6_version="$(awk -v RS='' '$1 == "Package:" && $2 == "libc6" {
		for (i = 1; i <= NF; i++) if ($i == "Version:") { print $(i + 1); exit }
	}' "${SDCARD}/var/lib/dpkg/status")" || true

	if [[ -z "${libc6_version}" ]]; then
		display_alert "ffmpeg-v4l2" "libc6 version not found in image, skipping" "warn"
		return 0
	fi

	if ! dpkg --compare-versions "${libc6_version}" ge 2.41; then
		display_alert "ffmpeg-v4l2" "glibc ${libc6_version} < 2.41 (prebuilt needs Debian trixie+), skipping" "warn"
		return 0
	fi

	if [[ -x "${SDCARD}/opt/ffmpeg-v4l2/bin/ffmpeg" ]]; then
		display_alert "ffmpeg-v4l2" "already present in image" "info"
		return 0
	fi

	# ---- download (fail-soft: env override first, then release asset, then mirror) ----
	local -a pack_urls=()
	[[ -n "${FFMPEG_PACK_URL:-}" ]] && pack_urls+=("${FFMPEG_PACK_URL}")
	pack_urls+=(
		"${kickpi_k2b_v2_ffmpeg_pack_release}"
		"${kickpi_k2b_v2_ffmpeg_pack_mirror}"
		"${kickpi_k2b_v2_ffmpeg_pack_mirror2}"
	)

	local tmp_dir="" pack_url="" downloaded_from=""
	tmp_dir="$(mktemp -d)" || {
		display_alert "ffmpeg-v4l2" "mktemp failed, skipping" "warn"
		return 0
	}

	for pack_url in "${pack_urls[@]}"; do
		if curl -fsSL --connect-timeout 15 --max-time 600 -o "${tmp_dir}/pack.tar.gz" "${pack_url}"; then
			downloaded_from="${pack_url}"
			break
		fi
		display_alert "ffmpeg-v4l2" "download failed: ${pack_url}" "warn"
	done

	if [[ -z "${downloaded_from}" ]]; then
		rm -rf "${tmp_dir}" || true
		display_alert "ffmpeg-v4l2" "all sources failed, continuing without FFmpeg" "warn"
		return 0
	fi

	# ---- verify checksum (fail-soft) ----
	local actual_sha256=""
	actual_sha256="$(sha256sum "${tmp_dir}/pack.tar.gz" | cut -d ' ' -f 1)" || true
	if [[ "${actual_sha256}" != "${kickpi_k2b_v2_ffmpeg_pack_sha256}" ]]; then
		display_alert "ffmpeg-v4l2" "sha256 mismatch (${actual_sha256}), skipping" "warn"
		rm -rf "${tmp_dir}" || true
		return 0
	fi

	# ---- extract and install into the image rootfs (fail-soft) ----
	if ! tar -xzf "${tmp_dir}/pack.tar.gz" -C "${tmp_dir}"; then
		display_alert "ffmpeg-v4l2" "extract failed, skipping" "warn"
		rm -rf "${tmp_dir}" || true
		return 0
	fi

	if ! install -d "${SDCARD}/opt/ffmpeg-v4l2/bin" "${SDCARD}/usr/local/bin" ||
		! install -m 0755 "${tmp_dir}/ffmpeg-v4l2-request-pack/bin/ffmpeg" "${SDCARD}/opt/ffmpeg-v4l2/bin/ffmpeg" ||
		! install -m 0755 "${tmp_dir}/ffmpeg-v4l2-request-pack/bin/ffprobe" "${SDCARD}/opt/ffmpeg-v4l2/bin/ffprobe" ||
		! ln -sfn /opt/ffmpeg-v4l2/bin/ffmpeg "${SDCARD}/usr/local/bin/ffmpeg" ||
		! ln -sfn /opt/ffmpeg-v4l2/bin/ffprobe "${SDCARD}/usr/local/bin/ffprobe"; then
		display_alert "ffmpeg-v4l2" "copy into image failed, skipping" "warn"
		rm -rf "${tmp_dir}" || true
		return 0
	fi
	rm -rf "${tmp_dir}" || true

	# ---- image hygiene: drop distro FFmpeg so /usr/local/bin wins PATH (fail-soft).
	# ---- libx264-164 runtime comes from PACKAGE_LIST_BOARD (installed way earlier,
	# ---- during package installation), so no chroot apt download is needed here.
	chroot_sdcard apt-get purge -y ffmpeg ||
		display_alert "ffmpeg-v4l2" "distro ffmpeg not purged (not installed?), continuing" "warn"
	chroot_sdcard apt-mark hold ffmpeg ||
		display_alert "ffmpeg-v4l2" "apt-mark hold ffmpeg failed, continuing" "warn"

	# ---- verify inside the image chroot; missing shared libs fail loudly here ----
	if chroot_sdcard /usr/local/bin/ffmpeg -version; then
		display_alert "ffmpeg-v4l2" "installed and verified (glibc ${libc6_version})" "info"
	else
		display_alert "ffmpeg-v4l2" "installed, but in-chroot verification failed" "warn"
	fi

	return 0
}

kickpi_k2b_v2_ffmpeg_install
