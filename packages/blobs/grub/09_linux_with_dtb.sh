#! /bin/sh
set -e

# This is an Armbian-specific /etc/grub.d/09_linux_with_dtb.sh
# It has been cobbled together from bookworm's 10_linux and Ubuntu's 10_linux.
# The main change is looking for a version-specific /boot/armbian-dtb-<version> file or symlink.
# Ubuntu's original implementation is at https://git.launchpad.net/~ubuntu-core-dev/grub/+git/ubuntu/tree/debian/patches/ubuntu-add-devicetree-command-support.patch
# We've further modified it to only look for a specific version, check it is a file or symlink, write the used name.

# grub-mkconfig helper script.
# Copyright (C) 2006,2007,2008,2009,2010  Free Software Foundation, Inc.
#
# GRUB is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# GRUB is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with GRUB.  If not, see <http://www.gnu.org/licenses/>.

prefix="/usr"
exec_prefix="/usr"
datarootdir="/usr/share"
ubuntu_recovery="0"
quiet_boot="0"
quick_boot="0"
gfxpayload_dynamic="0"
vt_handoff="0"

. "$pkgdatadir/grub-mkconfig_lib"

export TEXTDOMAIN=grub
export TEXTDOMAINDIR="${datarootdir}/locale"

CLASS="--class gnu-linux --class gnu --class os"
SUPPORTED_INITS="sysvinit:/lib/sysvinit/init systemd:/lib/systemd/systemd upstart:/sbin/upstart"

if [ "x${GRUB_DISTRIBUTOR}" = "x" ]; then
	OS=GNU/Linux
else
	case ${GRUB_DISTRIBUTOR} in
		Ubuntu | Kubuntu)
			OS="${GRUB_DISTRIBUTOR}"
			;;
		*)
			OS="${GRUB_DISTRIBUTOR} GNU/Linux"
			;;
	esac
	CLASS="--class $(echo ${GRUB_DISTRIBUTOR} | tr 'A-Z' 'a-z' | cut -d' ' -f1 | LC_ALL=C sed 's,[^[:alnum:]_],_,g') ${CLASS}"
fi

