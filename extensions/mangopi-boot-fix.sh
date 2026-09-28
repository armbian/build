function pre_umount_final_image__mangopi_boot_fix() {
	local grub_prefix="${SRC}/cache/grub-2.06-2ubuntu16/install"
	run_host_command_logged bash "${SRC}/extensions/mangopi-boot-fix/build-grub.sh" "${SRC}" "${CTHREADS}"
	local root_uuid
	root_uuid=$(findmnt -n -o UUID -T "${MOUNT}")
	[[ -n ${root_uuid} ]] || root_uuid=$(grep "^rootdev=UUID=" "${MOUNT}/boot/armbianEnv.txt" | cut -d= -f3)
	[[ -n ${root_uuid} ]] || exit_with_error "Cannot find root filesystem UUID"
	local kernel_file initrd_file
	kernel_file=$(basename "$(readlink -f "${MOUNT}/boot/Image")")
	initrd_file="initrd.img-${kernel_file#vmlinuz-}"
	[[ -f ${MOUNT}/boot/${initrd_file} ]] || exit_with_error "initrd missing" "${initrd_file}"
	
	mkdir -p "${MOUNT}/boot/efi/EFI/BOOT" "${MOUNT}/boot/grub"
	cp -a "${grub_prefix}/lib/grub/riscv64-efi" "${MOUNT}/boot/grub/"
	cp -a "${MOUNT}/boot/dtb/" "${MOUNT}/boot/efi/dtb"
	
	cat > "${WORKDIR}/grub-early.cfg" <<- EARLYCFG
		search --no-floppy --fs-uuid --set=root ${root_uuid}
		set prefix=(\$root)/boot/grub
	EARLYCFG
	
	run_host_command_logged "${grub_prefix}/bin/grub-mkimage" \
		-O riscv64-efi -d "${grub_prefix}/lib/grub/riscv64-efi" \
		-p /boot/grub -c "${WORKDIR}/grub-early.cfg" \
		-o "${MOUNT}/boot/efi/EFI/BOOT/BOOTRISCV64.EFI" \
		part_msdos fat ext2 normal configfile search search_fs_uuid linux gzio
		
	cat > "${MOUNT}/boot/grub/grub.cfg" <<- CFG
		set default=0
		set timeout=2
		terminal_output console
		menuentry 'Armbian' {
		    insmod part_msdos
		    insmod ext2
		    insmod gzio
		    search --no-floppy --fs-uuid --set=root ${root_uuid}
		    echo 'Loading Linux ${kernel_file#vmlinuz-} ...'
		    linux /boot/${kernel_file} root=UUID=${root_uuid} ro ${SRC_CMDLINE}
		    initrd /boot/${initrd_file}
		    devicetree /boot/dtb/\${BOOT_FDT_FILE}
		}
	CFG
}
