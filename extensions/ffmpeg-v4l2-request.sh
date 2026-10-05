# @description Installs the prebuilt Kwiboo FFmpeg 8.1 v4l2-request build (cedrus hardware
# decode + libx264 encode) into the image for boards that enable this extension via
# ENABLE_EXTENSIONS. Follow-up to #10902/#10915: the ~40 MB pack is a GitHub Release asset on
# the contributor fork and never enters git; the primary download source follows the
# framework's ${GITHUB_SOURCE} mirror (with two hardcoded fallbacks for proxy-less builders)
# and the sha256 is pinned. Guards: dpkg status present, glibc >= 2.41 (prebuilt = aarch64/
# trixie), Ubuntu "resolute" skipped (x264 ABI rename). Failure paths are currently fail-soft
# (warn, roll back, continue) — see the PR #10915 discussion about making network failures
# hard errors instead.
#
# shellcheck disable=SC2154 # build-framework globals: SDCARD, RELEASE, BOARD, PACKAGE_LIST_BOARD

# sha256 of ffmpeg-v4l2-request-pack.tar.gz (contents: README-BUILD.md, SHA256SUMS,
# bin/{ffmpeg,ffprobe}, scripts/*, src/kwiboo-ffmpeg-v4l2-request-n8.1.tgz)
ffmpeg_v4l2_request_pack_sha256="4b20d322778030d685e690e5c08e48a7091234e1506f2357401f478fac508b01"
ffmpeg_v4l2_request_pack_rel="Novice-PG/build/releases/download/ffmpeg-v4l2-request-v1/ffmpeg-v4l2-request-pack.tar.gz"

