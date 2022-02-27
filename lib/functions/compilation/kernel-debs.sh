# This is a re-imagining of mkdebian and builddeb from the kernel tree.

# We wanna produce Debian/Ubuntu compatible packages so we're able to use their standard tools, like
# `flash-kernel`, `u-boot-menu`, `grub2`, and others, so we gotta stick to their conventions.

# Headers are important. We wanna be compatible with `dkms` stuff from Ubuntu, like `nvidia-driver-xxx`.
# This is affected by cross-compilation: Armbian usually builds arm64 on amd64, and the KBUILD tools
# that would be included in such headers package will be the wrong arch for `dkms`ing on target arm64 machine.

# The main difference is that this is NOT invoked from KBUILD's Makefile, but instead
# directly by Armbian, with references to the dirs where KBUILD's
# `make install dtbs_install modules_install headers_install` have already successfully been run.

# This will create a SET of packages. It should always create these:
# image package: vmlinuz and such, config, modules, and dtbs (if exist) in /usr/lib/xxx
# libc header package: just the libc headers
# linux-headers package: just the image headers. (what about the binaries? cross compilation?)
# linux-dtbs package: only dtbs, if they exist. in /boot/

# So this will handle
# - Creating .deb package skeleton dir (mktemp)
# - Moving/copying around of KBUILD installed stuff for Debian/Ubuntu/Armbian standard locations, in the correct packages
# - Separating headers, between image and libc packages.
# - Fixing the symlinks to stuff so they fit a target system.
# - building the .debs;

is_enabled() {
	grep -q "^$1=y" include/config/auto.conf
}

