# @description Installs the prebuilt Kwiboo FFmpeg 8.1 v4l2-request build (cedrus hardware
# decode + libx264 encode) into the image for boards that enable this extension via
# ENABLE_EXTENSIONS. Follow-up to #10902/#10915: the ~40 MB pack is a GitHub Release asset on
# the contributor fork and never enters git; the primary download source follows the
# framework's ${GITHUB_SOURCE} mirror (with two hardcoded fallbacks for proxy-less builders)
# and the sha256 is pinned. Guards: dpkg status present, glibc >= 2.38 and libva >= 2.21
# (the pack calls vaMapBuffer2, so noble with libva 2.20 is skipped),
# Ubuntu "resolute" skipped (x264 ABI rename). Failure semantics (per PR #10915
# discussion): configuration-class conditions (unsupported release, missing or old glibc,
# foreign binaries in /usr/local/bin, already installed) warn and skip; download, checksum,
# extract, copy and verify failures abort the build via exit_with_error after rolling back
# any partial install, so a network or disk problem can never silently produce an image
# without the promised FFmpeg. Set SKIP_FFMPEG_V4L2=yes to deliberately build without the
# prebuilt pack.
#
# shellcheck disable=SC2154 # build-framework globals: SDCARD, RELEASE, BOARD, PACKAGE_LIST_BOARD

# sha256 of ffmpeg-v4l2-request-pack.tar.gz (contents: README-BUILD.md, SHA256SUMS,
# bin/{ffmpeg,ffprobe}, scripts/*, src/kwiboo-ffmpeg-v4l2-request-n8.1.tgz)
ffmpeg_v4l2_request_pack_sha256="1e90cf41ed99f1425dff8b70fa5119f35e1ac2a8efa807d1573c0b763511586b"
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

# Config phase: bring in every runtime library the prebuilt links against.
# The pack is a sha256-pinned release asset, so its NEEDED set is static and
# complete: no probing, no per-release guessing. One table feeds both the
# package list below and the pre-flight check in the install hook, so the
# declared packages and the binaries cannot drift apart again.
# libc/libm/libz/libudev come from the minimal baseline (libc6, zlib1g, systemd);
# the entries below are the ones a minimal image does not get for free.
# Package names verified against packages.ubuntu.com / packages.debian.org:
# - Ubuntu jammy ships libx264-163 only (no -164): a -164 request would fail the
#   build at package-install time, which runs before any guard in the install hook
# - Ubuntu resolute renamed the ABI to libx264-165 (no -164); the install hook
#   skips that release entirely (the prebuilt links libx264.so.164)
# Debian bookworm/trixie and Ubuntu noble all provide libx264-164 and keep it.
declare -gA ffmpeg_v4l2_request_runtime_pkgs=(
	[libdrm.so.2]="libdrm2"
	[libva-drm.so.2]="libva-drm2"
	[libva.so.2]="libva2"
	[libx264.so.164]="libx264-164"
)

# Sorted package names, one per line: identical on every run, shared by the
# config phase and the install hook.
function ffmpeg_v4l2_request_runtime_packages() {
	local soname=""
	for soname in "${!ffmpeg_v4l2_request_runtime_pkgs[@]}"; do
		printf '%s\n' "${ffmpeg_v4l2_request_runtime_pkgs[${soname}]}"
	done | sort
}

function extension_prepare_config__ffmpeg_v4l2_request() {
	if [[ "${SKIP_FFMPEG_V4L2:-}" == "yes" ]]; then
		display_alert "${EXTENSION}" "SKIP_FFMPEG_V4L2=yes — not adding ffmpeg runtime packages" "info"
		return 0
	fi
	if [[ "${RELEASE}" != "resolute" && "${RELEASE}" != "jammy" ]]; then
		# PACKAGE_LIST_BOARD is published read-only by config_source_board_file()
		# before extension_prepare_config() runs, so appending to it aborts the
		# build during configuration. add_packages_to_image() is the supported
		# path for extension/family-injected image packages.
		local -a ffmpeg_v4l2_request_pkgs=()
		mapfile -t ffmpeg_v4l2_request_pkgs < <(ffmpeg_v4l2_request_runtime_packages)
		add_packages_to_image "${ffmpeg_v4l2_request_pkgs[@]}"
	fi
	display_alert "${EXTENSION}" "ffmpeg-v4l2-request configured for RELEASE=${RELEASE}" "debug"
}

