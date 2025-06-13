# Install armbian config from repo. Now it is producing externally https://github.com/armbian/configng
# and they are moved to main armbian repo periodically


function custom_apt_repo__add_armbian-github-repo() {
	cat <<- EOF > "${SDCARD}"/etc/apt/sources.list.d/armbian-config.sources
	Types: deb
	URIs: http://github.armbian.com/configng
	Suites: stable
	Components: main
	Signed-By: ${APT_SIGNING_KEY_FILE}
	EOF
}


function post_armbian_repo_customize_image__install_armbian-config() {
	chroot_sdcard_apt_get_install "armbian-config"
}
