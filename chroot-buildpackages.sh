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
# chroot_installpackages_local
# chroot_installpackages

# create_chroot <target_dir> <release> <arch>
#
create_chroot()
{
	local target_dir="$1"
	local release=$2
	local arch=$3
	declare -A qemu_binary
	qemu_binary['armhf']='qemu-arm-static'
	qemu_binary['arm64']='qemu-aarch64-static'
	declare -A apt_mirror
	apt_mirror['jessie']='httpredir.debian.org/debian'
	apt_mirror['xenial']='ports.ubuntu.com'
	display_alert "Creating build chroot" "$release $arch" "info"
	local includes="ccache,locales,git,ca-certificates,devscripts,libfile-fcntllock-perl,debhelper,rsync,python3"
	debootstrap --variant=buildd --arch=$arch --foreign --include="$includes" $release $target_dir "http://localhost:3142/${apt_mirror[$release]}"
	[[ $? -ne 0 || ! -f $target_dir/debootstrap/debootstrap ]] && exit_with_error "Create chroot first stage failed"
	cp /usr/bin/${qemu_binary[$arch]} $target_dir/usr/bin/
	[[ ! -f $target_dir/usr/share/keyrings/debian-archive-keyring.gpg ]] && \
		mkdir -p  $target_dir/usr/share/keyrings/ && \
		cp /usr/share/keyrings/debian-archive-keyring.gpg $target_dir/usr/share/keyrings/
	chroot $target_dir /bin/bash -c "/debootstrap/debootstrap --second-stage"
	[[ $? -ne 0 || ! -f $target_dir/bin/bash ]] && exit_with_error "Create chroot second stage failed"
	create_sources_list $release > $target_dir/etc/apt/sources.list
	echo 'Acquire::http { Proxy "http://localhost:3142"; };' > $target_dir/etc/apt/apt.conf.d/02proxy
	cat <<-EOF > $target_dir/etc/apt/apt.conf.d/71-no-recommends
	APT::Install-Recommends "0";
	APT::Install-Suggests "0";
	EOF
	[[ -f $target_dir/etc/locale.gen ]] && sed -i "s/^# en_US.UTF-8/en_US.UTF-8/" $target_dir/etc/locale.gen
	chroot $target_dir /bin/bash -c "locale-gen; update-locale LANG=en_US:en LC_ALL=en_US.UTF-8"
	printf '#!/bin/sh\nexit 101' > $target_dir/usr/sbin/policy-rc.d
	chmod 755 $target_dir/usr/sbin/policy-rc.d
	rm $target_dir/etc/resolv.conf 2>/dev/null
	echo "8.8.8.8" > $target_dir/etc/resolv.conf
	rm $target_dir/etc/hosts 2>/dev/null
	echo "127.0.0.1 localhost" > $target_dir/etc/hosts
	mkdir -p $target_dir/root/{build,overlay,sources} $target_dir/selinux
	if [[ -L $target_dir/var/lock ]]; then
		rm -rf $target_dir/var/lock 2>/dev/null
		mkdir -p $target_dir/var/lock
	fi
	touch $target_dir/root/.debootstrap-complete
	display_alert "Debootstrap complete" "$release $arch" "info"
} #############################################################################

