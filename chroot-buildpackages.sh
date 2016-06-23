#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

create_chroot()
{
	local target_dir="$1"
	debootstrap --variant=buildd --include=ccache,locales,git,ca-certificates,devscripts --arch=$ARCH \
		--foreign $RELEASE $target_dir "http://localhost:3142/$APT_MIRROR"
	[[ $? -ne 0 || ! -f $target_dir/debootstrap/debootstrap ]] && exit_with_error "Create chroot first stage failed"
	cp /usr/bin/$QEMU_BINARY $target_dir/usr/bin/
	chroot $target_dir /bin/bash -c "/debootstrap/debootstrap --second-stage"
	[[ $? -ne 0 || ! -f $target_dir/bin/bash ]] && exit_with_error "Create chroot second stage failed"
	cp $SRC/lib/config/apt/sources.list.$RELEASE $target_dir/etc/apt/sources.list
	echo 'Acquire::http { Proxy "http://localhost:3142"; };' > $target_dir/etc/apt/apt.conf.d/02proxy
	cat <<-EOF > $target_dir/etc/apt/apt.conf.d/71-no-recommends
	APT::Install-Recommends "0";
	APT::Install-Suggests "0";
	EOF
	[[ -f $target_dir/etc/locale.gen ]] && sed -i "s/^# en_US.UTF-8/en_US.UTF-8/" $target_dir/etc/locale.gen
	chroot $target_dir /bin/bash -c "locale-gen; update-locale LANG=en_US:en LC_ALL=en_US.UTF-8"
	printf '#!/bin/sh\nexit 101' > $target_dir/usr/sbin/policy-rc.d
	chmod 755 $target_dir/usr/sbin/policy-rc.d
	mkdir -p $target_dir/root/{build,overlay} $target_dir/selinux
	# TODO: check if resolvconf edit is needed
	touch $target_dir/root/.debootstrap-complete
}

update_chroot()
{
	local target_dir="$1"
	# apt-get update && apt-get dist-upgrade
	systemd-nspawn -a -q -D $target_dir /bin/bash -c "apt-get -q update; apt-get -q -y upgrade"
	# helper script
	cat <<-'EOF' > $target_dir/root/install-deps.sh
	#!/bin/bash
	deps=()
	installed=$(dpkg-query -W -f '${db:Status-Abbrev}|${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print $2}' | cut -d ':' -f 1)
	for packet in "$@"; do grep -q -x -e "$packet" <<< "$installed" || deps+=("$packet"); done
	[[ ${#deps[@]} -gt 0 ]] && apt-get -y --no-install-recommends install "${deps[@]}"
	EOF
	chmod +x $target_dir/root/install-deps.sh
}

chroot_build_packages()
{
	display_alert "Starting package building process" "$RELEASE" "info"

	local target_dir=$DEST/buildpkg/${RELEASE}-${ARCH}

	[[ ! -f $target_dir/root/.debootstrap-complete ]] && create_chroot "$target_dir"

	[[ ! -f $target_dir/bin/bash ]] && exit_with_error "Creating chroot failed" "$RELEASE"

	update_chroot "$target_dir"

	for plugin in $SRC/lib/extras-buildpkgs/*.conf; do
		source $plugin
		display_alert "Creating package" "$package_name" "info"

		# create build script
		cat <<-EOF > $target_dir/root/build.sh
		#!/bin/bash
		export PATH="/usr/lib/ccache:$PATH"
		export HOME="/root"
		# for display_alert logging
		export DEST="/tmp"
		mkdir -p /tmp/debug
		export DEB_BUILD_OPTIONS="ccache nocheck"
		export CCACHE_TEMPDIR="/tmp"
		export DEBFULLNAME="$MAINTAINER"
		export DEBEMAIL="$MAINTAINERMAIL"
		$(declare -f display_alert)
		# check and install build dependencies
		display_alert "Installing build dependencies"
		[[ -n "$package_builddeps" ]] && /root/install-deps.sh $package_builddeps
		cd /root/build
		display_alert "Downloading sources"
		git clone $package_repo $package_dir ${package_branch:+ -b $package_branch} --single-branch
		cd $package_dir
		[[ -n "$package_commit" ]] && git checkout -f $package_commit
		# unpack debianization files if needed
		[[ -n "$package_overlay" ]] && tar xf /root/overlay/$package_overlay -C /root/build/$package_dir
		[[ -n "$package_prebuild_eval" ]] && eval "$package_prebuild_eval"
		# TODO: increment base version if needed
		# set local version
		debchange -l~armbian${REVISION}+ "New Armbian release"
		# build
		display_alert "Building package"
		dpkg-buildpackage -b -uc -us -jauto
		if [[ \$? -eq 0 ]]; then
			cd /root/build
			display_alert "Done building" "$package_name" "ext"
			ls *.deb
			# install in chroot if other libraries depend on them
			[[ "$package_install" == yes ]] && dpkg -i *.deb
			mv *.deb /root
		else
			display_alert "Failed building" "$package_name" "err"
		fi
		exit 0
		EOF

		chmod +x $target_dir/root/build.sh
		# run build script in chroot
		systemd-nspawn -a -q -D $target_dir --tmpfs=/root/build --tmpfs=/tmp --bind-ro $SRC/lib/extras-buildpkgs/:/root/overlay \
			/bin/bash -c "/root/build.sh"
		# TODO: move built packages to $DEST/debs/extras
		# mv $target_dir/root/build/*.deb $DEST/debs/extras
		# cleanup
		unset package_name package_repo package_dir package_branch package_overlay package_builddeps package_commit package_install package_prebuild_eval
	done
}