# loop-AES arranges things so that /dev/loop/X can be our root device, but
# the initrds that Linux uses don't like that.
case ${GRUB_DEVICE} in
	/dev/loop/* | /dev/loop[0-9])
		GRUB_DEVICE=$(losetup ${GRUB_DEVICE} | sed -e "s/^[^(]*(\([^)]\+\)).*/\1/")
		# We can't cope with devices loop-mounted from files here.
		case ${GRUB_DEVICE} in
			/dev/*) ;;
			*) exit 0 ;;
		esac
		;;
esac

# Default to disabling partition uuid support to maintian compatibility with
# older kernels.
GRUB_DISABLE_LINUX_PARTUUID=${GRUB_DISABLE_LINUX_PARTUUID-true}

# btrfs may reside on multiple devices. We cannot pass them as value of root= parameter
# and mounting btrfs requires user space scanning, so force UUID in this case.
if ([ "x${GRUB_DEVICE_UUID}" = "x" ] && [ "x${GRUB_DEVICE_PARTUUID}" = "x" ]) ||
	([ "x${GRUB_DISABLE_LINUX_UUID}" = "xtrue" ] &&
		[ "x${GRUB_DISABLE_LINUX_PARTUUID}" = "xtrue" ]) ||
	(! test -e "/dev/disk/by-uuid/${GRUB_DEVICE_UUID}" &&
		! test -e "/dev/disk/by-partuuid/${GRUB_DEVICE_PARTUUID}") ||
	(test -e "${GRUB_DEVICE}" && uses_abstraction "${GRUB_DEVICE}" lvm); then
	LINUX_ROOT_DEVICE=${GRUB_DEVICE}
elif [ "x${GRUB_DEVICE_UUID}" = "x" ] ||
	[ "x${GRUB_DISABLE_LINUX_UUID}" = "xtrue" ]; then
	LINUX_ROOT_DEVICE=PARTUUID=${GRUB_DEVICE_PARTUUID}
else
	LINUX_ROOT_DEVICE=UUID=${GRUB_DEVICE_UUID}
fi

case x"$GRUB_FS" in
	xbtrfs)
		rootsubvol="$(make_system_path_relative_to_its_root /)"
		rootsubvol="${rootsubvol#/}"
		if [ "x${rootsubvol}" != x ]; then
			GRUB_CMDLINE_LINUX="rootflags=subvol=${rootsubvol} ${GRUB_CMDLINE_LINUX}"
		fi
		;;
	xzfs)
		rpool=$(${grub_probe} --device ${GRUB_DEVICE} --target=fs_label 2> /dev/null || true)
		bootfs="$(make_system_path_relative_to_its_root / | sed -e "s,@$,,")"
		LINUX_ROOT_DEVICE="ZFS=${rpool}${bootfs%/}"
		;;
esac

title_correction_code=

if [ -x /lib/recovery-mode/recovery-menu ]; then
	GRUB_CMDLINE_LINUX_RECOVERY=recovery
else
	GRUB_CMDLINE_LINUX_RECOVERY=single
fi
if [ "$ubuntu_recovery" = 1 ]; then
	GRUB_CMDLINE_LINUX_RECOVERY="$GRUB_CMDLINE_LINUX_RECOVERY nomodeset"
fi

if [ "$vt_handoff" = 1 ]; then
	for word in $GRUB_CMDLINE_LINUX_DEFAULT; do
		if [ "$word" = splash ]; then
			GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT \$vt_handoff"
		fi
	done
fi

linux_entry() {
	os="$1"
	version="$2"
	type="$3"
	args="$4"

	if [ -z "$boot_device_id" ]; then
		boot_device_id="$(grub_get_device_id "${GRUB_DEVICE}")"
	fi
	if [ x$type != xsimple ]; then
		case $type in
			recovery)
				title="$(gettext_printf "%s, with Linux %s (%s)" "${os}" "${version}" "$(gettext "${GRUB_RECOVERY_TITLE}")")"
				;;
			init-*)
				title="$(gettext_printf "%s, with Linux %s (%s)" "${os}" "${version}" "${type#init-}")"
				;;
			*)
				title="$(gettext_printf "%s, with Linux %s" "${os}" "${version}")"
				;;
		esac
		if [ x"$title" = x"$GRUB_ACTUAL_DEFAULT" ] || [ x"Previous Linux versions>$title" = x"$GRUB_ACTUAL_DEFAULT" ]; then
			replacement_title="$(echo "Advanced options for ${OS}" | sed 's,>,>>,g')>$(echo "$title" | sed 's,>,>>,g')"
			quoted="$(echo "$GRUB_ACTUAL_DEFAULT" | grub_quote)"
			title_correction_code="${title_correction_code}if [ \"x\$default\" = '$quoted' ]; then default='$(echo "$replacement_title" | grub_quote)'; fi;"
			grub_warn "$(gettext_printf "Please don't use old title \`%s' for GRUB_DEFAULT, use \`%s' (for versions before 2.00) or \`%s' (for 2.00 or later)" "$GRUB_ACTUAL_DEFAULT" "$replacement_title" "gnulinux-advanced-$boot_device_id>gnulinux-$version-$type-$boot_device_id")"
		fi
		echo "menuentry '$(echo "$title" | grub_quote)' ${CLASS} \$menuentry_id_option 'gnulinux-$version-$type-$boot_device_id' {" | sed "s/^/$submenu_indentation/"
	else
		echo "menuentry '$(echo "$os" | grub_quote)' ${CLASS} \$menuentry_id_option 'gnulinux-simple-$boot_device_id' {" | sed "s/^/$submenu_indentation/"
	fi
	if [ "$quick_boot" = 1 ]; then
		echo "	recordfail" | sed "s/^/$submenu_indentation/"
	fi
	if [ x$type != xrecovery ]; then
		save_default_entry | grub_add_tab
	fi

	# Use ELILO's generic "efifb" when it's known to be available.
	# FIXME: We need an interface to select vesafb in case efifb can't be used.
	if [ "x$GRUB_GFXPAYLOAD_LINUX" = x ]; then
		echo "	load_video" | sed "s/^/$submenu_indentation/"
	else
		if [ "x$GRUB_GFXPAYLOAD_LINUX" != xtext ]; then
			echo "	load_video" | sed "s/^/$submenu_indentation/"
		fi
	fi
	if ([ "$ubuntu_recovery" = 0 ] || [ x$type != xrecovery ]) &&
		([ "x$GRUB_GFXPAYLOAD_LINUX" != x ] || [ "$gfxpayload_dynamic" = 1 ]); then
		echo "	gfxmode \$linux_gfx_mode" | sed "s/^/$submenu_indentation/"
	fi

	echo "	insmod gzio" | sed "s/^/$submenu_indentation/"
	echo "	if [ x\$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi" | sed "s/^/$submenu_indentation/"

	if [ x$dirname = x/ ]; then
		if [ -z "${prepare_root_cache}" ]; then
			prepare_root_cache="$(prepare_grub_to_access_device ${GRUB_DEVICE} | grub_add_tab)"
		fi
		printf '%s\n' "${prepare_root_cache}" | sed "s/^/$submenu_indentation/"
	else
		if [ -z "${prepare_boot_cache}" ]; then
			prepare_boot_cache="$(prepare_grub_to_access_device ${GRUB_DEVICE_BOOT} | grub_add_tab)"
		fi
		printf '%s\n' "${prepare_boot_cache}" | sed "s/^/$submenu_indentation/"
	fi
	if [ x"$quiet_boot" = x0 ] || [ x"$type" != xsimple ]; then
		message="$(gettext_printf "Loading Linux %s ..." ${version})"
		sed "s/^/$submenu_indentation/" << EOF
	echo	'$(echo "$message" | grub_quote)'
EOF
	fi
	if test -d /sys/firmware/efi && test -e "${linux}.efi.signed"; then
		sed "s/^/$submenu_indentation/" << EOF
	linux	${rel_dirname}/${basename}.efi.signed root=${linux_root_device_thisversion} ro ${args}
EOF
	else
		sed "s/^/$submenu_indentation/" << EOF
	linux	${rel_dirname}/${basename} root=${linux_root_device_thisversion} ro ${args}
EOF
	fi
	if test -n "${initrd}"; then
		# TRANSLATORS: ramdisk isn't identifier. Should be translated.
		if [ x"$quiet_boot" = x0 ] || [ x"$type" != xsimple ]; then
			message="$(gettext_printf "Loading initial ramdisk ...")"
			sed "s/^/$submenu_indentation/" << EOF
	echo	'$(echo "$message" | grub_quote)'
EOF
		fi
		initrd_path=
		for i in ${initrd}; do
			initrd_path="${initrd_path} ${rel_dirname}/${i}"
		done
		sed "s/^/$submenu_indentation/" << EOF
	initrd	$(echo $initrd_path)
EOF
	fi
	if test -n "${dtb}"; then
		if [ x"$quiet_boot" = x0 ] || [ x"$type" != xsimple ]; then
			message="$(gettext_printf "Loading device tree blob...")"
			sed "s/^/$submenu_indentation/" << EOF
	echo	'$(echo "$message ${rel_dirname}/${dtb}" | grub_quote)'
EOF
		fi
		sed "s/^/$submenu_indentation/" << EOF
	devicetree	${rel_dirname}/${dtb}
EOF
	fi

	sed "s/^/$submenu_indentation/" << EOF
}
EOF
}

machine=$(uname -m)
case "x$machine" in
	xi?86 | xx86_64)
		list=
		for i in /boot/vmlinuz-* /vmlinuz-* /boot/kernel-*; do
			if grub_file_is_not_garbage "$i"; then list="$list $i"; fi
		done
		;;
	*)
		list=
		for i in /boot/vmlinuz-* /boot/vmlinux-* /vmlinuz-* /vmlinux-* /boot/kernel-*; do
			if grub_file_is_not_garbage "$i"; then list="$list $i"; fi
		done
		;;
esac

case "$machine" in
	i?86) GENKERNEL_ARCH="x86" ;;
	mips | mips64) GENKERNEL_ARCH="mips" ;;
	mipsel | mips64el) GENKERNEL_ARCH="mipsel" ;;
	arm*) GENKERNEL_ARCH="arm" ;;
	*) GENKERNEL_ARCH="$machine" ;;
esac

prepare_boot_cache=
prepare_root_cache=
boot_device_id=
title_correction_code=

cat << 'EOF'
function gfxmode {
	set gfxpayload="${1}"
EOF
if [ "$vt_handoff" = 1 ]; then
	cat << 'EOF'
	if [ "${1}" = "keep" ]; then
		set vt_handoff=vt.handoff=7
	else
		set vt_handoff=
	fi
EOF
fi
cat << EOF
}
EOF

# Use ELILO's generic "efifb" when it's known to be available.
# FIXME: We need an interface to select vesafb in case efifb can't be used.
if [ "x$GRUB_GFXPAYLOAD_LINUX" != x ] || [ "$gfxpayload_dynamic" = 0 ]; then
	echo "set linux_gfx_mode=$GRUB_GFXPAYLOAD_LINUX"
else
	cat << EOF
if [ "\${recordfail}" != 1 ]; then
  if [ -e \${prefix}/gfxblacklist.txt ]; then
    if hwmatch \${prefix}/gfxblacklist.txt 3; then
      if [ \${match} = 0 ]; then
        set linux_gfx_mode=keep
      else
        set linux_gfx_mode=text
      fi
    else
      set linux_gfx_mode=text
    fi
  else
    set linux_gfx_mode=keep
  fi
else
  set linux_gfx_mode=text
fi
EOF
fi
cat << EOF
export linux_gfx_mode
EOF

# Extra indentation to add to menu entries in a submenu. We're not in a submenu
# yet, so it's empty. In a submenu it will be equal to '\t' (one tab).
submenu_indentation=""

is_top_level=true
while [ "x$list" != "x" ]; do
	linux=$(version_find_latest $list)
	case $linux in
		*.efi.signed)
			# We handle these in linux_entry.
			list=$(echo $list | tr ' ' '\n' | grep -vx $linux | tr '\n' ' ')
			continue
			;;
	esac
	gettext_printf "Found linux image: %s\n" "$linux" >&2
	basename=$(basename $linux)
	dirname=$(dirname $linux)
	rel_dirname=$(make_system_path_relative_to_its_root $dirname)
	version=$(echo $basename | sed -e "s,^[^0-9]*-,,g")
	alt_version=$(echo $version | sed -e "s,\.old$,,g")
	linux_root_device_thisversion="${LINUX_ROOT_DEVICE}"

	initrd_early=
	for i in ${GRUB_EARLY_INITRD_LINUX_STOCK} \
		${GRUB_EARLY_INITRD_LINUX_CUSTOM}; do
		if test -e "${dirname}/${i}"; then
			initrd_early="${initrd_early} ${i}"
		fi
	done

	initrd_real=
	for i in "initrd.img-${version}" "initrd-${version}.img" "initrd-${version}.gz" \
		"initrd-${version}" "initramfs-${version}.img" \
		"initrd.img-${alt_version}" "initrd-${alt_version}.img" \
		"initrd-${alt_version}" "initramfs-${alt_version}.img" \
		"initramfs-genkernel-${version}" \
		"initramfs-genkernel-${alt_version}" \
		"initramfs-genkernel-${GENKERNEL_ARCH}-${version}" \
		"initramfs-genkernel-${GENKERNEL_ARCH}-${alt_version}"; do
		if test -e "${dirname}/${i}"; then
			initrd_real="${i}"
			break
		fi
	done

	initrd=
	if test -n "${initrd_early}" || test -n "${initrd_real}"; then
		initrd="${initrd_early} ${initrd_real}"

		initrd_display=
		for i in ${initrd}; do
			initrd_display="${initrd_display} ${dirname}/${i}"
		done
		gettext_printf "Found initrd image: %s\n" "$(echo $initrd_display)" >&2
	fi

	dtb=
	# shellcheck disable=SC2066 # yeah I know, just wanna keep it similar to Ubuntu's
	for i in "armbian-dtb-${version}"; do # This used to include "dtb" but that conflicts with Armbian's linux-dtb
		if test -e "${dirname}/${i}"; then
			gettext_printf "Found DTB path: %s\n" "${dirname}/${i}" >&2

			# skip if it's a directory, and in the case of Armbian's linux-dtb.
			if test -d "${dirname}/${i}"; then
				gettext_printf "Found DTB directory, skipping: %s\n" "${dirname}/${i}" >&2
				continue
			fi
			dtb="$i"
			gettext_printf "Found DTB file, using it: %s\n" "${dirname}/${i}" >&2
			break
		fi
	done

	config=
	for i in "${dirname}/config-${version}" "${dirname}/config-${alt_version}" "/etc/kernels/kernel-config-${version}"; do
		if test -e "${i}"; then
			config="${i}"
			break
		fi
	done

	initramfs=
	if test -n "${config}"; then
		initramfs=$(grep CONFIG_INITRAMFS_SOURCE= "${config}" | cut -f2 -d= | tr -d \")
	fi

	if test -z "${initramfs}" && test -z "${initrd_real}"; then
		# "UUID=" and "ZFS=" magic is parsed by initrd or initramfs.  Since there's
		# no initrd or builtin initramfs, it can't work here.
		if [ "x${GRUB_DEVICE_PARTUUID}" = "x" ] ||
			[ "x${GRUB_DISABLE_LINUX_PARTUUID}" = "xtrue" ]; then

			linux_root_device_thisversion=${GRUB_DEVICE}
		else
			linux_root_device_thisversion=PARTUUID=${GRUB_DEVICE_PARTUUID}
		fi
	fi

	# The GRUB_DISABLE_SUBMENU option used to be different than others since it was
	# mentioned in the documentation that has to be set to 'y' instead of 'true' to
	# enable it. This caused a lot of confusion to users that set the option to 'y',
	# 'yes' or 'true'. This was fixed but all of these values must be supported now.
	if [ "x${GRUB_DISABLE_SUBMENU}" = xyes ] || [ "x${GRUB_DISABLE_SUBMENU}" = xy ]; then
		GRUB_DISABLE_SUBMENU="true"
	fi

	if [ "x$is_top_level" = xtrue ] && [ "x${GRUB_DISABLE_SUBMENU}" != xtrue ]; then
		linux_entry "${OS}" "${version}" simple \
			"${GRUB_CMDLINE_LINUX} ${GRUB_CMDLINE_LINUX_DEFAULT}"

		submenu_indentation="$grub_tab"

		if [ -z "$boot_device_id" ]; then
			boot_device_id="$(grub_get_device_id "${GRUB_DEVICE}")"
		fi
		# TRANSLATORS: %s is replaced with an OS name
		echo "submenu '$(gettext_printf "Advanced options for %s" "${OS}" | grub_quote)' \$menuentry_id_option 'gnulinux-advanced-$boot_device_id' {"
		is_top_level=false
	fi

	linux_entry "${OS}" "${version}" advanced \
		"${GRUB_CMDLINE_LINUX} ${GRUB_CMDLINE_LINUX_DEFAULT}"
	for supported_init in ${SUPPORTED_INITS}; do
		init_path="${supported_init#*:}"
		if [ -x "${init_path}" ] && [ "$(readlink -f /sbin/init)" != "$(readlink -f "${init_path}")" ]; then
			linux_entry "${OS}" "${version}" "init-${supported_init%%:*}" \
				"${GRUB_CMDLINE_LINUX} ${GRUB_CMDLINE_LINUX_DEFAULT} init=${init_path}"
		fi
	done
	if [ "x${GRUB_DISABLE_RECOVERY}" != "xtrue" ]; then
		linux_entry "${OS}" "${version}" recovery \
			"${GRUB_CMDLINE_LINUX_RECOVERY} ${GRUB_CMDLINE_LINUX}"
	fi

	list=$(echo $list | tr ' ' '\n' | fgrep -vx "$linux" | tr '\n' ' ')
done

# If at least one kernel was found, then we need to
# add a closing '}' for the submenu command.
if [ x"$is_top_level" != xtrue ]; then
	echo '}'
fi

echo "$title_correction_code"
