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
	declare kernel_dest_install_dir="${2}"
	declare kernel_version="${3}"
	declare -n tmp_kernel_install_dirs="${4}" # nameref to 	declare -n kernel_install_dirs dictionary
	declare debs_target_dir="${kernel_work_dir}/.."

	# Some variables and settings used throughout the script
	declare kernel_version_family="${kernel_version}-${LINUXFAMILY}"
	declare package_version="${REVISION}"

	# show incoming tree
	display_alert "Kernel install dir" "incoming from KBUILD make" "debug"
	run_host_command_logged tree -C --du -h "${kernel_dest_install_dir}" "| grep --line-buffered -v -e '\.ko' -e '\.h' "

	display_alert "tmp_kernel_install_dirs INSTALL_PATH:" "${tmp_kernel_install_dirs[INSTALL_PATH]}" "debug"
	display_alert "tmp_kernel_install_dirs INSTALL_MOD_PATH:" "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}" "debug"
	display_alert "tmp_kernel_install_dirs INSTALL_HDR_PATH:" "${tmp_kernel_install_dirs[INSTALL_HDR_PATH]}" "debug"
	display_alert "tmp_kernel_install_dirs INSTALL_DTBS_PATH:" "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" "debug"

	# package the linux-image (image, modules, dtbs (if present))
	create_kernel_deb "linux-image-${BRANCH}-${LINUXFAMILY}" "${debs_target_dir}" kernel_package_callback_linux_image

	# if dtbs present, package those too separately, for u-boot usage.
	if [[ -d "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" ]]; then
		create_kernel_deb "linux-dtb-${BRANCH}-${LINUXFAMILY}" "${debs_target_dir}" kernel_package_callback_linux_dtb
	fi

	# @TODO: package headers. probably in 3 phases: common per-version (libc headers), common per-arch (arch-specific, with binary tools), and kernel specific (kernel-headers, no tools)

}

function create_kernel_deb() {
	declare package_name="${1}"
	declare deb_output_dir="${2}"
	declare callback_function="${3}"

	declare package_directory
	package_directory=$(mktemp -d "${WORKDIR}/${package_name}.XXXXXXXXX") # subject to TMPDIR/WORKDIR, so is protected by single/common error trapmanager to clean-up.
	display_alert "package_directory" "${package_directory}" "debug"

	declare package_DEBIAN_dir="${package_directory}/DEBIAN" # DEBIAN dir
	mkdir -p "${package_DEBIAN_dir}"                         # maintainer scripts et al

	# Generate copyright file
	mkdir -p "${package_directory}/usr/share/doc/${package_name}"
	cat <<- COPYRIGHT > "${package_directory}/usr/share/doc/${package_name}/copyright"
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
	COPYRIGHT

	# Run the callback.
	display_alert "Running callback" "callback: ${callback_function}" "debug"
	"${callback_function}" "${@}"

	run_host_command_logged chown -R root:root "${package_directory}" # Fix ownership and permissions
	run_host_command_logged chmod -R go-w "${package_directory}"      # Fix ownership and permissions
	run_host_command_logged chmod -R a+rX "${package_directory}"      # in case we are in a restrictive umask environment like 0077
	run_host_command_logged chmod -R ug-s "${package_directory}"      # in case we build in a setuid/setgid directory

	cd "${package_directory}" || exit_with_error "major failure 774 for ${package_name}"

	# create md5sums file
	sh -c "cd '${package_directory}'; find . -type f ! -path './DEBIAN/*' -printf '%P\0' | xargs -r0 md5sum > DEBIAN/md5sums"

	declare unpacked_size
	unpacked_size="$(du -h -s "${package_directory}" | awk '{print $1}')"
	display_alert "Unpacked ${package_name} tree" "${unpacked_size}" "debug"

	# Show it
	display_alert "Package dir" "for package ${package_name}" "debug"
	run_host_command_logged tree -C -h -d --du "${package_directory}"

	run_host_command_logged dpkg-deb ${DEB_COMPRESS:+-Z$DEB_COMPRESS} --build "${package_directory}" "${deb_output_dir}" # not KDEB compress, we're not under a Makefile
}

function kernel_package_hook_helper() {
	declare script="${1}"
	declare contents="${2}"

	cat >> "${package_DEBIAN_dir}/${script}" <<- EOT
		#!/bin/bash
		echo "Armbian ${package_name} for ${kernel_version_family}: ${script} starting."
		set -e # Error control
		set -x # Debugging

		$(cat "${contents}")

		echo "Armbian ${package_name} for ${kernel_version_family}: ${script} finishing."
		true
	EOT
	chmod 775 "${package_DEBIAN_dir}/${script}"

	display_alert "Hook debug" "${script} for ${package_name}" "debug"
	run_host_command_logged cat "${package_DEBIAN_dir}/${script}"
}

