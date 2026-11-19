#!/usr/bin/env bash
# @description Makes Firefox from Mozilla's APT repository (packages.mozilla.org) the default browser on desktop images. Removes `firefox-esr`, `chromium` and `google-chrome-stable`, and sets Firefox as the default browser. Pins Mozilla's `firefox` above the Armbian and distro packages, so Ubuntu's snap transitional package is never used. Mozilla builds only amd64 and arm64; other architectures and CLI images are skipped.

function extension_prepare_config__firefox_mozilla() {
	display_alert "Extension: ${EXTENSION}: Firefox from packages.mozilla.org replaces the default browser" "${EXTENSION}" "info"
}

# Runs after the rootfs cache (with the desktop) is in place and all repos are enabled.
function post_repo_customize_image__firefox_mozilla() {
	if [[ "${BUILD_DESKTOP}" != "yes" ]]; then
		display_alert "Extension: ${EXTENSION}" "not a desktop image; skipping" "info"
		return 0
	fi
	if [[ "${ARCH}" != "amd64" && "${ARCH}" != "arm64" ]]; then
		display_alert "Extension: ${EXTENSION}" "Mozilla has no ${ARCH} build; skipping" "warn"
		return 0
	fi

	declare key_url="https://packages.mozilla.org/apt/repo-signing-key.gpg"
	declare key_fpr="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"
	declare key_file="/etc/apt/keyrings/packages.mozilla.org.asc"

	run_host_command_logged mkdir -p "${SDCARD}/etc/apt/keyrings"
	run_host_command_logged curl --max-time 60 --retry 3 -fsSL "${key_url}" -o "${SDCARD}${key_file}"

	declare gnupg_home got_fpr
	gnupg_home="$(mktemp -d)"
	got_fpr="$(GNUPGHOME="${gnupg_home}" gpg --show-keys --with-colons "${SDCARD}${key_file}" | awk -F: '$1 == "fpr" {print $10; exit}')"
	rm -rf "${gnupg_home}"
	if [[ "${got_fpr}" != "${key_fpr}" ]]; then
		exit_with_error "Extension: ${EXTENSION}: Mozilla key fingerprint mismatch" "${got_fpr:-none}"
	fi

	cat <<- EOF > "${SDCARD}/etc/apt/sources.list.d/mozilla.sources"
		Types: deb
		URIs: https://packages.mozilla.org/apt
		Suites: mozilla
		Components: main
		Signed-By: ${key_file} ${key_fpr}
	EOF

	# 1002 beats the 1001 pin for o=Armbian in armbian-config's armbian-desktops file.
	cat <<- EOF > "${SDCARD}/etc/apt/preferences.d/00-mozilla-firefox"
		# Written by the Armbian firefox-mozilla extension.
		Package: firefox firefox-l10n-*
		Pin: origin packages.mozilla.org
		Pin-Priority: 1002

		# Never install Ubuntu's snap transitional package.
		Package: firefox
		Pin: release o=Ubuntu
		Pin-Priority: -1
	EOF

	do_with_retries 3 chroot_sdcard_apt_get_update
	display_alert "Extension: ${EXTENSION}" "installing firefox from packages.mozilla.org" "info"
	chroot_sdcard_apt_get_install --allow-downgrades firefox

	# Remove the browsers armbian-config installs: chromium, Chrome on amd64, firefox-esr.
	# The build runs apt autoremove after this hook.
	declare -a old_pkgs=()
	# shellcheck disable=SC2016 # dpkg-query format, not shell expansion
	mapfile -t old_pkgs < <(chroot_sdcard_with_stdout dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' |
		awk '$1 == "ii" && $2 ~ /^(firefox-esr($|-l10n-)|chromium($|-)|google-chrome-stable$)/ {print $2}')
	if [[ ${#old_pkgs[@]} -gt 0 ]]; then
		display_alert "Extension: ${EXTENSION}" "removing ${old_pkgs[*]}" "info"
		DONT_MAINTAIN_APT_CACHE="yes" chroot_sdcard_apt_get purge "${old_pkgs[@]}"
	fi

	# The firefox package sets the x-www-browser alternative. Set the XDG default too:
	# other apps (LibreOffice, for example) also claim text/html.
	declare mimeapps="${SDCARD}/etc/xdg/mimeapps.list"
	run_host_command_logged mkdir -p "${SDCARD}/etc/xdg"
	[[ -f "${mimeapps}" ]] || : > "${mimeapps}"
	awk '
		BEGIN {
			entries = "x-scheme-handler/http=firefox.desktop;\nx-scheme-handler/https=firefox.desktop;"
			entries = entries "\ntext/html=firefox.desktop;\napplication/xhtml+xml=firefox.desktop;"
		}
		/^\[/ {
			insec = ($0 == "[Default Applications]")
			print
			if (insec && !done) { print entries; done = 1 }
			next
		}
		insec && /^[[:space:]]*(x-scheme-handler\/https?|text\/html|application\/xhtml\+xml)[[:space:]]*=/ { next }
		{ print }
		END {
			if (done) exit
			if (NR > 0) print ""
			print "[Default Applications]"
			print entries
		}' "${mimeapps}" > "${mimeapps}.new"
	run_host_command_logged mv "${mimeapps}.new" "${mimeapps}"

	# GNOME dock: armbian-config adds the installed Chromium-family browsers. Put Firefox there instead.
	# Match any keyfile: armbian-config has changed the file name before.
	declare dconf_dir="${SDCARD}/etc/dconf/db/local.d"
	declare -a gnome_keys=()
	if [[ -d "${dconf_dir}" ]]; then
		mapfile -t gnome_keys < <(grep -rlE "^[[:space:]]*favorite-apps[[:space:]]*=" "${dconf_dir}" || true)
	fi
	if [[ ${#gnome_keys[@]} -gt 0 ]]; then
		# Drop the Chromium-family entries at any position. Add Firefox as the second entry, or alone.
		sed -i -E "/^[[:space:]]*favorite-apps[[:space:]]*=/{
			s/'(chromium|chromium-browser|google-chrome)\.desktop'(,[[:space:]]*)?//g
			s/,[[:space:]]*\]/]/
			/'firefox\.desktop'/! s/\[[[:space:]]*\]/['firefox.desktop']/
			/'firefox\.desktop'/! s/(=[[:space:]]*\[[^],]*)/\1, 'firefox.desktop'/
		}" "${gnome_keys[@]}"
		chroot_sdcard dconf update
	fi

	# Hide the repo from the final image-side apt update. Under qemu, apt sometimes fails to read
	# Mozilla's InRelease (getline ENOMEM), and a mirror sync also fails that update. apt ignores *.disabled.
	run_host_command_logged mv "${SDCARD}/etc/apt/sources.list.d/mozilla.sources" "${SDCARD}/etc/apt/sources.list.d/mozilla.sources.disabled"
}

# Runs after the final image-side apt update. The image ships the repo, but not its index.
function post_post_debootstrap_tweaks__firefox_mozilla() {
	declare src="${SDCARD}/etc/apt/sources.list.d/mozilla.sources"
	if [[ -f "${src}.disabled" ]]; then
		run_host_command_logged mv "${src}.disabled" "${src}"
	fi
}
