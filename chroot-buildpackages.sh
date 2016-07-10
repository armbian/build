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
# Functions:
# create_chroot
# update_chroot
# chroot_build_packages
# fetch_from_repo

# create_chroot <target_dir>
# <target_dir>: directory to put files
#
create_chroot()
{
	local target_dir="$1"
	debootstrap --variant=buildd --arch=$ARCH --foreign \
		--include=ccache,locales,git,ca-certificates,devscripts,libfile-fcntllock-perl,debhelper,rsync \
		$RELEASE $target_dir "http://localhost:3142/$APT_MIRROR"
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
	# TODO: check if resolvconf edit is needed
	touch $target_dir/root/.debootstrap-complete
} #############################################################################

# update_chroot <target_dir>
# <target_dir>: directory to put files
#
update_chroot()
{
	local target_dir="$1"
	local t=$target_dir/root/.update-timestamp
	# apply changes to previously created chroots
	mkdir -p $target_dir/root/{build,overlay,sources} $target_dir/selinux
	# apt-get update && apt-get dist-upgrade
	if [[ -f $t && $(( ($(date +%s) - $(<$t)) / 86400 )) -gt 2 ]]; then
		systemd-nspawn -a -q -D $target_dir /bin/bash -c "apt-get -q update; apt-get -q -y upgrade"
		date +%s > $t
	fi
	# helper script
	cat <<-'EOF' > $target_dir/root/install-deps.sh
	#!/bin/bash
	deps=()
	installed=$(dpkg-query -W -f '${db:Status-Abbrev}|${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print $2}' | cut -d ':' -f 1)
	for packet in "$@"; do grep -q -x -e "$packet" <<< "$installed" || deps+=("$packet"); done
	[[ ${#deps[@]} -gt 0 ]] && apt-get -y --no-install-recommends install "${deps[@]}"
	EOF
	chmod +x $target_dir/root/install-deps.sh
} #############################################################################

# chroot_build_packages
#
chroot_build_packages()
{
	display_alert "Starting package building process" "$RELEASE" "info"

	local target_dir=$DEST/buildpkg/${RELEASE}-${ARCH}

	[[ ! -f $target_dir/root/.debootstrap-complete ]] && create_chroot "$target_dir"

	[[ ! -f $target_dir/bin/bash ]] && exit_with_error "Creating chroot failed" "$RELEASE"

	update_chroot "$target_dir"

	for plugin in $SRC/lib/extras-buildpkgs/*.conf; do
		source $plugin

		# check if needs building
		local needs_building=no
		if [[ -n $package_install_target ]]; then
			for f in $package_install_target; do
				if [[ -z $(find $DEST/debs/extra/ -name "${f}_*$REVISION*_$ARCH.deb") ]]; then
					needs_building=yes
					break
				fi
			done
		else
			needs_building=yes
		fi
		if [[ $needs_building == no ]]; then
			display_alert "Packages are up to date" "$package_name"
			continue
		fi
		display_alert "Building packages" "$package_name"
		# create build script
		cat <<-EOF > $target_dir/root/build.sh
		#!/bin/bash
		export PATH="/usr/lib/ccache:$PATH"
		export HOME="/root"
		export DEBIAN_FRONTEND="noninteractive"
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
		display_alert "Copying sources"
		rsync -aq /root/sources/$package_name /root/build/
		cd /root/build/$package_name
		# copy overlay / "debianization" files
		[[ -d "/root/overlay/$package_name/" ]] && rsync -aq /root/overlay/$package_name /root/build/
		# execute additional commands before building
		[[ -n "$package_prebuild_eval" ]] && eval "$package_prebuild_eval"
		# set upstream version
		[[ -n "$package_upstream_version" ]] && debchange --preserve --newversion "$package_upstream_version" "Import from upstream"
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
			if [[ -n "$package_install_chroot" ]]; then
				display_alert "Installing packages"
				for p in $package_install_chroot; do
					dpkg -i \${p}_*.deb
				done
			fi
			mv *.deb /root
		else
			display_alert "Failed building" "$package_name" "err"
		fi
		exit 0
		EOF

		chmod +x $target_dir/root/build.sh

		# fetch sources
		fetch_from_repo $package_repo $package_name $package_ref

		# run build script in chroot
		systemd-nspawn -a -q -D $target_dir --tmpfs=/root/build --tmpfs=/tmp --bind-ro $SRC/lib/extras-buildpkgs/:/root/overlay \
			--bind-ro $SRC/sources/extra/:/root/sources /bin/bash -c "/root/build.sh"
		# move built packages to $DEST/debs/extras
		if [[ -n $package_install_target ]]; then
			for f in $package_install_target; do
				mv $target_dir/root/${f}_*.deb $DEST/debs/extra/
			done
		fi
		# cleanup
		rm $target_dir/root/*.deb 2>/dev/null
		unset package_name package_repo package_ref package_builddeps package_install_chroot package_install_target \
			package_prebuild_eval package_upstream_version needs_building
	done
} #############################################################################

# fetch_rom_repo <url> <directory> <ref> <ref_subdir>
# <url>: remote repository URL
# <directory>: local directory; subdir for branch/tag will be created
# <ref>:
#	branch:name
#	tag:name
#	HEAD
#	commit:hash@depth
# <ref_subdir>: "yes" to create subdirectory for tag or branch name
#
fetch_from_repo()
{
	local url=$1
	local dir=$2
	local ref=$3
	local ref_subdir=$4

	[[ -z $ref || ( $ref != tag:* && $ref != branch:* ) ]] && exit_with_error "Error in configuration"
	local ref_type=${ref%%:*}
	local ref_name=${ref##*:}

	# get default remote branch name without cloning
	# doesn't work with git:// remote URLs
	# local ref_name=$(git ls-remote --symref $url HEAD | grep -o 'refs/heads/\S*' | sed 's%refs/heads/%%')

	if [[ $ref_subdir == yes ]]; then
		mkdir -p $SOURCES/extra/$dir/$ref_name
		cd $SOURCES/extra/$dir/$ref_name
	else
		mkdir -p $SOURCES/extra/$dir/
		cd $SOURCES/extra/$dir/
	fi

	# this may not work if $SRC is a part of git repository
	if [[ $(git rev-parse --is-inside-work-tree 2>/dev/null) != true ]]; then
		# initial clone
		display_alert "... creating shallow clone"
		git clone -n --depth 1 $url .
	fi

	# update from remote if needed
	local local_hash=$(git rev-parse @)
	# even though tags are unlikely to change on remote
	case $ref_type in
		branch) local remote_hash=$(git ls-remote -h origin $ref_name | cut -f1) ;;
		tag) local remote_hash=$(git ls-remote -t origin $ref_name | cut -f1) ;;
		head) local remote_hash=$(git ls-remote origin HEAD | cut -f1) ;;
	esac

	if [[ $local_hash != $remote_hash ]]; then
		# remote was updated, fetch and check out updates
		display_alert "... fetching updates"
		case $ref_type in
			branch) git fetch --depth 1 origin $ref_name ;;
			tag) git fetch --depth 1 origin tags/$ref_name ;;
			head) git fetch --depth 1 origin HEAD ;;
		esac
		display_alert "... checking out"
		git checkout -f -q FETCH_HEAD
	elif [[ -n $(git status -uno --porcelain) ]]; then
		# working directory is not clean
		display_alert "... checking out"
		git checkout -f -q HEAD
	else
		# working directory is clean, nothing to do
		display_alert "... up to date"
	fi
} #############################################################################