function kernel_package_callback_linux_image() {
	display_alert "package_directory" "${package_directory}" "debug"

	declare installed_image_path="boot/vmlinuz-${kernel_version_family}" # using old mkdebian terminology here.
	declare image_name="Image"                                           # for arm64. or, "zImage" for arm, or "vmlinuz" for others. Why? See where u-boot puts them.

	run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_PATH]}" "${package_directory}/"         # /boot stuff
	run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}/lib" "${package_directory}/" # so "lib" stuff sits at the root

	if [[ -d "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" ]]; then
		# /usr/lib/linux-image-${kernel_version_family} is wanted by flash-kernel
		# /lib/firmware/${kernel_version_family}/device-tree/ would also be acceptable

		display_alert "DTBs present on kernel output" "DTBs ${package_name}: /usr/lib/linux-image-${kernel_version_family}" "debug"
		mkdir -p "${package_directory}/usr/lib"
		run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" "${package_directory}/usr/lib/linux-image-${kernel_version_family}"
	fi

	# Generate a control file
	cat <<- CONTROL_FILE > "${package_DEBIAN_dir}/control"
		Package: ${package_name}
		Version: ${package_version}
		Architecture: ${ARCH}
		Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
		Section: kernel
		Provides: linux-image, linux-image-armbian, armbian-$BRANCH
		Description: Linux kernel, armbian version $kernel_version_family $BRANCH
		 This package contains the Linux kernel, modules and corresponding other
		 files, kernel_version_family: $kernel_version_family.
	CONTROL_FILE

	# Install the maintainer scripts
	# Note: hook scripts under /etc/kernel are also executed by official Debian
	# kernel packages, as well as kernel packages built using make-kpkg.
	# make-kpkg sets $INITRD to indicate whether an initramfs is wanted, and
	# so do we; recent versions of dracut and initramfs-tools will obey this.
	declare debian_kernel_hook_dir="/etc/kernel"
	for script in "postinst" "postrm" "preinst" "prerm"; do
		mkdir -p "${package_directory}${debian_kernel_hook_dir}/${script}.d" # create kernel hook dir, make sure.

		kernel_package_hook_helper "${script}" <(
			cat <<- KERNEL_HOOK_DELEGATION
				export DEB_MAINT_PARAMS="\$*" # Pass maintainer script parameters to hook scripts
				export INITRD=$(if_enabled_echo CONFIG_BLK_DEV_INITRD Yes No) # Tell initramfs builder whether it's wanted
				# Run the same hooks Debian/Ubuntu would for their kernel packages.
				test -d ${debian_kernel_hook_dir}/${script}.d && run-parts --arg="${kernel_version_family}" --arg="/${installed_image_path}" ${debian_kernel_hook_dir}/${script}.d
			KERNEL_HOOK_DELEGATION

			# @TODO: only if u-boot, only for postinst. Gotta find a hook scheme for these...
			if [[ "${script}" == "postinst" ]]; then
				if [[ "yes" == "yes" ]]; then
					cat <<- HOOK_FOR_LINK_TO_LAST_INSTALLED_KERNEL
						echo "Armbian: update last-installed kernel symlink..."
						ln -sf $(basename "${installed_image_path}") /boot/$image_name || mv /${installed_image_path} /boot/${image_name}
						touch /boot/.next
					HOOK_FOR_LINK_TO_LAST_INSTALLED_KERNEL
				fi
			fi
		)
	done
}

function kernel_package_callback_linux_dtb() {
	display_alert "package_directory" "${package_directory}" "debug"

	mkdir -p "${package_directory}/boot/dtb-${kernel_version_family}"
	run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" "${package_directory}/boot/dtb-${kernel_version_family}"

	# Generate a control file
	cat <<- CONTROL_FILE > "${package_DEBIAN_dir}/control"
		Version: ${package_version}
		Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
		Section: kernel
		Package: ${package_name}
		Architecture: ${ARCH}
		Provides: linux-dtb, linux-dtb-armbian, armbian-$BRANCH
		Description: Armbian Linux DTB, version ${kernel_version_family} $BRANCH
		 This package contains device blobs from the Linux kernel, version ${kernel_version_family}
	CONTROL_FILE

	kernel_package_hook_helper "preinst" <(
		cat <<- EOT
			rm -rf /boot/dtb
			rm -rf /boot/dtb-${kernel_version_family}
		EOT
	)

	kernel_package_hook_helper "postinst" <(
		cat <<- EOT
			cd /boot
			ln -sfT dtb-${kernel_version_family} dtb || mv dtb-${kernel_version_family} dtb
		EOT
	)

}
