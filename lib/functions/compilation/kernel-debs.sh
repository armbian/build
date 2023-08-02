#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

# This is a re-imagining of mkdebian and builddeb from the kernel tree.

# We wanna produce Debian/Ubuntu compatible packages so we're able to use their standard tools, like
# `flash-kernel`, `u-boot-menu`, `grub2`, and others, so we gotta stick to their conventions.

# The main difference is that this is NOT invoked from KBUILD's Makefile, but instead
# directly by Armbian, with references to the dirs where KBUILD's
# `make install dtbs_install modules_install headers_install` have already successfully been run.

# This will create a SET of packages. It should always create these:
# image package: vmlinuz and such, config, modules, and dtbs (if exist) in /usr/lib/xxx
# linux-headers package: "just" the kernel headers, for building out-of-tree modules, dkms, etc.
# linux-dtbs package: only dtbs, if they exist. in /boot/

# So this will handle
# - Creating .deb package skeleton dir (mktemp)
# - Moving/copying around of KBUILD installed stuff for Debian/Ubuntu/Armbian standard locations, in the correct packages
# - Fixing the symlinks to stuff so they fit a target system.
# - building the .debs.

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
	: "${artifact_version:?artifact_version is not set}"

	declare kernel_work_dir="${1}"
	declare kernel_dest_install_dir="${2}"
	declare kernel_version="${3}"
	declare -n tmp_kernel_install_dirs="${4}" # nameref to 	declare -n kernel_install_dirs dictionary
	declare debs_target_dir="${kernel_work_dir}/.."

	# Some variables and settings used throughout the script
	declare kernel_version_family="${kernel_version}-${BRANCH}-${LINUXFAMILY}"

	# Package version. Affects users upgrading from repo!
	display_alert "Kernel .deb package version" "${artifact_version}" "info"

	# show incoming tree
	#display_alert "Kernel install dir" "incoming from KBUILD make" "debug"
	#run_host_command_logged tree -C --du -h "${kernel_dest_install_dir}" "| grep --line-buffered -v -e '\.ko' -e '\.h' "

	# display_alert "tmp_kernel_install_dirs INSTALL_PATH:" "${tmp_kernel_install_dirs[INSTALL_PATH]}" "debug"
	# display_alert "tmp_kernel_install_dirs INSTALL_MOD_PATH:" "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}" "debug"
	# display_alert "tmp_kernel_install_dirs INSTALL_HDR_PATH:" "${tmp_kernel_install_dirs[INSTALL_HDR_PATH]}" "debug"
	# display_alert "tmp_kernel_install_dirs INSTALL_DTBS_PATH:" "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" "debug"

	# Due to we call `make install` twice, we will get some `.old` files
	run_host_command_logged rm -rf "${tmp_kernel_install_dirs[INSTALL_PATH]}/*.old" || true

	# package the linux-image (image, modules, dtbs (if present))
	display_alert "Packaging linux-image" "${LINUXFAMILY} ${LINUXCONFIG}" "info"
	create_kernel_deb "linux-image-${BRANCH}-${LINUXFAMILY}" "${debs_target_dir}" kernel_package_callback_linux_image "linux-image"

	# if dtbs present, package those too separately, for u-boot usage.
	if [[ -d "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" ]]; then
		display_alert "Packaging linux-dtb" "${LINUXFAMILY} ${LINUXCONFIG}" "info"
		create_kernel_deb "linux-dtb-${BRANCH}-${LINUXFAMILY}" "${debs_target_dir}" kernel_package_callback_linux_dtb "linux-dtb"
	fi

	if [[ "${KERNEL_HAS_WORKING_HEADERS}" == "yes" ]]; then
		display_alert "Packaging linux-headers" "${LINUXFAMILY} ${LINUXCONFIG}" "info"
		create_kernel_deb "linux-headers-${BRANCH}-${LINUXFAMILY}" "${debs_target_dir}" kernel_package_callback_linux_headers "linux-headers"
	else
		display_alert "Skipping linux-headers package" "for ${KERNEL_MAJOR_MINOR} kernel version" "info"
	fi
}

