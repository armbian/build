# @description Builds a bootable live `.iso` from a UEFI image so it boots from a BMC/IPMI virtual CD-ROM or a USB stick. Packs the kernel, `live-boot` initrd and a squashfs rootfs into a hybrid ISO9660 with GRUB (`xorriso`/`mksquashfs`/`grub-mkstandalone`), dropping the `.img` by default. Boots UEFI (Secure Boot off) and, on amd64, legacy BIOS; restricted to `uefi-*` boards using the `grub` extension.

#
# SPDX-License-Identifier: GPL-2.0
#
# Extension: image-output-iso
#
# Produce a bootable LIVE .iso from a UEFI build (amd64 and arm64; riscv64 is
# EXPERIMENTAL/untested) so it can be booted from a BMC/IPMI *virtual CD* (cloud,
# IPMI, KVM). On a virtual CD the firmware boots via El Torito and the
# only device grub/kernel see is the ISO itself, so everything needed to boot
# must live inside the ISO9660 filesystem — exactly like Ubuntu Server's ISO:
#
#   /live/vmlinuz            - the kernel
#   /live/initrd.img         - the initrd, with live-boot support
#   /live/filesystem.squashfs- the rootfs, mounted read-only + a RAM overlay
#   /boot/grub/              - grub.cfg, font and wallpaper; i386-pc modules on amd64
#   El Torito UEFI boot      - a self-contained grub (all modules embedded) in an
#                              appended ESP, so a dd copy on USB boots too
#   El Torito BIOS boot      - amd64 only: grub i386-pc + a hybrid MBR
#
# An earlier "wrap the disk image" approach kept the kernel/rootfs on a separate
# GPT partition, which is invisible under virtual-CD boot — grub loaded but had
# nothing to boot. This live layout is the only shape a virtual CD actually runs.
#
# Enable with `enable_extension "image-output-iso"` on a UEFI target that uses the `grub`
# extension (uefi-x86 / uefi-arm64; riscv64 experimental).
#
# Firmware requirements to boot the ISO:
#   * UEFI firmware, or legacy BIOS/SeaBIOS on amd64. arm64/riscv64 are UEFI-only.
#     armbian-install on a BIOS-booted live system installs GRUB for BIOS.
#   * Secure Boot must be DISABLED: grub (grub-mkstandalone) and the Armbian kernel
#     are unsigned, so a Secure-Boot-enabled machine rejects them. Signing the boot
#     chain (Debian shim + an Armbian MOK, or distro-signed kernel) is a possible
#     future addition; for now boot with Secure Boot off.
#
# Vars:
#   SKIP_ISO=yes       - do nothing
#   ISO_VOLID="..."    - ISO9660 volume id (max 32 chars, default ARMBIAN)
#   ISO_COMP="zstd"    - squashfs compressor (zstd|xz|gzip)
#   ISO_TIMEOUT=1      - grub wait in seconds; the menu is hidden, Esc shows it (0 = no wait)
#   ISO_KEEP_IMG=no    - keep the .img alongside the .iso (default: drop it)
#

