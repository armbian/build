# @description Builds a bootable live `.iso` from a UEFI image so it boots from a BMC/IPMI virtual CD-ROM. Packs the kernel, `live-boot` initrd and a squashfs rootfs into a hybrid ISO9660 with self-contained GRUB (`xorriso`/`mksquashfs`/`grub-mkstandalone`), dropping the `.img` by default. UEFI-only with Secure Boot off, restricted to `uefi-*` boards using the `grub` extension.

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
#   El Torito UEFI boot      - a self-contained grub (all modules embedded)
#
# An earlier "wrap the disk image" approach kept the kernel/rootfs on a separate
# GPT partition, which is invisible under virtual-CD boot — grub loaded but had
# nothing to boot. This live layout is the only shape a virtual CD actually runs.
#
# Enable with `enable_extension "image-output-iso"` on a UEFI target that uses the `grub`
# extension (uefi-x86 / uefi-arm64; riscv64 experimental).
#
# Firmware requirements to boot the ISO:
#   * UEFI firmware (the ISO is UEFI-only, like stock Armbian UEFI images; it will
#     NOT boot under legacy BIOS/SeaBIOS).
#   * Secure Boot must be DISABLED: grub (grub-mkstandalone) and the Armbian kernel
#     are unsigned, so a Secure-Boot-enabled machine rejects them. Signing the boot
#     chain (Debian shim + an Armbian MOK, or distro-signed kernel) is a possible
#     future addition; for now boot with Secure Boot off.
#
# Vars:
#   SKIP_ISO=yes       - do nothing
#   ISO_VOLID="..."    - ISO9660 volume id (max 32 chars, default ARMBIAN)
#   ISO_COMP="zstd"    - squashfs compressor (zstd|xz|gzip)
#   ISO_TIMEOUT=1      - grub menu seconds (0 = boot immediately; >0 shows the splash)
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
	display_alert "Creating rootfs squashfs (${ISO_COMP})" "${EXTENSION}" "info"
	cmd=(mksquashfs "${MOUNT}" "${stage_dir}/live/filesystem.squashfs"
		-noappend -comp "${ISO_COMP}" -no-progress -wildcards
		-e "proc/*" "sys/*" "dev/*" "run/*" "tmp/*" "var/tmp/*" "var/cache/apt/archives/*")
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
	# undo the live-only service/generator masks so the installed .img is unaffected
	for svc in "${live_mask[@]}"; do
		rm -f "${MOUNT}/etc/systemd/system/${svc}"
	done
	for gen in "${live_gen_mask[@]}"; do
		rm -f "${MOUNT}/etc/systemd/system-generators/${gen}"
	done
	[[ "${squashfs_rc}" -ne 0 ]] && exit_with_error "image-output-iso: mksquashfs failed (exit ${squashfs_rc})"

	# --- self-contained grub EFI (embeds our cfg + all modules; no external deps,
	#     so 'terminal gfxterm not found' and missing-module failures cannot happen) ---
	# Show the Armbian grub wallpaper (embedded, so no external module/font lookup
	# like the one that used to fail with 'terminal gfxterm not found'). gfxterm
	# renders on the VGA/BMC-KVM screen only; serial keeps a text menu for SOL. If
	# the font/graphics do not init, fall back to a plain text console.
	# $prefix (grub's own var) always points at the embedded memdisk, even after the
	# menuentry's `search` changes $root — escaped here so the shell leaves it alone.
	cat > "${MOUNT}/tmp/image-output-iso-grub.cfg" <<- GRUBCFG
		set default=0
		set timeout=${ISO_TIMEOUT}
		insmod serial
		serial --unit=0 --speed=115200
		terminal_input console serial
		if loadfont \$prefix/fonts/unicode.pf2 ; then
		    insmod all_video
		    insmod gfxterm
		    insmod png
		    set gfxmode=auto
		    terminal_output gfxterm serial
		    background_image \$prefix/armbian.png
		else
		    terminal_output console serial
		fi
		menuentry "Armbian ${version} (live)" {
		    search --no-floppy --set=root --file /live/vmlinuz
		    linux  /live/vmlinuz boot=live components loglevel=6 systemd.gpt_auto=0 console=ttyS0,115200 console=ttyAMA0,115200 console=tty1
		    initrd /live/initrd.img
		}
	GRUBCFG

	display_alert "Building standalone grub EFI" "${EXTENSION}" "info"
	# TMPDIR=/tmp: grub-mkstandalone's mkdtemp otherwise inherits the host TMPDIR,
	# a path that does not exist inside the chroot ("cannot make temporary directory").
	declare -a gm_args=(chroot "${MOUNT}" env TMPDIR=/tmp grub-mkstandalone
		--format="${grub_efi_format}"
		--output="/tmp/${efi_boot_name}"
		--modules="part_gpt part_msdos fat iso9660 normal linux echo all_video gfxterm gfxterm_background png test true loadenv search search_fs_uuid search_fs_file search_label configfile serial terminal ls cat halt reboot"
		"boot/grub/grub.cfg=/tmp/image-output-iso-grub.cfg")
	# embed the font + wallpaper (paths are inside the chroot) if present
	if [[ -f "${MOUNT}/usr/share/grub/unicode.pf2" && -f "${MOUNT}/usr/share/images/grub/wallpaper.png" ]]; then
		gm_args+=("boot/grub/fonts/unicode.pf2=/usr/share/grub/unicode.pf2" "boot/grub/armbian.png=/usr/share/images/grub/wallpaper.png")
	else
		display_alert "Extension: ${EXTENSION}: grub wallpaper/font missing" "booting to text menu" "info"
	fi
	# grub-mkstandalone runs the target's own binary inside the chroot; on a cross
	# build update_initramfs already undeployed the static qemu, so redeploy it for
	# this call (a no-op / cheap on a native build) and remove it again after.
	deploy_qemu_binary_to_chroot "${MOUNT}" "${EXTENSION}"
	run_host_command_logged "${gm_args[*]@Q}"
	undeploy_qemu_binary_from_chroot "${MOUNT}" "${EXTENSION}"
	[[ -f "${MOUNT}/tmp/${efi_boot_name}" ]] || exit_with_error "image-output-iso: grub-mkstandalone did not produce ${efi_boot_name}"

	# --- El Torito EFI boot image: a small FAT holding /EFI/BOOT/${efi_boot_name} ---
	declare efi_img="${stage_dir}/boot/grub/efiboot.img"
	declare efi_bytes efi_blocks
	efi_bytes="$(stat -c%s "${MOUNT}/tmp/${efi_boot_name}")"
	efi_blocks=$(((efi_bytes / 1024) + 2048)) # grub + FAT overhead + slack, in KiB
	cmd=(dd if=/dev/zero of="${efi_img}" bs=1024 count="${efi_blocks}" status=none) && run_host_command_logged "${cmd[*]@Q}"
	cmd=(mkfs.vfat -n EFIBOOT "${efi_img}") && run_host_command_logged "${cmd[*]@Q}"
	cmd=(mmd -i "${efi_img}" ::/EFI ::/EFI/BOOT) && run_host_command_logged "${cmd[*]@Q}"
	cmd=(mcopy -i "${efi_img}" "${MOUNT}/tmp/${efi_boot_name}" "::/EFI/BOOT/${efi_boot_name}") && run_host_command_logged "${cmd[*]@Q}"
	rm -f "${MOUNT}/tmp/${efi_boot_name}" "${MOUNT}/tmp/image-output-iso-grub.cfg"

	# --- assemble the hybrid ISO ---
	declare iso="${DESTIMG}/${version}.iso"
	display_alert "Assembling ISO" "${iso}" "info"
	cmd=(xorriso -as mkisofs
		-iso-level 3
		-volid "${ISO_VOLID:0:32}"
		-full-iso9660-filenames
		-e boot/grub/efiboot.img
		-no-emul-boot
		-isohybrid-gpt-basdat
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