function create_kernel_deb() {
	declare package_name="${1}"
	declare deb_output_dir="${2}"
	declare callback_function="${3}"
	declare artifact_deb_id="${4}"

	declare cleanup_id="" package_directory=""
	prepare_temp_dir_in_workdir_and_schedule_cleanup "deb-k-${package_name}" cleanup_id package_directory # namerefs

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
	# display_alert "Running callback" "callback: ${callback_function}" "debug"
	"${callback_function}" "${@}"

	run_host_command_logged chown -R root:root "${package_directory}" # Fix ownership and permissions
	run_host_command_logged chmod -R go-w "${package_directory}"      # Fix ownership and permissions
	run_host_command_logged chmod -R a+rX "${package_directory}"      # in case we are in a restrictive umask environment like 0077
	run_host_command_logged chmod -R ug-s "${package_directory}"      # in case we build in a setuid/setgid directory

	cd "${package_directory}" || exit_with_error "major failure 774 for ${package_name}"

	# create md5sums file
	# sh -c "cd '${package_directory}'; find . -type f ! -path './DEBIAN/*' -printf '%P\0' | xargs -r0 md5sum > DEBIAN/md5sums"

	declare unpacked_size
	unpacked_size="$(du -h -s "${package_directory}" | awk '{print $1}')"
	display_alert "Unpacked ${package_name} tree" "${unpacked_size}" "debug"

	# Show it
	#display_alert "Package dir" "for package ${package_name}" "debug"
	#run_host_command_logged tree -C -h -d --du "${package_directory}"

	fakeroot_dpkg_deb_build "${package_directory}" "${artifact_deb_id}"

	done_with_temp_dir "${cleanup_id}" # changes cwd to "${SRC}" and fires the cleanup function early
}

function kernel_package_hook_helper() {
	declare script="${1}"
	declare contents="${2}"

	cat >> "${package_DEBIAN_dir}/${script}" <<- EOT
		#!/bin/bash
		echo "Armbian '${package_name}' for '${kernel_version_family}': '${script}' starting."
		set -e # Error control

		function is_boot_dev_vfat() {
			# When installing these packages during image build, /boot is not mounted, and will most definitely not be vfat.
			# Use an environment variable to signal that it _will_ be a fat32, so symlinks are not created.
			# This is passed by install_deb_chroot() explicitly via the runners.
			if [[ "\${ARMBIAN_IMAGE_BUILD_BOOTFS_TYPE:-"unknown"}" == "fat" ]]; then
				echo "Armbian: ARMBIAN_IMAGE_BUILD_BOOTFS_TYPE: '\${ARMBIAN_IMAGE_BUILD_BOOTFS_TYPE:-"not set"}'"
				return 0
			fi
			if ! mountpoint -q /boot; then
				return 1
			fi
			local boot_partition bootfstype
			boot_partition=\$(findmnt --nofsroot -n -o SOURCE /boot)
			bootfstype=\$(blkid -s TYPE -o value \$boot_partition)
			if [[ "\$bootfstype" == "vfat" ]]; then
				return 0
			fi
			return 1
		}

		#set -x # Debugging

		$(cat "${contents}")

		set +x # Disable debugging
		echo "Armbian '${package_name}' for '${kernel_version_family}': '${script}' finishing."
		true
	EOT
	chmod 775 "${package_DEBIAN_dir}/${script}"

	# produce log asset for script
	LOG_ASSET="deb-${package_name}-${script}.sh" do_with_log_asset run_host_command_logged cat "${package_DEBIAN_dir}/${script}"

}

