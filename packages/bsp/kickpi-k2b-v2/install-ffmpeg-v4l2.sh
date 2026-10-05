#!/bin/bash
# KickPi K2B V2: install the prebuilt FFmpeg v4l2-request build (Kwiboo FFmpeg 8.1,
# cedrus HW decode + libx264 encode) into the image at build time.
#
# Sourced by config/boards/kickpi-k2b-v2.csc from its post_family_tweaks__ hook, so it
# runs with build-framework context: ${SDCARD}, display_alert and chroot_sdcard.
#
# Follow-up to #10902:
# - the 41 MB pack is a GitHub Release asset on the contributor fork, never in git
# - guards: Debian dpkg status present, glibc >= 2.41 (prebuilt = aarch64/trixie)
# - every failure path is fail-soft: warn, clean up, and let the image build continue
# - the replacement is verified in-chroot BEFORE distro ffmpeg is purged; a failing
#   verification rolls the replacement back and keeps the distro package
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

# Remove anything this installer may have put into the image, so a failed run leaves
# the image exactly as it was and a later run can retry from scratch. Only symlinks
# that actually point into /opt/ffmpeg-v4l2 are touched.
function kickpi_k2b_v2_ffmpeg_remove_partial() {
	rm -rf "${SDCARD}/opt/ffmpeg-v4l2" || true
	local link_name="" link_target=""
	for link_name in ffmpeg ffprobe; do
		link_target="$(readlink "${SDCARD}/usr/local/bin/${link_name}" 2> /dev/null || true)"
		if [[ "${link_target}" == /opt/ffmpeg-v4l2/* ]]; then
			rm -f "${SDCARD}/usr/local/bin/${link_name}" || true
		fi
	done
	return 0
}

# True only for a complete installation: both binaries executable and both symlinks
# pointing at them (a partial install must fall through and be repaired, not skipped).
function kickpi_k2b_v2_ffmpeg_is_complete() {
	[[ -x "${SDCARD}/opt/ffmpeg-v4l2/bin/ffmpeg" &&
		-x "${SDCARD}/opt/ffmpeg-v4l2/bin/ffprobe" &&
		"$(readlink "${SDCARD}/usr/local/bin/ffmpeg" 2> /dev/null)" == "/opt/ffmpeg-v4l2/bin/ffmpeg" &&
		"$(readlink "${SDCARD}/usr/local/bin/ffprobe" 2> /dev/null)" == "/opt/ffmpeg-v4l2/bin/ffprobe" ]]
}

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

	if kickpi_k2b_v2_ffmpeg_is_complete; then
		display_alert "ffmpeg-v4l2" "already present in image" "info"
		return 0
	fi

	# ---- download + checksum: every source is validated before it is accepted, so a
	# ---- corrupt or tampered response just moves on to the next mirror ----
	local -a pack_urls=()
	[[ -n "${FFMPEG_PACK_URL:-}" ]] && pack_urls+=("${FFMPEG_PACK_URL}")
	pack_urls+=(
		"${kickpi_k2b_v2_ffmpeg_pack_release}"
		"${kickpi_k2b_v2_ffmpeg_pack_mirror}"
		"${kickpi_k2b_v2_ffmpeg_pack_mirror2}"
	)

	local tmp_dir="" pack_url="" valid_pack="" actual_sha256=""
	tmp_dir="$(mktemp -d)" || {
		display_alert "ffmpeg-v4l2" "mktemp failed, skipping" "warn"
		return 0
	}

	for pack_url in "${pack_urls[@]}"; do
		if ! curl -fsSL --connect-timeout 15 --max-time 600 -o "${tmp_dir}/pack.tar.gz" "${pack_url}"; then
			display_alert "ffmpeg-v4l2" "download failed: ${pack_url}" "warn"
			continue
		fi
		actual_sha256="$(sha256sum "${tmp_dir}/pack.tar.gz" | cut -d ' ' -f 1)" || actual_sha256=""
		if [[ "${actual_sha256}" == "${kickpi_k2b_v2_ffmpeg_pack_sha256}" ]]; then
			valid_pack="${pack_url}"
			break
		fi
		display_alert "ffmpeg-v4l2" "sha256 mismatch from ${pack_url} (${actual_sha256}), trying next source" "warn"
	done

	if [[ -z "${valid_pack}" ]]; then
		rm -rf "${tmp_dir}" || true
		display_alert "ffmpeg-v4l2" "no valid archive from any source, continuing without FFmpeg" "warn"
		return 0
	fi

	# ---- extract and install into the image rootfs; clean up partial copies ----
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
		kickpi_k2b_v2_ffmpeg_remove_partial
		display_alert "ffmpeg-v4l2" "copy into image failed, partial install removed" "warn"
		rm -rf "${tmp_dir}" || true
		return 0
	fi
	rm -rf "${tmp_dir}" || true

	# ---- verify the replacement in the image chroot BEFORE touching distro ffmpeg ----
	# ---- (missing shared libraries fail loudly here); rollback on failure so the ----
	# ---- image keeps whatever distro ffmpeg it had ----
	if ! chroot_sdcard /usr/local/bin/ffmpeg -version; then
		kickpi_k2b_v2_ffmpeg_remove_partial
		display_alert "ffmpeg-v4l2" "verification failed, replacement removed; distro ffmpeg untouched" "warn"
		return 0
	fi

	# ---- now that the replacement works: drop distro FFmpeg so /usr/local/bin wins
	# ---- PATH (fail-soft). libx264-164 runtime comes from PACKAGE_LIST_BOARD
	# ---- (installed during package installation, before this hook runs).
	chroot_sdcard apt-get purge -y ffmpeg ||
		display_alert "ffmpeg-v4l2" "distro ffmpeg not purged (not installed?), continuing" "warn"
	chroot_sdcard apt-mark hold ffmpeg ||
		display_alert "ffmpeg-v4l2" "apt-mark hold ffmpeg failed, continuing" "warn"

	display_alert "ffmpeg-v4l2" "installed and verified (glibc ${libc6_version})" "info"
	return 0
}

kickpi_k2b_v2_ffmpeg_install
