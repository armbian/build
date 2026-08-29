#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

compile_armbian-zsh() {
	: "${artifact_version:?artifact_version is not set}"
	: "${ARMBIAN_ZSH_BRANCH:?ARMBIAN_ZSH_BRANCH is not set}"

	declare cleanup_id="" tmp_dir=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "deb-zsh" cleanup_id tmp_dir # namerefs

	declare armbian_zsh_dir="armbian-zsh"
	mkdir -p "${tmp_dir}/${armbian_zsh_dir}"

	fetch_from_repo "$GITHUB_SOURCE/ohmyzsh/ohmyzsh" "oh-my-zsh" "${ARMBIAN_ZSH_BRANCH}"
	fetch_from_repo "$GITHUB_SOURCE/mroth/evalcache" "evalcache" "commit:d6973f8c3ecde3eabd75c17b47e2222e24ab3e87" # 2025-11-24
	fetch_from_repo "$GITHUB_SOURCE/zsh-users/zsh-autosuggestions" "zsh-autosuggestions" "commit:85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5" # 2025-06-24
	fetch_from_repo "$GITHUB_SOURCE/zsh-users/zsh-syntax-highlighting" "zsh-syntax-highlighting" "commit:2fc57d63067c18b1100ecdbf684fa5baf49459d1" # 2026-08-22

	mkdir -p "${tmp_dir}/${armbian_zsh_dir}"/{DEBIAN,etc/skel/,etc/oh-my-zsh/,/etc/skel/.oh-my-zsh/cache}

	cd "${tmp_dir}/${armbian_zsh_dir}" || exit_with_error "can't change directory"

	# set up control file
	cat <<- END > DEBIAN/control
		Package: armbian-zsh
		Version: ${artifact_version}
		Architecture: all
		Maintainer: $MAINTAINER <$MAINTAINERMAIL>
		Depends: zsh, tmux
		Section: utils
		Priority: optional
		Description: Armbian improved ZShell (oh-my-zsh...)
	END

	# set up post install script
	cat <<- END > DEBIAN/postinst
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

	# the two most-wanted external plugins: fish-style history suggestions and
	# command-line syntax highlighting. Dropped into custom/plugins (where oh-my-zsh
	# resolves plugin names first) and enabled in the plugins=() list below.
	mkdir -p "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/custom/plugins
	cp -R "${SRC}"/cache/sources/zsh-autosuggestions "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/custom/plugins
	cp -R "${SRC}"/cache/sources/zsh-syntax-highlighting "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/custom/plugins

	# @TODO: do this properly (not-copy it to begin with)
	rm -rf "${tmp_dir}/${armbian_zsh_dir}"/etc/.git "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/plugins/.git
	find "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/custom/plugins -type d -name .git -prune -exec rm -rf {} +

	# bash<->zsh compatibility shims, auto-loaded for every user via oh-my-zsh
	# ($ZSH/custom/*.zsh) so it is not baked per-.zshrc. Restores the bash builtins
	# zsh lacks (complete/compgen/compopt via bashcompinit; mapfile/readarray).
	# NB: scripts with a #!/bin/bash shebang always run under bash regardless of
	# the login shell — this only smooths bash typed/sourced into interactive zsh.
	mkdir -p "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/custom
	cat > "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/custom/armbian-compat.zsh <<- 'ARMBIAN_COMPAT_EOF'
		# Armbian bash<->zsh interactive compatibility shims (auto-loaded by oh-my-zsh).
		# Scripts with a #!/bin/bash shebang run under bash regardless of the login
		# shell; this only smooths bash snippets typed at the prompt or sourced into an
		# interactive zsh, restoring the bash builtins zsh omits.

		# bashcompinit provides the complete/compgen/compopt builtins so a tool's
		# bash-completion file works under zsh too.
		autoload -Uz +X bashcompinit 2>/dev/null && bashcompinit 2>/dev/null

		# mapfile / readarray: read stdin lines into an array. The array name is the
		# last argument; -t/-d/... flags are accepted and ignored and the trailing
		# newline is always stripped (the -t common case).
		if (( ! ${+builtins[mapfile]} )); then
			mapfile() {
				emulate -L zsh
				local __name=${@[-1]} __line
				local -a __buf
				while IFS= read -r __line; do __buf+=("$__line"); done
				set -A "$__name" "${__buf[@]}"
			}
			readarray() { mapfile "$@" }
		fi
	ARMBIAN_COMPAT_EOF

	# Small history deltas layered on top of oh-my-zsh's own config (which already
	# sets HISTSIZE/dedup/share_history/hist_verify and the completion styling).
	# Loaded after it via $ZSH/custom/*.zsh.
	cat > "${tmp_dir}/${armbian_zsh_dir}"/etc/oh-my-zsh/custom/armbian-defaults.zsh <<- 'ARMBIAN_DEFAULTS_EOF'
		# Armbian zsh defaults, layered on oh-my-zsh's history/completion config.
		# oh-my-zsh caps SAVEHIST at 10000 while keeping 50000 in memory; persist the
		# full set to disk, and trim blanks / skip duplicate search hits.
		SAVEHIST=$HISTSIZE
		setopt HIST_REDUCE_BLANKS HIST_FIND_NO_DUPS
	ARMBIAN_DEFAULTS_EOF

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
	# zsh-syntax-highlighting must stay LAST — it wraps the line editor and has to
	# load after every other plugin's widgets are defined.
	sed -i 's/^plugins=.*/plugins=(evalcache git git-extras debian tmux screen history extract colorize web-search docker zsh-autosuggestions zsh-syntax-highlighting)/' "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	# add collection of Armbian BASH aliases also to ZSH. They are compatible
	cat "${SRC}"/packages/bsp/common/etc/skel/.bash_aliases >> "${tmp_dir}/${armbian_zsh_dir}"/etc/skel/.zshrc

	chmod 755 "${tmp_dir}/${armbian_zsh_dir}"/DEBIAN/postinst

	dpkg_deb_build "${tmp_dir}/${armbian_zsh_dir}" "armbian-zsh"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}