function kernel_package_callback_linux_image() {
	display_alert "linux-image deb packaging" "${package_directory}" "debug"

	# @TODO: we expect _all_ kernels to produce this, which is... not true.
	declare kernel_pre_package_path="${tmp_kernel_install_dirs[INSTALL_PATH]}"
	declare kernel_image_pre_package_path="${kernel_pre_package_path}/vmlinuz-${kernel_version_family}"
	declare installed_image_path="boot/vmlinuz-${kernel_version_family}" # using old mkdebian terminology here for compatibility

	display_alert "Showing contents of Kbuild produced /boot" "linux-image" "debug"
	run_host_command_logged tree -C --du -h "${tmp_kernel_install_dirs[INSTALL_PATH]}"

	display_alert "Kernel-built image filetype" "vmlinuz-${kernel_version_family}: $(file --brief "${kernel_image_pre_package_path}")" "info"

	declare image_name="Image" # "Image" for arm64. or, "zImage" for arm, or "vmlinuz" for others. 'image_name' is for easy mkdebian compat
	# If NAME_KERNEL is set (usually in arch config file), warn and use that instead.
	if [[ -n "${NAME_KERNEL}" ]]; then
		display_alert "NAME_KERNEL is set" "using '${NAME_KERNEL}' instead of '${image_name}'" "debug"
		image_name="${NAME_KERNEL}"
	fi

	# allow hook to do stuff here. Some (legacy/vendor/weird) kernels spit out a vmlinuz that needs manual conversion to uImage, etc.
	run_host_command_logged ls -la "${kernel_pre_package_path}" "${kernel_image_pre_package_path}"

	call_extension_method "pre_package_kernel_image" <<- 'PRE_PACKAGE_KERNEL_IMAGE'
		*fix Image/uImage/zImage before packaging kernel*
		Some (legacy/vendor) kernels need preprocessing of the produced Image/uImage/zImage before packaging.
		Use this hook to do that, by modifying the file in place, in `${kernel_pre_package_path}` directory.
		The final file that will be used is stored in `${kernel_image_pre_package_path}` -- which you shouldn't change.
	PRE_PACKAGE_KERNEL_IMAGE

	display_alert "Kernel image filetype after pre_package_kernel_image" "vmlinuz-${kernel_version_family}: $(file --brief "${kernel_image_pre_package_path}")" "info"

	unset kernel_pre_package_path       # be done with var after hook
	unset kernel_image_pre_package_path # be done with var after hook

	run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_PATH]}" "${package_directory}/"         # /boot stuff
	run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_MOD_PATH]}/lib" "${package_directory}/" # so "lib" stuff sits at the root

	# Clean up symlinks in lib/modules/${kernel_version_family}/build and lib/modules/${kernel_version_family}/source; will be in the headers package
	run_host_command_logged rm -v -f "${package_directory}/lib/modules/${kernel_version_family}/build" "${package_directory}/lib/modules/${kernel_version_family}/source"

	if [[ -d "${package_directory}/lib/modules/${kernel_version_family}/kernel" ]]; then
		display_alert "Showing contents of Kbuild produced modules" "linux-image" "debug"
		run_host_command_logged tree -C --du -h -d -L 1 "${package_directory}/lib/modules/${kernel_version_family}/kernel" "|| true" # do not fail
	fi

	if [[ -d "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" ]]; then
		# /usr/lib/linux-image-${kernel_version_family} is wanted by flash-kernel, u-boot-menu, and other standard Debian/Ubuntu utilities

		display_alert "DTBs present on kernel output" "DTBs ${package_name}: /usr/lib/linux-image-${kernel_version_family}" "debug"
		mkdir -p "${package_directory}/usr/lib"
		run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" "${package_directory}/usr/lib/linux-image-${kernel_version_family}"
	fi

	# Generate a control file
	cat <<- CONTROL_FILE > "${package_DEBIAN_dir}/control"
		Package: ${package_name}
		Version: ${artifact_version}
		Source: linux-${kernel_version}
		Armbian-Kernel-Version: ${kernel_version}
		Armbian-Kernel-Version-Family: ${kernel_version_family}
		Architecture: ${ARCH}
		Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
		Section: kernel
		Priority: optional
		Provides: linux-image, linux-image-armbian, armbian-$BRANCH
		Description: Armbian Linux $BRANCH kernel image $kernel_version_family
		 This package contains the Linux kernel, modules and corresponding other files.
		 ${artifact_version_reason:-"${kernel_version_family}"}
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
			# Common for all of postinst/postrm/preinst/prerm
			cat <<- KERNEL_HOOK_DELEGATION # Reference: linux-image-6.1.0-7-amd64.postinst from Debian
				export DEB_MAINT_PARAMS="\$*" # Pass maintainer script parameters to hook scripts
				export INITRD=$(if_enabled_echo CONFIG_BLK_DEV_INITRD Yes No) # Tell initramfs builder whether it's wanted
				# Run the same hooks Debian/Ubuntu would for their kernel packages.
				test -d ${debian_kernel_hook_dir}/${script}.d && run-parts --arg="${kernel_version_family}" --arg="/${installed_image_path}" ${debian_kernel_hook_dir}/${script}.d
			KERNEL_HOOK_DELEGATION

			if [[ "${script}" == "preinst" ]]; then
				cat <<- HOOK_FOR_REMOVE_VFAT_BOOT_FILES
					if is_boot_dev_vfat; then
						rm -f /boot/System.map* /boot/config* /boot/vmlinuz* /boot/$image_name /boot/uImage
					fi
				HOOK_FOR_REMOVE_VFAT_BOOT_FILES
			fi

			# @TODO: only if u-boot, only for postinst. Gotta find a hook scheme for these...
			if [[ "${script}" == "postinst" ]]; then
				cat <<- HOOK_FOR_LINK_TO_LAST_INSTALLED_KERNEL # image_name="${NAME_KERNEL}", above
					touch /boot/.next
					if is_boot_dev_vfat; then
						echo "Armbian: FAT32 /boot: move last-installed kernel to '$image_name'..."
						mv -v /${installed_image_path} /boot/${image_name}
					else
						echo "Armbian: update last-installed kernel symlink to '$image_name'..."
						ln -sfv $(basename "${installed_image_path}") /boot/$image_name
					fi
				HOOK_FOR_LINK_TO_LAST_INSTALLED_KERNEL

				# Reference: linux-image-6.1.0-7-amd64.postinst from Debian
				cat <<- HOOK_FOR_DEBIAN_COMPAT_SYMLINK
					# call debian helper, for compatibility. this symlinks things according to /etc/kernel-img.conf
					# "install" or "upgrade" are decided in a very contrived way by Debian (".fresh-install" file)
					# do NOT do this if /boot is a vfat, though.
					if ! is_boot_dev_vfat; then
						echo "Armbian: Debian compat: linux-update-symlinks install ${kernel_version_family} ${installed_image_path}"
						linux-update-symlinks install "${kernel_version_family}" "${installed_image_path}" || true
					fi
				HOOK_FOR_DEBIAN_COMPAT_SYMLINK
			fi
		)
	done
}