# Remove anything this installer may have put into the image, so a failed run leaves
# the image exactly as it was and a later run can retry from scratch. Only symlinks
# that actually point into /opt/ffmpeg-v4l2 are touched.
function ffmpeg_v4l2_request_remove_partial() {
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
function ffmpeg_v4l2_request_is_complete() {
	[[ -x "${SDCARD}/opt/ffmpeg-v4l2/bin/ffmpeg" &&
		-x "${SDCARD}/opt/ffmpeg-v4l2/bin/ffprobe" &&
		"$(readlink "${SDCARD}/usr/local/bin/ffmpeg" 2> /dev/null)" == "/opt/ffmpeg-v4l2/bin/ffmpeg" &&
		"$(readlink "${SDCARD}/usr/local/bin/ffprobe" 2> /dev/null)" == "/opt/ffmpeg-v4l2/bin/ffprobe" ]]
}

# Config phase: bring in the x264 encode runtime the prebuilt links against.
# Package names verified against packages.ubuntu.com / packages.debian.org:
# - Ubuntu jammy ships libx264-163 only (no -164): a -164 request would fail the
#   build at package-install time, which runs before any guard in the install hook
# - Ubuntu resolute renamed the ABI to libx264-165 (no -164); the install hook
#   skips that release entirely (the prebuilt links libx264.so.164)
# Debian bookworm/trixie and Ubuntu noble all provide libx264-164 and keep it.
function extension_prepare_config__ffmpeg_v4l2_request() {
	if [[ "${RELEASE}" != "resolute" && "${RELEASE}" != "jammy" ]]; then
		declare -g PACKAGE_LIST_BOARD+=" libx264-164"
	fi
	display_alert "${EXTENSION}" "ffmpeg-v4l2-request configured for RELEASE=${RELEASE}" "debug"
}

# Install phase (same stage as post_family_tweaks board hooks): everything below is
# fail-soft for now — see the header and PR #10915 for the hard-fail proposal.
function post_family_tweaks__ffmpeg_v4l2_request() {
	if [[ "${RELEASE}" == "resolute" ]]; then
		display_alert "${EXTENSION}" "Skipping prebuilt FFmpeg v4l2-request on ${RELEASE} (x264 ABI rename)" "warn"
		return 0
	fi
	display_alert "${EXTENSION}" "Installing prebuilt FFmpeg v4l2-request (fail-soft)" "info"

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

	if ffmpeg_v4l2_request_is_complete; then
		display_alert "ffmpeg-v4l2" "already present in image" "info"
		return 0
	fi

	# ---- never clobber somebody else's binaries: if /usr/local/bin/{ffmpeg,ffprobe}
	# ---- exists and is not one of our own symlinks, it belongs to another
	# ---- installation — skip (a later rollback could not restore it) ----
	local pre_link_name="" pre_link_target=""
	for pre_link_name in ffmpeg ffprobe; do
		if [[ -e "${SDCARD}/usr/local/bin/${pre_link_name}" || -L "${SDCARD}/usr/local/bin/${pre_link_name}" ]]; then
			pre_link_target="$(readlink "${SDCARD}/usr/local/bin/${pre_link_name}" 2> /dev/null || true)"
			if [[ "${pre_link_target}" != /opt/ffmpeg-v4l2/* ]]; then
				display_alert "ffmpeg-v4l2" "pre-existing ${pre_link_name} in image belongs to another installation, skipping" "warn"
				return 0
			fi
		fi
	done

	# ---- download + checksum: primary source follows the framework's ${GITHUB_SOURCE}
	# ---- github mirror (GITPROXY/GHPROXY, same pattern as lib/tools/shellcheck.sh);
	# ---- every source is validated before it is accepted, so a corrupt or tampered
	# ---- response just moves on to the next mirror ----
	local -a pack_urls=()
	[[ -n "${FFMPEG_PACK_URL:-}" ]] && pack_urls+=("${FFMPEG_PACK_URL}")
	pack_urls+=(
		"${GITHUB_SOURCE:-https://github.com}/${ffmpeg_v4l2_request_pack_rel}"
		"https://gh.acmsz.top/https://github.com/${ffmpeg_v4l2_request_pack_rel}"
		"https://gh-proxy.com/https://github.com/${ffmpeg_v4l2_request_pack_rel}"
	)

	local tmp_dir="" pack_url="" valid_pack="" actual_sha256="" source_no=0
	tmp_dir="$(mktemp -d)" || {
		display_alert "ffmpeg-v4l2" "mktemp failed, skipping" "warn"
		return 0
	}

	for pack_url in "${pack_urls[@]}"; do
		source_no=$((source_no + 1))
		if ! curl -fsSL --connect-timeout 15 --max-time 600 -o "${tmp_dir}/pack.tar.gz" "${pack_url}"; then
			display_alert "ffmpeg-v4l2" "download failed (source ${source_no} of ${#pack_urls[@]}), trying next" "warn"
			continue
		fi
		actual_sha256="$(sha256sum "${tmp_dir}/pack.tar.gz" | cut -d ' ' -f 1)" || actual_sha256=""
		if [[ "${actual_sha256}" == "${ffmpeg_v4l2_request_pack_sha256}" ]]; then
			valid_pack="${pack_url}"
			break
		fi
		display_alert "ffmpeg-v4l2" "sha256 mismatch (${actual_sha256}), trying next source" "warn"
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
		ffmpeg_v4l2_request_remove_partial
		display_alert "ffmpeg-v4l2" "copy into image failed, partial install removed" "warn"
		rm -rf "${tmp_dir}" || true
		return 0
	fi
	rm -rf "${tmp_dir}" || true

	# ---- verify the replacement in the image chroot BEFORE touching distro ffmpeg ----
	# ---- (missing shared libraries fail loudly here); rollback on failure so the ----
	# ---- image keeps whatever distro ffmpeg it had ----
	if ! chroot_sdcard /usr/local/bin/ffmpeg -version; then
		ffmpeg_v4l2_request_remove_partial
		display_alert "ffmpeg-v4l2" "verification failed, replacement removed; distro ffmpeg untouched" "warn"
		return 0
	fi

	# ---- now that the replacement works: drop distro FFmpeg so /usr/local/bin wins
	# ---- PATH (fail-soft). libx264-164 runtime comes from the config hook above
	# ---- (installed during package installation, before this hook runs).
	chroot_sdcard apt-get purge -y ffmpeg ||
		display_alert "ffmpeg-v4l2" "distro ffmpeg not purged (not installed?), continuing" "warn"
	chroot_sdcard apt-mark hold ffmpeg ||
		display_alert "ffmpeg-v4l2" "apt-mark hold ffmpeg failed, continuing" "warn"

	display_alert "ffmpeg-v4l2" "installed and verified (glibc ${libc6_version})" "info"
	return 0
}