if_enabled_echo() {
	if is_enabled "$1"; then
		echo -n "$2"
	elif [ $# -ge 3 ]; then
		echo -n "$3"
	fi
}

function prepare_kernel_packaging_debs() {
	declare kernel_work_dir="${1}"
	declare kernel_version="${2}"
	declare -n tmp_kernel_install_dirs="${3}" # nameref to 	declare -n kernel_install_dirs dictionary
	declare kernel_package_dir

	kernel_package_dir=$(mktemp -d "${WORKDIR}/kernel.image.package.XXXXXXXXX") # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	display_alert "kernel_package_dir" "${kernel_package_dir}" "debug"

	# Some variables and settings used throughout the script
	declare kernel_version_family="${kernel_version}-${LINUXFAMILY}"
	declare packageversion="${REVISION}"
	declare linux_image_package_name="linux-image-${BRANCH}-${LINUXFAMILY}"

	mkdir -p "${kernel_package_dir}/DEBIAN"

	# Generate copyright file
	mkdir -p "${kernel_package_dir}/usr/share/doc/${linux_image_package_name}"
	cat <<- EOF > "${kernel_package_dir}/usr/share/doc/${linux_image_package_name}/copyright"
		This is a packaged Armbian patched version of the Linux kernel.

		The sources may be found at most Linux archive sites, including:
		https://www.kernel.org/pub/linux/kernel

		Copyright: 1991 - 2018 Linus Torvalds and others.

		The git repository for mainline kernel development is at:
		git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

		    This program is free software; you can redistribute it and/or modify
		    it under the terms of the GNU General Public License as published by
		    the Free Software Foundation; version 2 dated June, 1991.

		On Debian GNU/Linux systems, the complete text of the GNU General Public
		License version 2 can be found in \`/usr/share/common-licenses/GPL-2'.
	EOF

	# Generate a control file
	cat <<- EOF > "${kernel_package_dir}/DEBIAN/control"
		Package: ${linux_image_package_name}
		Version: ${packageversion}
		Architecture: ${ARCH}
		Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
		Section: kernel
		Provides: linux-image, linux-image-armbian, armbian-$BRANCH
		Description: Linux kernel, armbian version $kernel_version_family $BRANCH
		 This package contains the Linux kernel, modules and corresponding other
		 files, kernel_version_family: $kernel_version_family.
	EOF

	# Install the maintainer scripts
	# Note: hook scripts under /etc/kernel are also executed by official Debian
	# kernel packages, as well as kernel packages built using make-kpkg.
	# make-kpkg sets $INITRD to indicate whether an initramfs is wanted, and
	# so do we; recent versions of dracut and initramfs-tools will obey this.
	declare debhookdir="/etc/kernel"
	for script in postinst postrm preinst prerm; do
		mkdir -p "${kernel_package_dir}${debhookdir}/${script}.d"
		cat <<- EOF > "${kernel_package_dir}/DEBIAN/${script}"
			#!/bin/bash
			set -x
			set -e

			# Pass maintainer script parameters to hook scripts
			export DEB_MAINT_PARAMS="\$*"

			# Tell initramfs builder whether it's wanted
			export INITRD=$(if_enabled_echo CONFIG_BLK_DEV_INITRD Yes No)

			test -d $debhookdir/$script.d && run-parts --arg="$kernel_version_family" --arg="/$installed_image_path" $debhookdir/$script.d
			exit 0
		EOF
		chmod 755 "${kernel_package_dir}/DEBIAN/${script}"
	done

	display_alert "tmp_kernel_install_dirs INSTALL_PATH:" "${tmp_kernel_install_dirs[INSTALL_PATH]}" "debug"
	display_alert "tmp_kernel_install_dirs INSTALL_MOD_PATH:" "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}" "debug"
	display_alert "tmp_kernel_install_dirs INSTALL_HDR_PATH:" "${tmp_kernel_install_dirs[INSTALL_HDR_PATH]}" "debug"

	display_alert "Kernel install dir" "tree 1" "debug"
	run_host_command_logged tree -C -h --du -d -L 3 "${tmp_kernel_install_dirs[INSTALL_PATH]}/../.."

	run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_PATH]}" "${kernel_package_dir}/"         # /boot stuff
	run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}/lib" "${kernel_package_dir}/" # so "lib" stuff sits at the root

	if [[ -d "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" ]]; then
		display_alert "tmp_kernel_install_dirs INSTALL_DTBS_PATH:" "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" "debug"
		display_alert "Kernel build will produce DTBs package!" "DTBs YES PACKAGE" "debug"

		# /usr/lib/linux-image-${kernel_version_family} is wanted by flash-kernel
		# /lib/firmware/${kernel_version_family}/device-tree/ would also be acceptable
		mkdir -p "${kernel_package_dir}/usr/lib"
		run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" "${kernel_package_dir}/usr/lib/linux-image-${kernel_version_family}"
	fi

	run_host_command_logged chown -R root:root "${kernel_package_dir}" # Fix ownership and permissions
	run_host_command_logged chmod -R go-w "${kernel_package_dir}"      # Fix ownership and permissions
	run_host_command_logged chmod -R a+rX "${kernel_package_dir}"      # in case we are in a restrictive umask environment like 0077
	run_host_command_logged chmod -R ug-s "${kernel_package_dir}"      # in case we build in a setuid/setgid directory

	cd "${kernel_package_dir}" || exit_with_error "major failure 774"

	# create md5sums file. needed? @TODO: convert to subshell?
	sh -c "cd '${kernel_package_dir}'; find . -type f ! -path './DEBIAN/*' -printf '%P\0' | xargs -r0 md5sum > DEBIAN/md5sums"

	declare unpacked_size
	unpacked_size="$(du -h -s "${kernel_package_dir}" | awk '{print $1}')"
	display_alert "Unpacked linux-kernel image" "${unpacked_size}" "debug"

	# Show it
	display_alert "Package dir" "tree 2" "debug"
	run_host_command_logged tree -C -h --du -d -L 3 "${kernel_package_dir}"

	run_host_command_logged dpkg-deb ${DEB_COMPRESS:+-Z$DEB_COMPRESS} --build "${kernel_package_dir}" "${kernel_work_dir}/.." # not KDEB compress, we're not under a Makefile

}