# chroot_build_packages
#
chroot_build_packages()
{
	for release in jessie xenial; do
		for arch in armhf arm64; do
			display_alert "Starting package building process" "$release $arch" "info"

			local target_dir=$DEST/buildpkg/${release}-${arch}
			# to avoid conflicts between published and self-built packages higher pin-priority may be enough
			# or may use hostname or other unique identifier or smth like builddate=$(date +"%Y%m%d")

			[[ ! -f $target_dir/root/.debootstrap-complete ]] && create_chroot "$target_dir" "$release" "$arch"
			[[ ! -f $target_dir/root/.debootstrap-complete ]] && exit_with_error "Creating chroot failed" "$release"

			local t=$target_dir/root/.update-timestamp
			if [[ ! -f $t || $(( ($(date +%s) - $(<$t)) / 86400 )) -gt 7 ]]; then
				display_alert "Upgrading packages" "$release $arch" "info"
				systemd-nspawn -a -q -D $target_dir /bin/bash -c "apt-get -q update; apt-get -q -y upgrade; apt-get clean"
				date +%s > $t
			fi

			for plugin in $SRC/lib/extras-buildpkgs/*.conf; do
				unset package_name package_repo package_ref package_builddeps package_install_chroot package_install_target \
					package_prebuild_eval package_upstream_version needs_building plugin_target_dir package_component
				source $plugin

				# check build arch
				[[ $package_arch != $arch && $package_arch != all ]] && continue
				# build utils only once for Jessie target
				[[ $package_component == utils && $release == xenial ]] && continue

				local plugin_target_dir=$DEST/debs/extra/$package_component/
				mkdir -p $plugin_target_dir

				# check if needs building
				local needs_building=no
				if [[ -n $package_install_target ]]; then
					for f in $package_install_target; do
						if [[ -z $(find $plugin_target_dir -name "${f}_*$REVISION*_$arch.deb") ]]; then
							needs_building=yes
							break
						fi
					done
				else
					needs_building=yes
				fi
				if [[ $needs_building == no ]]; then
					display_alert "Packages are up to date" "$package_name $release $arch" "info"
					continue
				fi
				display_alert "Building packages" "$package_name $release $arch" "ext"

				# create build script
				cat <<-EOF > $target_dir/root/build.sh
				#!/bin/bash
				export PATH="/usr/lib/ccache:\$PATH"
				export HOME="/root"
				export DEBIAN_FRONTEND="noninteractive"
				export DEB_BUILD_OPTIONS="ccache nocheck"
				export CCACHE_TEMPDIR="/tmp"
				export DEBFULLNAME="$MAINTAINER"
				export DEBEMAIL="$MAINTAINERMAIL"
				$(declare -f display_alert)
				cd /root/build
				if [[ -n "$package_builddeps" ]]; then
					display_alert "Installing build dependencies"
					deps=()
					installed=\$(dpkg-query -W -f '\${db:Status-Abbrev}|\${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print \$2}' | cut -d ':' -f 1)
					for packet in $package_builddeps; do grep -q -x -e "\$packet" <<< "\$installed" || deps+=("\$packet"); done
					[[ \${#deps[@]} -gt 0 ]] && apt-get -y --no-install-recommends --show-progress -o DPKG::Progress-Fancy=1 install "\${deps[@]}"
				fi
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
				# debchange -l~armbian${REVISION}-${builddate}+ "New Armbian release"
				debchange -l~armbian${REVISION}+ "New Armbian release"
				display_alert "Building package"
				dpkg-buildpackage -b -uc -us -jauto
				if [[ \$? -eq 0 ]]; then
					cd /root/build
					# install in chroot if other libraries depend on them
					if [[ -n "$package_install_chroot" ]]; then
						display_alert "Installing packages"
						for p in $package_install_chroot; do
							dpkg -i \${p}_*.deb
						done
					fi
					display_alert "Done building" "$package_name $release $arch" "ext"
					ls *.deb 2>/dev/null
					mv *.deb /root 2>/dev/null
				else
					display_alert "Failed building" "$package_name $release $arch" "err"
				fi
				exit 0
				EOF

				chmod +x $target_dir/root/build.sh

				fetch_from_repo "$package_repo" "extra/$package_name" "$package_ref"

				eval systemd-nspawn -a -q -D $target_dir --tmpfs=/root/build --tmpfs=/tmp --bind-ro $SRC/lib/extras-buildpkgs/:/root/overlay \
					--bind-ro $SRC/sources/extra/:/root/sources /bin/bash -c "/root/build.sh" 2>&1 \
					${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/buildpkg.log'}
				mv $target_dir/root/*.deb $plugin_target_dir 2>/dev/null
			done
		done
	done
} #############################################################################

# chroot_installpackages_local
#
chroot_installpackages_local()
{
	local conf=$SRC/lib/config/aptly-temp.conf
	rm -rf /tmp/aptly-temp/
	mkdir -p /tmp/aptly-temp/
	aptly -config=$conf repo create temp
	# NOTE: this works recursively
	aptly -config=$conf repo add temp $DEST/debs/extra/${RELEASE}-desktop/
	aptly -config=$conf repo add temp $DEST/debs/extra/utils/
	# -gpg-key="925644A6"
	aptly -keyring="$SRC/lib/extras-buildpkgs/buildpkg-public.gpg" -secret-keyring="$SRC/lib/extras-buildpkgs/buildpkg.gpg" -batch=true -config=$conf \
		 -gpg-key="925644A6" -passphrase="testkey1234" -component=temp -distribution=$RELEASE publish repo temp
	aptly -config=$conf -listen=":8189" serve &
	local aptly_pid=$!
	cp $SRC/lib/extras-buildpkgs/buildpkg.key $CACHEDIR/sdcard/tmp/buildpkg.key
	cat <<-'EOF' > $CACHEDIR/sdcard/etc/apt/preferences.d/90-armbian-temp.pref
	Package: *
	Pin: origin "localhost"
	Pin-Priority: 995
	EOF
	cat <<-EOF > $CACHEDIR/sdcard/etc/apt/sources.list.d/armbian-temp.list
	deb http://localhost:8189/ $RELEASE temp
	EOF
	chroot_installpackages
	kill $aptly_pid
} #############################################################################

# chroot_installpackages <remote_only>
#
chroot_installpackages()
{
	local remote_only=$1
	local install_list=""
	for plugin in $SRC/lib/extras-buildpkgs/*.conf; do
		source $plugin
		if [[ $(type -t package_checkinstall) == function ]] && package_checkinstall; then
			install_list="$install_list $package_install_target"
		fi
		unset package_install_target package_checkinstall
	done
	cat <<-EOF > $CACHEDIR/sdcard/tmp/install.sh
	#!/bin/bash
	[[ "$remote_only" != yes ]] && apt-key add /tmp/buildpkg.key
	apt-get -o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" \
		-o Acquire::http::Proxy::localhost="DIRECT" -q update
	# uncomment to debug
	# /bin/bash
	# TODO: check if package exists in case new config was added
	#if [[ -n "$remote_only" == yes ]]; then
	#	for p in $install_list; do
	#		if grep -qE "apt.armbian.com|localhost" <(apt-cache madison \$p); then
	#		if apt-get -s -qq install \$p; then
	#fi
	apt-get -q -o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" \
		-o Acquire::http::Proxy::localhost="DIRECT" \
		--show-progress -o DPKG::Progress-Fancy=1 install -y $install_list
	apt-get clean
	[[ "$remote_only" != yes ]] && apt-key del "925644A6"
	rm /etc/apt/sources.list.d/armbian-temp.list 2>/dev/null
	rm /etc/apt/preferences.d/90-armbian-temp.pref 2>/dev/null
	rm /tmp/buildpkg.key 2>/dev/null
	rm -- "\$0"
	EOF
	chmod +x $CACHEDIR/sdcard/tmp/install.sh
	chroot $CACHEDIR/sdcard /bin/bash -c "/tmp/install.sh"
} #############################################################################
