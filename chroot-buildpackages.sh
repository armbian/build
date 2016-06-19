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
	debootstrap --variant=buildd --include=ccache,locales,git,ca-certificates,devscripts --arch=$ARCH \
		--foreign $RELEASE $DEST/buildpkg/$RELEASE "http://localhost:3142/$APT_MIRROR"
	[[ $? -ne 0 || ! -f $DEST/buildpkg/$RELEASE/debootstrap/debootstrap ]] && exit_with_error "Create chroot first stage failed"
	cp /usr/bin/$QEMU_BINARY $DEST/buildpkg/$RELEASE/usr/bin/
	chroot $DEST/buildpkg/$RELEASE /bin/bash -c "/debootstrap/debootstrap --second-stage"
	[[ $? -ne 0 || ! -f $DEST/buildpkg/$RELEASE/bin/bash ]] && exit_with_error "Create chroot second stage failed"
	cp $SRC/lib/config/apt/sources.list.$RELEASE $DEST/buildpkg/$RELEASE/etc/apt/sources.list
	echo 'Acquire::http { Proxy "http://localhost:3142"; };' > $DEST/buildpkg/$RELEASE/etc/apt/apt.conf.d/02proxy
	cat <<-EOF > $DEST/buildpkg/$RELEASE/etc/apt/apt.conf.d/71-no-recommends
	APT::Install-Recommends "0";
	APT::Install-Suggests "0";
	EOF
	[[ -f $DEST/buildpkg/$RELEASE/etc/locale.gen ]] && sed -i "s/^# en_US.UTF-8/en_US.UTF-8/" $DEST/buildpkg/$RELEASE/etc/locale.gen
	systemd-nspawn -D $DEST/buildpkg/$RELEASE /bin/bash -c "locale-gen; update-locale LANG=en_US:en LC_ALL=en_US.UTF-8"
	printf '#!/bin/sh\nexit 101' > $DEST/buildpkg/$RELEASE/usr/sbin/policy-rc.d
	chmod 755 $DEST/buildpkg/$RELEASE/usr/sbin/policy-rc.d
	mkdir -p $DEST/buildpkg/$RELEASE/root/build $DEST/buildpkg/$RELEASE/root/overlay $DEST/buildpkg/$RELEASE/selinux
	# TODO: check if resolvconf edit is needed
	touch $DEST/buildpkg/$RELEASE/root/.debootstrap-complete
}

update_chroot()
{
	# apt-get update && apt-get dist-upgrade
	systemd-nspawn -D $DEST/buildpkg/$RELEASE /bin/bash -c "apt-get -q update; apt-get -q -y upgrade"
	# helper script
	cat <<-'EOF' > $DEST/buildpkg/$RELEASE/root/install-deps.sh
	#!/bin/bash
	deps=()
	installed=$(dpkg-query -W -f '${db:Status-Abbrev}|${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print $2}' | cut -d ':' -f 1)
	for packet in "$@"; do grep -q -x -e "$packet" <<< "$installed" || deps+=("$packet"); done
	[[ ${#deps[@]} -gt 0 ]] && apt-get -y --no-install-recommends install "${deps[@]}"
	EOF
	chmod +x $DEST/buildpkg/$RELEASE/root/install-deps.sh
}

chroot_build_packages()
{
	display_alert "Starting package building process" "$RELEASE" "info"
	[[ ! -f $DEST/buildpkg/$RELEASE/root/.debootstrap-complete ]] && create_chroot

	[[ ! -f $DEST/buildpkg/$RELEASE/bin/bash ]] && exit_with_error "Creating chroot failed" "$RELEASE"

	update_chroot

	for plugin in $SRC/lib/extras-buildpkgs/*.conf; do
		source $plugin
		display_alert "Creating package" "$package_name" "info"

		# create build script
		cat <<-EOF > $DEST/buildpkg/$RELEASE/root/build.sh
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
		# TODO: increment base version if needed
		# set local version
		debchange -l~armbian${REVISION}+ "New Armbian release"
		# build
		display_alert "Building package"
		dpkg-buildpackage -b -uc -us -jauto
		cd /root/build
		display_alert "Done building"
		ls *.deb
		# install in chroot if other libraries depend on them
		[[ "$package_install" == yes ]] && dpkg -i *.deb
		mv *.deb /root
		EOF

		chmod +x $DEST/buildpkg/$RELEASE/root/build.sh
		# run build script in chroot
		systemd-nspawn -D $DEST/buildpkg/$RELEASE --tmpfs=/root/build --tmpfs=/tmp --bind-ro $SRC/lib/extras-buildpkgs/:/root/overlay \
			/bin/bash -c "/root/build.sh"
		# TODO: move built packages to $DEST/debs
		# mv $DEST/buildpkg/$RELEASE/root/build/*.deb $DEST/debs/
		# DEBUG:
		#systemd-nspawn -D $DEST/buildpkg/$RELEASE --tmpfs=/root/build --tmpfs=/tmp --bind-ro $SRC/lib/extras-buildpkgs/:/root/overlay \
		#	/bin/bash
		# cleanup
		unset package_name package_repo package_dir package_branch package_overlay package_builddeps package_commit package_install
	done
}