function extension_prepare_config__prepare_image_output_iso_config() {
	declare -g SKIP_ISO="${SKIP_ISO:-no}"
	[[ "${SKIP_ISO}" == "yes" ]] && return 0
	# image-output-iso only applies to the generic UEFI families (uefi-x86 / uefi-arm64 /
	# uefi-riscv64 / ...). Gate on BOARDFAMILY, not BOARD, so qemu-uefi-x86
	# (BOARDFAMILY=uefi-x86, but BOARD starts with qemu-) is covered. On anything
	# else, warn and disable rather than error.
	if [[ "${BOARDFAMILY}" != uefi* ]]; then
		display_alert "Extension: ${EXTENSION}: disabled" "only supported on UEFI boards (BOARDFAMILY=uefi*), not '${BOARDFAMILY}'" "wrn"
		declare -g SKIP_ISO="yes"
		return 0
	fi
	declare -g ISO_VOLID="${ISO_VOLID:-ARMBIAN}"
	declare -g ISO_COMP="${ISO_COMP:-zstd}"
	declare -g ISO_TIMEOUT="${ISO_TIMEOUT:-1}"
	declare -g ISO_KEEP_IMG="${ISO_KEEP_IMG:-no}" # the ISO carries the rootfs; drop the .img by default

	# The kernel/grub run over a serial-and-VGA console: gfxterm needs a font/module
	# that is not embedded, and IPMI wants serial/text anyway.
	if [[ "${UEFI_GRUB_TERMINAL:-gfxterm}" == *gfxterm* ]]; then
		declare -g UEFI_GRUB_TERMINAL="serial console"
	fi

	# live-boot lets the initrd find /live/filesystem.squashfs on the boot medium
	# and mount it with a writable RAM overlay. Inert on a normal disk boot (only
	# activates with boot=live), so the .img still boots normally.
	add_packages_to_image live-boot live-boot-initramfs-tools
	# i386-pc modules for the BIOS El Torito image, and for armbian-install in BIOS mode.
	# grub-pc-bin installs beside grub-efi-amd64 (grub-pc does not).
	[[ "${ARCH}" == "amd64" ]] && add_packages_to_image grub-pc-bin
	return 0
}

#### *run before installing host dependencies*
function add_host_dependencies__image_output_iso_host_deps() {
	[[ "${SKIP_ISO}" == "yes" ]] && return 0
	EXTRA_BUILD_DEPS+=("image-output-iso::xorriso" "image-output-iso::squashfs-tools" "image-output-iso::mtools" "image-output-iso::dosfstools")
}

