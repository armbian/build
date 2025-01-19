# Install armbian config from repo. Now it is producing externally https://github.com/armbian/configng
# and they are moved to main armbian repo periodically


function custom_apt_repo__add_armbian-github-repo(){
	echo "deb ${SIGNED_BY}https://github.armbian.com/configng stable main" > "${SDCARD}"/etc/apt/sources.list.d/armbian-config.list
}


function post_armbian_repo_customize_image__install_armbian-config() {
	chroot_sdcard_apt_get_install "armbian-config"
}