# Install phase (same stage as post_family_tweaks board hooks): configuration-class
# conditions warn and skip; download, integrity and install failures abort the build
# (exit_with_error) after rolling back any partial install — see the header.
function post_family_tweaks__ffmpeg_v4l2_request() {
	if [[ "${SKIP_FFMPEG_V4L2:-}" == "yes" ]]; then
		display_alert "${EXTENSION}" "SKIP_FFMPEG_V4L2=yes — skipping prebuilt FFmpeg install" "info"
		return 0
	fi
	if [[ "${RELEASE}" == "resolute" ]]; then
		display_alert "${EXTENSION}" "Skipping prebuilt FFmpeg v4l2-request on ${RELEASE} (x264 ABI rename)" "warn"
		return 0
	fi
	display_alert "${EXTENSION}" "Installing prebuilt FFmpeg v4l2-request" "info"

	# ---- configuration-class guards: warn + skip, keep building ----
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

	# The pack needs GLIBC_2.38 at most. Bookworm (2.36) and older are skipped.
	if ! dpkg --compare-versions "${libc6_version}" ge 2.38; then
		display_alert "ffmpeg-v4l2" "glibc ${libc6_version} < 2.38 (no compatible prebuilt), skipping" "warn"
		return 0
	fi

	# The pack calls vaMapBuffer2 (libva >= 2.21). ldd does not catch a missing
	# symbol, so skip older libva, e.g. noble (2.20).
	local libva_version=""
	libva_version="$(awk -v RS='' '$1 == "Package:" && $2 == "libva2" {
		for (i = 1; i <= NF; i++) if ($i == "Version:") { print $(i + 1); exit }
	}' "${SDCARD}/var/lib/dpkg/status")" || true

	if ! dpkg --compare-versions "${libva_version:-0}" ge 2.21; then
		display_alert "ffmpeg-v4l2" "libva ${libva_version:-none} < 2.21 (no compatible prebuilt), skipping" "warn"
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
		exit_with_error "ffmpeg-v4l2: mktemp failed on the builder (local disk problem)"
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
		exit_with_error "ffmpeg-v4l2: no valid pack from ${#pack_urls[@]} sources (download or sha256 failed); set SKIP_FFMPEG_V4L2=yes to build without the prebuilt FFmpeg"
	fi

	# ---- extract and install into the image rootfs; clean up partial copies ----
	if ! tar -xzf "${tmp_dir}/pack.tar.gz" -C "${tmp_dir}"; then
		rm -rf "${tmp_dir}" || true
		exit_with_error "ffmpeg-v4l2: archive extract failed (corrupt download or builder disk problem)"
	fi

	if ! install -d "${SDCARD}/opt/ffmpeg-v4l2/bin" "${SDCARD}/usr/local/bin" ||
		! install -m 0755 "${tmp_dir}/ffmpeg-v4l2-request-pack/bin/ffmpeg" "${SDCARD}/opt/ffmpeg-v4l2/bin/ffmpeg" ||
		! install -m 0755 "${tmp_dir}/ffmpeg-v4l2-request-pack/bin/ffprobe" "${SDCARD}/opt/ffmpeg-v4l2/bin/ffprobe" ||
		! ln -sfn /opt/ffmpeg-v4l2/bin/ffmpeg "${SDCARD}/usr/local/bin/ffmpeg" ||
		! ln -sfn /opt/ffmpeg-v4l2/bin/ffprobe "${SDCARD}/usr/local/bin/ffprobe"; then
		ffmpeg_v4l2_request_remove_partial
		rm -rf "${tmp_dir}" || true
		exit_with_error "ffmpeg-v4l2: copy into image failed; partial install rolled back"
	fi
	rm -rf "${tmp_dir}" || true

	# ---- resolve every NEEDED soname at once: the loader only ever names the ----
	# ---- first missing one, which turns a 3-package bug into 3 build cycles ----
	# ldd lists every unresolved object in one pass, so a build never has to be
	# repeated once per missing library. The table above declares what an image
	# needs; this check reports what this binary actually links against.
	local ldd_out="" missing=""
	ldd_out="$(chroot_sdcard ldd /usr/local/bin/ffmpeg 2>&1 || true)"
	missing="$(awk '/=> not found/ { print $1 }' <<< "${ldd_out}" | sort -u | tr '\n' ' ')" || true
	if [[ -n "${missing}" ]]; then
		ffmpeg_v4l2_request_remove_partial
		exit_with_error "ffmpeg-v4l2: missing runtime libraries: ${missing}- install the packages that provide them"
	fi

	# ---- verify the replacement in the image chroot BEFORE touching distro ffmpeg ----
	# ---- (missing shared libraries fail loudly here); rollback on failure so the ----
	# ---- image keeps whatever distro ffmpeg it had ----
	if ! chroot_sdcard /usr/local/bin/ffmpeg -version; then
		ffmpeg_v4l2_request_remove_partial
		exit_with_error "ffmpeg-v4l2: in-image verification failed; replacement rolled back, distro ffmpeg untouched"
	fi

	# ---- now that the replacement works: drop distro FFmpeg so /usr/local/bin wins
	# ---- PATH (non-fatal cleanup: if this fails, distro ffmpeg stays but /usr/local/bin
	# ---- still wins PATH). libx264-164 runtime comes from the config hook above
	# ---- (installed during package installation, before this hook runs).
	chroot_sdcard apt-get purge -y ffmpeg ||
		display_alert "ffmpeg-v4l2" "distro ffmpeg not purged (not installed?), continuing" "warn"
	chroot_sdcard apt-mark hold ffmpeg ||
		display_alert "ffmpeg-v4l2" "apt-mark hold ffmpeg failed, continuing" "warn"

	display_alert "ffmpeg-v4l2" "installed and verified (glibc ${libc6_version})" "info"
	return 0
}