function kernel_package_callback_linux_dtb() {
	display_alert "linux-dtb packaging" "${package_directory}" "debug"

	display_alert "Showing tree of Kbuild produced DTBs" "linux-dtb" "debug"
	run_host_command_logged tree -C --du -h -L 2 "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}"

	mkdir -p "${package_directory}/boot/"
	run_host_command_logged cp -rp "${tmp_kernel_install_dirs[INSTALL_DTBS_PATH]}" "${package_directory}/boot/dtb-${kernel_version_family}"

	# Generate a control file
	cat <<- CONTROL_FILE > "${package_DEBIAN_dir}/control"
		Version: ${artifact_version}
		Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
		Section: kernel
		Package: ${package_name}
		Architecture: ${ARCH}
		Priority: optional
		Provides: linux-dtb, linux-dtb-armbian, armbian-$BRANCH
		Description: Armbian Linux $BRANCH DTBs in /boot/dtb-${kernel_version_family}
		 This package contains device tree blobs from the Linux kernel, version ${kernel_version_family}
		 ${artifact_version_reason:-"${kernel_version_family}"}
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
			if ! is_boot_dev_vfat; then
				echo "Armbian: DTB: symlinking /boot/dtb to /boot/dtb-${kernel_version_family}..."
				ln -sfTv "dtb-${kernel_version_family}" dtb
			else
				echo "Armbian: DTB: FAT32: moving /boot/dtb-${kernel_version_family} to /boot/dtb ..."
				mv -v "dtb-${kernel_version_family}" dtb
			fi
		EOT
	)

}