#### *hack the mounted final image, before unmount*
# Runs while the final rootfs is mounted at ${MOUNT} (loop ${LOOP}) with the
# live-boot-enabled initrd already built — the right moment to assemble the ISO.
function pre_umount_final_image__800_build_image_output_iso() {
	[[ "${SKIP_ISO}" == "yes" ]] && return 0
	# Map ARCH to the grub EFI target and the fallback boot filename the firmware
	# looks for on removable media (BOOTX64.EFI on x86_64, BOOTAA64.EFI on aarch64).
	declare grub_efi_format efi_boot_name
	case "${ARCH}" in
		amd64) grub_efi_format="x86_64-efi" && efi_boot_name="BOOTX64.EFI" ;;
		arm64) grub_efi_format="arm64-efi" && efi_boot_name="BOOTAA64.EFI" ;;
		riscv64) # experimental / untested
			grub_efi_format="riscv64-efi" && efi_boot_name="BOOTRISCV64.EFI"
			display_alert "Extension: ${EXTENSION}: riscv64 is EXPERIMENTAL and untested" "proceed at your own risk" "wrn"
			;;
		*)
			display_alert "Extension: ${EXTENSION}: skipping" "image-output-iso targets amd64/arm64/riscv64 UEFI, ARCH=${ARCH}" "wrn"
			return 0
			;;
	esac
	[[ -z "${version}" ]] && exit_with_error "version is not set"

	display_alert "Building live UEFI ISO" "${EXTENSION}" "info"

	declare tmp_dir stage_dir
	mkdir -p "${DESTIMG}"
	tmp_dir="$(mktemp -d -p "${DESTIMG}" "image-output-iso.XXXXXX")"
	stage_dir="${tmp_dir}/iso-root"
	mkdir -p "${stage_dir}/live" "${stage_dir}/boot/grub"

	# --- kernel + initrd (newest real files in the image /boot) ---
	declare kernel_file initrd_file
	# Debian/Ubuntu name the compressed kernel vmlinuz-*, but some arm64 kernels
	# (e.g. the 'cloud' branch) install the image as vmlinux-* instead. GRUB boots
	# either, so accept both; prefer vmlinuz-* when both are present.
	kernel_file="$(ls -1 "${MOUNT}"/boot/vmlinuz-* "${MOUNT}"/boot/vmlinux-* 2>/dev/null | grep -vE '\.(manifest|dtb|old)$' | sort -V | tail -1)"
	initrd_file="$(ls -1 "${MOUNT}"/boot/initrd.img-* 2>/dev/null | grep -vE '\.manifest$' | sort -V | tail -1)"
	[[ -f "${kernel_file}" ]] || exit_with_error "image-output-iso: no kernel found under ${MOUNT}/boot"
	[[ -f "${initrd_file}" ]] || exit_with_error "image-output-iso: no initrd found under ${MOUNT}/boot"
	display_alert "Using kernel/initrd" "$(basename "${kernel_file}") / $(basename "${initrd_file}")" "info"
	# run_host_command_logged re-parses its args through `bash -c`, so every call
	# below is built as an array and passed as "${cmd[*]@Q}" (per-element shell
	# quoting) so dynamic values (paths, user-set ISO_VOLID) cannot re-parse.
	declare -a cmd
	cmd=(cp -v "${kernel_file}" "${stage_dir}/live/vmlinuz") && run_host_command_logged "${cmd[*]@Q}"
	cmd=(cp -v "${initrd_file}" "${stage_dir}/live/initrd.img") && run_host_command_logged "${cmd[*]@Q}"

	# --- rootfs squashfs ---
	# The image /etc/fstab pins the installed root and /boot/efi by UUID; those
	# devices do not exist when booted from CD, so systemd blocks ~90s waiting for
	# them and the fstab-generator chokes on a duplicate '/' entry (live-boot
	# already provides root). Neutralize fstab in the squashfs ONLY, then restore
	# the real one so the .img still boots normally.
	declare fstab_bak=""
	if [[ -f "${MOUNT}/etc/fstab" ]]; then
		fstab_bak="$(mktemp)"
		cp -a "${MOUNT}/etc/fstab" "${fstab_bak}"
		cat > "${MOUNT}/etc/fstab" <<- 'LIVEFSTAB'
			# Live ISO: root is provided by live-boot (RAM overlay).
			# The installed image's UUID entries are intentionally omitted.
		LIVEFSTAB
	fi
	# A crypt image's crypttab names the installed LUKS root. The live system
	# waits 90s for that device. Empty crypttab in the squashfs only.
	declare crypttab_bak=""
	if [[ -f "${MOUNT}/etc/crypttab" ]]; then
		crypttab_bak="$(mktemp)"
		cp -a "${MOUNT}/etc/crypttab" "${crypttab_bak}"
		echo "# Live ISO: no encrypted volumes." > "${MOUNT}/etc/crypttab"
	fi

	# Mask GRUB boot-success bookkeeping services in the live squashfs only: on a
	# read-only live medium they have no writable grubenv to record into, so they
	# fail every boot ("degraded" state, red [FAILED] lines). Removed after squashing
	# so the installed .img (if kept) still records boot success normally.
	declare -a live_mask=(grub-initrd-fallback.service grub2-common.service)
	declare svc
	for svc in "${live_mask[@]}"; do
		ln -sfT /dev/null "${MOUNT}/etc/systemd/system/${svc}"
	done
	# Silence a live-irrelevant systemd generator that spams the console at first
	# boot on Trixie+: systemd-ssh-generator fails querying AF_VSOCK on hosts with
	# no vsock. Masked via /dev/null in the high-priority generator dir. (The other
	# offender, gpt-auto, is disabled on the kernel cmdline: systemd.gpt_auto=0.)
	declare -a live_gen_mask=(systemd-ssh-generator)
	declare gen
	mkdir -p "${MOUNT}/etc/systemd/system-generators"
	for gen in "${live_gen_mask[@]}"; do
		ln -sfT /dev/null "${MOUNT}/etc/systemd/system-generators/${gen}"
	done

	# Exclude the CONTENTS of pseudo/ephemeral dirs but KEEP the (empty) directories
	# themselves: they are mount points the live rootfs needs. Excluding the
	# directories outright leaves the live system with no /proc,/sys,/dev,/run, so
	# init cannot mount them and panics ("Attempted to kill init").
	# No grub.cfg: the ISO boots from its embedded config. Without the file, the
	# kernel postinst skips update-grub, which fails on the overlay root.
	# armbian-install writes a new grub.cfg to the target.
	display_alert "Creating rootfs squashfs (${ISO_COMP})" "${EXTENSION}" "info"
	cmd=(mksquashfs "${MOUNT}" "${stage_dir}/live/filesystem.squashfs"
		-noappend -comp "${ISO_COMP}" -no-progress -wildcards
		-e "proc/*" "sys/*" "dev/*" "run/*" "tmp/*" "var/tmp/*" "var/cache/apt/archives/*"
		"boot/grub/grub.cfg")
	# Capture the result instead of letting a failure abort here, so the mounted
	# image state is ALWAYS restored below (a kept .img is never left with the
	# live-only fstab stub / masked services). Fail after restoring.
	declare squashfs_rc=0
	run_host_command_logged "${cmd[*]@Q}" || squashfs_rc=$?

	# restore the real fstab so the installed .img is unaffected
	if [[ -n "${fstab_bak}" ]]; then
		cp -a "${fstab_bak}" "${MOUNT}/etc/fstab"
		rm -f "${fstab_bak}"
	fi
	if [[ -n "${crypttab_bak}" ]]; then
		cp -a "${crypttab_bak}" "${MOUNT}/etc/crypttab"
		rm -f "${crypttab_bak}"
	fi
	# undo the live-only service/generator masks so the installed .img is unaffected
	for svc in "${live_mask[@]}"; do
		rm -f "${MOUNT}/etc/systemd/system/${svc}"
	done
	for gen in "${live_gen_mask[@]}"; do
		rm -f "${MOUNT}/etc/systemd/system-generators/${gen}"
	done
	[[ "${squashfs_rc}" -ne 0 ]] && exit_with_error "image-output-iso: mksquashfs failed (exit ${squashfs_rc})"

	# --- grub config, shared by the EFI and the BIOS grub ---
	# gfxterm renders the Armbian wallpaper on the VGA/BMC-KVM screen; serial keeps a
	# text menu for SOL. If the font/graphics do not init, fall back to a text console.
	# $prefix (grub's own var) is the EFI memdisk or the ISO /boot/grub (BIOS): both
	# hold the font and wallpaper. Escaped here so the shell leaves it alone.
	# Desktop images with Plymouth boot silently from grub to the splash, like the
	# installed image (see the grub extension). Esc still shows the boot log.
	declare iso_cmdline="boot=live components systemd.gpt_auto=0"
	if [[ "${BUILD_DESKTOP}" == "yes" && "${PLYMOUTH}" == "yes" ]]; then
		iso_cmdline+=" quiet splash loglevel=3 vt.global_cursor_default=0 plymouth.ignore-serial-consoles"
	else
		iso_cmdline+=" loglevel=6"
	fi
	# console=tty1 last: it becomes /dev/console, which Plymouth uses.
	iso_cmdline+=" console=ttyS0,115200 console=ttyAMA0,115200 console=tty1"
	cat > "${MOUNT}/tmp/image-output-iso-grub.cfg" <<- GRUBCFG
		set default=0
		set timeout=${ISO_TIMEOUT}
		set timeout_style=hidden
		# Use serial only when com0 exists. grub probes the ports itself; in an
		# 'if' condition it does not print the error. Without this, the failed
		# 'terminal_output gfxterm serial' leaves gfxterm off.
		insmod serial
		set armbian_serial=0
		if serial --unit=0 --speed=115200; then
		    terminal_input --append serial
		    set armbian_serial=1
		fi
		if loadfont \$prefix/fonts/unicode.pf2 ; then
		    # UEFI: not all_video. Its video_bochs sets the QEMU standard VGA behind the
		    # firmware, and a kernel with only the EFI framebuffer shows garbage.
		    # BIOS (amd64): efi_gop does not exist, use vbe.
		    if [ "\$grub_platform" = "efi" ]; then
		        insmod efi_gop
		    else
		        insmod vbe
		    fi
		    insmod gfxterm
		    insmod png
		    set gfxmode=auto
		    terminal_output gfxterm
		    background_image \$prefix/armbian.png
		else
		    terminal_output console
		fi
		if [ "\$armbian_serial" = "1" ]; then
		    terminal_output --append serial
		fi
		menuentry "Armbian ${version} (live)" {
		    set gfxpayload=keep
		    search --no-floppy --set=root --file /live/vmlinuz
		    linux  /live/vmlinuz ${iso_cmdline}
		    initrd /live/initrd.img
		}
	GRUBCFG

	declare -a grub_assets=()
	if [[ -f "${MOUNT}/usr/share/grub/unicode.pf2" && -f "${MOUNT}/usr/share/images/grub/wallpaper.png" ]]; then
		grub_assets=("fonts/unicode.pf2=/usr/share/grub/unicode.pf2" "armbian.png=/usr/share/images/grub/wallpaper.png")
	else
		display_alert "Extension: ${EXTENSION}: grub wallpaper/font missing" "booting to text menu" "info"
	fi

	# --- self-contained grub EFI (embeds the cfg + all modules; no external deps,
	#     so 'terminal gfxterm not found' and missing-module failures cannot happen) ---
	display_alert "Building standalone grub EFI" "${EXTENSION}" "info"
	# TMPDIR=/tmp: grub-mkstandalone's mkdtemp otherwise inherits the host TMPDIR,
	# a path that does not exist inside the chroot ("cannot make temporary directory").
	declare -a gm_args=(chroot "${MOUNT}" env TMPDIR=/tmp grub-mkstandalone
		--format="${grub_efi_format}"
		--output="/tmp/${efi_boot_name}"
		--modules="part_gpt part_msdos fat iso9660 normal linux echo all_video gfxterm gfxterm_background png test true loadenv search search_fs_uuid search_fs_file search_label configfile serial terminal ls cat halt reboot"
		"boot/grub/grub.cfg=/tmp/image-output-iso-grub.cfg")
	declare asset
	for asset in "${grub_assets[@]}"; do
		gm_args+=("boot/grub/${asset}") # paths inside the chroot
	done
	# grub-mkstandalone runs the target's own binary inside the chroot; on a cross
	# build update_initramfs already undeployed the static qemu, so redeploy it for
	# this call (a no-op / cheap on a native build) and remove it again after.
	deploy_qemu_binary_to_chroot "${MOUNT}" "${EXTENSION}"
	run_host_command_logged "${gm_args[*]@Q}"
	undeploy_qemu_binary_from_chroot "${MOUNT}" "${EXTENSION}"
	[[ -f "${MOUNT}/tmp/${efi_boot_name}" ]] || exit_with_error "image-output-iso: grub-mkstandalone did not produce ${efi_boot_name}"

	# --- EFI boot image: a small FAT holding /EFI/BOOT/${efi_boot_name}. xorriso appends
	#     it as an ESP partition, used by El Torito (CD) and by the firmware (USB). ---
	declare efi_img="${tmp_dir}/efiboot.img"
	declare efi_bytes efi_blocks
	efi_bytes="$(stat -c%s "${MOUNT}/tmp/${efi_boot_name}")"
	efi_blocks=$(((efi_bytes / 1024) + 2048)) # grub + FAT overhead + slack, in KiB
	cmd=(dd if=/dev/zero of="${efi_img}" bs=1024 count="${efi_blocks}" status=none) && run_host_command_logged "${cmd[*]@Q}"
	cmd=(mkfs.vfat -n EFIBOOT "${efi_img}") && run_host_command_logged "${cmd[*]@Q}"
	cmd=(mmd -i "${efi_img}" ::/EFI ::/EFI/BOOT) && run_host_command_logged "${cmd[*]@Q}"
	cmd=(mcopy -i "${efi_img}" "${MOUNT}/tmp/${efi_boot_name}" "::/EFI/BOOT/${efi_boot_name}") && run_host_command_logged "${cmd[*]@Q}"
	rm -f "${MOUNT}/tmp/${efi_boot_name}"

	# --- BIOS grub (amd64): El Torito core image + modules, cfg and assets in /boot/grub ---
	declare bios_dir="${MOUNT}/usr/lib/grub/i386-pc"
	declare -a bios_xorriso_args=()
	if [[ "${ARCH}" == "amd64" ]]; then
		[[ -f "${bios_dir}/boot_hybrid.img" ]] || exit_with_error "image-output-iso: grub-pc-bin missing in the image" "${bios_dir}"
		display_alert "Building BIOS grub El Torito image" "${EXTENSION}" "info"
		mkdir -p "${stage_dir}/boot/grub/i386-pc" "${stage_dir}/boot/grub/fonts"
		cmd=(chroot "${MOUNT}" grub-mkimage -O i386-pc-eltorito -p /boot/grub -o /tmp/eltorito.img biosdisk iso9660)
		deploy_qemu_binary_to_chroot "${MOUNT}" "${EXTENSION}"
		run_host_command_logged "${cmd[*]@Q}"
		undeploy_qemu_binary_from_chroot "${MOUNT}" "${EXTENSION}"
		cmd=(mv "${MOUNT}/tmp/eltorito.img" "${stage_dir}/boot/grub/i386-pc/eltorito.img") && run_host_command_logged "${cmd[*]@Q}"
		cp "${bios_dir}"/*.mod "${bios_dir}"/*.lst "${stage_dir}/boot/grub/i386-pc/"
		cp "${MOUNT}/tmp/image-output-iso-grub.cfg" "${stage_dir}/boot/grub/grub.cfg"
		for asset in "${grub_assets[@]}"; do
			cp "${MOUNT}${asset#*=}" "${stage_dir}/boot/grub/${asset%%=*}"
		done
		bios_xorriso_args=(
			--grub2-mbr "${bios_dir}/boot_hybrid.img"
			--mbr-force-bootable
			-b boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info
			-eltorito-alt-boot)
	fi
	rm -f "${MOUNT}/tmp/image-output-iso-grub.cfg"

	# --- assemble the hybrid ISO: ISO9660 + appended ESP in a GPT, as Ubuntu does.
	#     Boots as CD (El Torito) and as a dd copy on USB. ---
	declare iso="${DESTIMG}/${version}.iso"
	display_alert "Assembling ISO" "${iso}" "info"
	cmd=(xorriso -as mkisofs
		-iso-level 3
		-volid "${ISO_VOLID:0:32}"
		-full-iso9660-filenames
		-partition_offset 16
		-append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "${efi_img}"
		-appended_part_as_gpt
		-c boot.catalog
		"${bios_xorriso_args[@]}"
		-e --interval:appended_partition_2:all:: -no-emul-boot
		-o "${iso}"
		"${stage_dir}")
	run_host_command_logged "${cmd[*]@Q}"

	cmd=(rm -rf "${tmp_dir}") && run_host_command_logged "${cmd[*]@Q}"
	# The ISO is picked up from ${DESTIMG} by the build's normal finalization
	# (compress/checksum + move of all ${version}.* to ${FINALDEST}), same as the
	# .img — no need to track its path in a global that would go stale after the move.
	display_alert "Created live UEFI ISO" "$(basename "${iso}") ($(du -h "${iso}" | cut -f1))" "info"
	return 0
}

#### *custom post build hook*
# The live ISO already contains the whole rootfs (as a squashfs), so the .img is
# redundant. Drop it (default) so only the .iso is finalized/published; runs late
# so any image-output-* conversion (qcow2, ...) has already consumed the .img.
function post_build_image__990_image_output_iso_drop_img() {
	[[ "${SKIP_ISO}" == "yes" ]] && return 0
	[[ "${ISO_KEEP_IMG}" == "yes" ]] && return 0
	[[ -f "${DESTIMG}/${version}.iso" ]] || return 0 # only drop the .img if the ISO was produced
	# Keep the .img when it is about to be written to a card: that write happens
	# right after this hook (rootfs-to-image.sh) and is guarded by the .img existing.
	if [[ -n "${CARD_DEVICE:-}" ]]; then
		display_alert "Extension: ${EXTENSION}: keeping .img" "CARD_DEVICE=${CARD_DEVICE} is set" "info"
		return 0
	fi
	if [[ -f "${DESTIMG}/${version}.img" ]]; then
		display_alert "Extension: ${EXTENSION}: dropping .img (ISO carries the rootfs)" "${version}.img" "info"
		run_host_command_logged rm -vf "${DESTIMG}/${version}.img" # .img.txt is created later, after this hook
	fi
	return 0
}
