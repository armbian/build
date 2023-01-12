compile_armbian-zsh() {
	local tmp_dir armbian_zsh_dir
	tmp_dir=$(mktemp -d) # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	chmod 700 "${tmp_dir}"

	armbian_zsh_dir=armbian-zsh_${REVISION}_all
	display_alert "Building deb" "armbian-zsh" "info"

	fetch_from_repo "$GITHUB_SOURCE/ohmyzsh/ohmyzsh" "oh-my-zsh" "branch:master"
	fetch_from_repo "$GITHUB_SOURCE/mroth/evalcache" "evalcache" "branch:master"

	mkdir -p "${tmp_dir}/${armbian_zsh_dir}"/{DEBIAN,etc/skel/,etc/oh-my-zsh/,/etc/skel/.oh-my-zsh/cache}

	# set up control file
	cat <<- END > "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/control
		Package: armbian-zsh
		Version: $REVISION
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Depends: zsh, tmux
		Section: utils
		Priority: optional
		Description: Armbian improved ZShell (oh-my-zsh...)
	END

	# set up post install script
	cat <<- END > "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/postinst
		#!/bin/sh

		# copy cache directory if not there yet
		awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$6"/.oh-my-zsh"}' /etc/passwd | xargs -i sh -c 'test ! -d {} && cp -R --attributes-only /etc/skel/.oh-my-zsh {}'
		awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$6"/.zshrc"}' /etc/passwd | xargs -i sh -c 'test ! -f {} && cp -R /etc/skel/.zshrc {}'

		# fix owner permissions in home directory
		awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$1":"\$3" "\$6"/.oh-my-zsh"}' /etc/passwd | xargs -n2 chown -R
		awk -F'[:]' '{if (\$3 >= 1000 && \$3 != 65534 || \$3 == 0) print ""\$1":"\$3" "\$6"/.zshrc"}' /etc/passwd | xargs -n2 chown -R

		# add support for bash profile
		! grep emulate /etc/zsh/zprofile  >/dev/null && echo "emulate sh -c 'source /etc/profile'" >> /etc/zsh/zprofile
		exit 0
	END

	cp -R "${SRC}"/cache/sources/oh-my-zsh "${tmp_dir}/${armbian_zsh_dir}"/etc/
	cp -R "${SRC}"/cache/sources/evalcache "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/plugins

	# @TODO: do this properly (not-copy it to begin with)
	rm -rf "${tmp_dir}/${armbian_zsh_dir}"/etc/.git "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/plugins/.git

	cp "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/templates/zshrc.zsh-template "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	chmod -R g-w,o-w "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/

	# we have common settings
	sed -i "s/^export ZSH=.*/export ZSH=\/etc\/oh-my-zsh/" "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# user cache
	sed -i "/^export ZSH=.*/a export ZSH_CACHE_DIR=~\/.oh-my-zsh\/cache" "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# define theme
	sed -i 's/^ZSH_THEME=.*/ZSH_THEME="mrtazz"/' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# disable auto update since we provide update via package
	sed -i "s/^# zstyle ':omz:update' mode disabled.*/zstyle ':omz:update' mode disabled/g" "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# define default plugins
	sed -i 's/^plugins=.*/plugins=(evalcache git git-extras debian tmux screen history extract colorize web-search docker)/' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	chmod 755 "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/postinst

	fakeroot_dpkg_deb_build "${tmp_dir}/${armbian_zsh_dir}"
	run_host_command_logged rsync --remove-source-files -r "${tmp_dir}/${armbian_zsh_dir}.deb" "${DEB_STORAGE}/"
}