function kernel_package_callback_linux_headers() {
	display_alert "linux-headers packaging" "${package_directory}" "debug"

	# targets.
	local headers_target_dir="${package_directory}/usr/src/linux-headers-${kernel_version_family}" # headers/tools etc
	local modules_target_dir="${package_directory}/lib/modules/${kernel_version_family}"           # symlink to above later

	mkdir -p "${headers_target_dir}" "${modules_target_dir}"                                                         # create both dirs
	run_host_command_logged ln -v -s "/usr/src/linux-headers-${kernel_version_family}" "${modules_target_dir}/build" # Symlink in modules so builds find the headers
	run_host_command_logged cp -vp "${kernel_work_dir}"/.config "${headers_target_dir}"/.config                      # copy .config manually to be where it's expected to be

	# gather stuff from the linux source tree: ${kernel_work_dir} (NOT the make install destination)
	# those can be source files or object (binary/compiled) stuff
	# how to get SRCARCH? only from the makefile itself. ARCH=amd64 then SRCARCH=x86. How to we know? @TODO
	local SRC_ARCH="${ARCH}"
	[[ "${SRC_ARCH}" == "amd64" ]] && SRC_ARCH="x86"
	[[ "${SRC_ARCH}" == "armhf" ]] && SRC_ARCH="arm"
	[[ "${SRC_ARCH}" == "riscv64" ]] && SRC_ARCH="riscv"
	# @TODO: added KERNEL_SRC_ARCH to each arch'es .config file; let's make sure they're sane. Just use KERNEL_SRC_ARCH after confirmed.
	# Lets check and warn if it isn't. If warns don't popup over time we remove and just use ARCHITECTURE later.
	if [[ "${SRC_ARCH}" != "${KERNEL_SRC_ARCH}" ]]; then
		display_alert "WARNING: KERNEL_SRC_ARCH and SRC_ARCH don't match during kernel build." "KERNEL_SRC_ARCH=${ARCHITECTURE} SRC_ARCH=${SRC_ARCH}" "wrn"
	fi

	# Create a list of files to include, path-relative to the kernel tree
	local temp_file_list="${WORKDIR}/tmp_file_list_${kernel_version_family}.kernel.headers"

	# Find the files we want to include in the package. Those will be later cleaned, etc.
	(
		cd "${kernel_work_dir}" || exit 2
		find . -name Makefile\* -o -name Kconfig\* -o -name \*.pl

		find arch/*/include include scripts -type f -o -type l

		find security/*/include -type f
		[[ -d "arch/${SRC_ARCH}" ]] && {
			find "arch/${SRC_ARCH}" -name module.lds -o -name Kbuild.platforms -o -name Platform
			# shellcheck disable=SC2046 # I need to expand. Thanks.
			find $(find "arch/${SRC_ARCH}" -name include -o -name scripts -type d) -type f
			find arch/${SRC_ARCH}/include -type f
		}
		find Module.symvers include scripts -type f
		find . -name "bitsperlong.h" -type f

		# tools/include/tools has the byteshift utilities shared between kernel proper and the build scripts/tools.
		# This replaces 'headers-debian-byteshift.patch' which was used for years in Armbian.
		find tools -type f       # all tools; will trim a bit later
		find arch/x86/lib/insn.c # required by objtool stuff...

		if is_enabled CONFIG_GCC_PLUGINS; then
			find scripts/gcc-plugins -name gcc-common.h # @TODO something else here too?
		fi
	) > "${temp_file_list}"

	# Now include/copy those, using tar as intermediary. Just like builddeb does it.
	tar -c -f - -C "${kernel_work_dir}" -T "${temp_file_list}" | tar -xf - -C "${headers_target_dir}"

	# ${temp_file_list} is left at WORKDIR for later debugging, will be removed by WORKDIR cleanup trap

	# Small detour: in v6.3-rc1, in commit https://github.com/torvalds/linux/commit/799fb82aa132fa3a3886b7872997a5a84e820062,
	#               the tools/vm dir was renamed to tools/mm. Unfortunately tools/Makefile still expects it to exist,
	#               and "make clean" in the "/tools" dir fails. Drop in a fake Makefile there to work around this.
	if [[ ! -f "${headers_target_dir}/tools/vm/Makefile" ]]; then
		display_alert "Creating fake tools/vm/Makefile" "6.3+ hackfix" "debug"
		run_host_command_logged mkdir -p "${headers_target_dir}/tools/vm"
		echo -e "clean:\n\techo fake clean for tools/vm" > "${headers_target_dir}/tools/vm/Makefile"
	fi

	# Hack for 6.5-rc1: create include/linux dir so the 'clean' step below doesn't fail. I've reported upstream...
	display_alert "Creating fake counter/include/linux" "6.5-rc1 hackfix" "debug"
	run_host_command_logged mkdir -p "${headers_target_dir}/tools/counter/include/linux"

	# Now, make the script dirs clean.
	# This is run in our _target_ dir, NOT the source tree, so we're free to make clean as we wish without invalidating the next build's cache.
	# Understand: I'm sending the logs of this to the bitbucket ON PURPOSE: "clean" tries to use clang, ALSA, etc, which are not available.
	#             The logs produced during this step throw off developers casually looking at the logs.
	#             Important: if the steps _fail_ here, you'll have to enable DEBUG=yes to see what's going on.
	declare make_bitbucket="&> /dev/null"
	[[ "${DEBUG}" == "yes" ]] && make_bitbucket=""
	run_host_command_logged cd "${headers_target_dir}" "&&" make "ARCH=${SRC_ARCH}" "M=scripts" clean "${make_bitbucket}"
	run_host_command_logged cd "${headers_target_dir}/tools" "&&" make "ARCH=${SRC_ARCH}" clean "${make_bitbucket}"

	# Trim down on the tools dir a bit after cleaning.
	rm -rf "${headers_target_dir}/tools/perf" "${headers_target_dir}/tools/testing"

	# Hack: after cleaning, copy over the scripts/module.lds file from the source tree. It will only exist on 5.10+
	# See https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1906131
	[[ -f "${kernel_work_dir}/scripts/module.lds" ]] &&
		run_host_command_logged cp -v "${kernel_work_dir}/scripts/module.lds" "${headers_target_dir}/scripts/module.lds"

	if [[ "${DEBUG}" == "yes" ]]; then
		# Check that no binaries are included by now. Expensive... @TODO: remove after me make sure.
		display_alert "Checking for binaries in kernel headers" "${headers_target_dir}" "debug"
		(
			cd "${headers_target_dir}" || exit 33
			find . -type f | grep -v -e "include/config/" -e "\.h$" -e ".c$" -e "Makefile$" -e "Kconfig$" -e "Kbuild$" -e "\.cocci$" | xargs file | grep -v -e "ASCII" -e "script text" -e "empty" -e "Unicode text" -e "symbolic link" -e "CSV text" -e "SAS 7+" || true
		)
	fi

	# Generate a control file
	# TODO: libssl-dev is only required if we're signing modules, which is a kernel .config option.
	cat <<- CONTROL_FILE > "${package_DEBIAN_dir}/control"
		Version: ${artifact_version}
		Maintainer: ${MAINTAINER} <${MAINTAINERMAIL}>
		Section: devel
		Package: ${package_name}
		Architecture: ${ARCH}
		Priority: optional
		Provides: linux-headers, linux-headers-armbian, armbian-$BRANCH
		Depends: make, gcc, libc6-dev, bison, flex, libssl-dev, libelf-dev
		Description: Armbian Linux $BRANCH headers ${kernel_version_family}
		 This package provides kernel header files for ${kernel_version_family}
		 .
		 This is useful for DKMS and building of external modules.
		 ${artifact_version_reason:-"${kernel_version_family}"}
	CONTROL_FILE

	# Make sure the target dir is clean/not-existing before installing.
	kernel_package_hook_helper "preinst" <(
		cat <<- EOT_PREINST
			if [[ -d "/usr/src/linux-headers-${kernel_version_family}" ]]; then
				echo "Cleaning pre-existing directory /usr/src/linux-headers-${kernel_version_family} ..."
				rm -rf "/usr/src/linux-headers-${kernel_version_family}"
			fi
		EOT_PREINST
	)

	# Make sure the target dir is removed before removing the package; that way we don't leave eventual compilation artifacts over there.
	kernel_package_hook_helper "prerm" <(
		cat <<- EOT_PRERM
			if [[ -d "/usr/src/linux-headers-${kernel_version_family}" ]]; then
				echo "Cleaning directory /usr/src/linux-headers-${kernel_version_family} ..."
				rm -rf "/usr/src/linux-headers-${kernel_version_family}"
			fi
		EOT_PRERM
	)

	kernel_package_hook_helper "postinst" <(
		cat <<- EOT_POSTINST
			cd "/usr/src/linux-headers-${kernel_version_family}"
			NCPU=\$(grep -c 'processor' /proc/cpuinfo)
			echo "Compiling kernel-headers tools (${kernel_version_family}) using \$NCPU CPUs - please wait ..."
			yes "" | make ARCH="${SRC_ARCH}" oldconfig
			make ARCH="${SRC_ARCH}" -j\$NCPU scripts
			make ARCH="${SRC_ARCH}" -j\$NCPU M=scripts/mod/
			# make ARCH="${SRC_ARCH}" -j\$NCPU modules_prepare # depends on too much other stuff.
			echo "Done compiling kernel-headers tools (${kernel_version_family})."
		EOT_POSTINST

		if [[ "${ARCH}" == "amd64" ]]; then # This really only works on x86/amd64; @TODO revisit later
			cat <<- EOT_POSTINST_OBJTOOL
				echo "Compiling kernel-header objtool (${kernel_version_family})."
				make ARCH="${SRC_ARCH}" -j\$NCPU tools/objtool
				echo "Done compiling kernel-header objtool (${kernel_version_family})."
			EOT_POSTINST_OBJTOOL
		fi

		cat <<- EOT_POSTINST_FINISH
			echo "Done compiling kernel-headers tools (${kernel_version_family})."
		EOT_POSTINST_FINISH
	)
}
