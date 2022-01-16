#############################################################################

#############################################################################

#############################################################################

# create_image
#
# finishes creation of image from cached rootfs
#
create_image_from_sdcard_rootfs() {
	# create DESTIMG, hooks might put stuff there early.
	mkdir -p $DESTIMG

	# stage: create file name
	local version="${VENDOR}_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}${DESKTOP_ENVIRONMENT:+_$DESKTOP_ENVIRONMENT}"
	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $BUILD_MINIMAL == yes ]] && version=${version}_minimal
	[[ $ROOTFS_TYPE == nfs ]] && version=${version}_nfsboot

	if [[ $ROOTFS_TYPE != nfs ]]; then
		display_alert "Copying files to" "/"
		rsync -aHWXh \
			--exclude="/boot/*" \
			--exclude="/dev/*" \
			--exclude="/proc/*" \
			--exclude="/run/*" \
			--exclude="/tmp/*" \
			--exclude="/sys/*" \
			--info=progress0,stats1 $SDCARD/ $MOUNT/ 2>&1
	else
		display_alert "Creating rootfs archive" "rootfs.tgz" "info"
		tar cp --xattrs --directory=$SDCARD/ --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . |
			pv -p -b -r -s "$(du -sb "$SDCARD"/ | cut -f1)" \
				-N "$(logging_echo_prefix_for_pv "create_rootfs_archive") rootfs.tgz" |
			gzip -c > "$DEST/images/${version}-rootfs.tgz"
	fi

	# stage: rsync /boot
	display_alert "Copying files to" "/boot"
	if [[ $(findmnt --target $MOUNT/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		rsync -rLtWh \
			--info=progress0,stats1 \
			--log-file="${DEST}"/${LOG_SUBPATH}/install.log $SDCARD/boot $MOUNT 2>&1 #@TODO: log to stdout, terse?
	else
		# ext4
		rsync -aHWXh \
			--info=progress0,stats1 \
			--log-file="${DEST}"/${LOG_SUBPATH}/install.log $SDCARD/boot $MOUNT 2>&1 #@TODO: log to stdout, terse?
	fi

	call_extension_method "pre_update_initramfs" "config_pre_update_initramfs" << 'PRE_UPDATE_INITRAMFS'
*allow config to hack into the initramfs create process*
Called after rsync has synced both `/root` and `/root` on the target, but before calling `update_initramfs`.
PRE_UPDATE_INITRAMFS

	# stage: create final initramfs
	[[ -n $KERNELSOURCE ]] && {
		update_initramfs $MOUNT
	}

	# DEBUG: print free space
	local freespace=$(LC_ALL=C df -h)
	# @TODO: this is very specific; we don't want it on screen ever?
	#echo $freespace >> $DEST/${LOG_SUBPATH}/debootstrap.log
	display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
	display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

	# stage: write u-boot, unless the deb is not there, which would happen if BOOTCONFIG=none
	[[ -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]] && write_uboot_to_loop_image $LOOP

	# fix wrong / permissions
	chmod 755 $MOUNT

	call_extension_method "pre_umount_final_image" "config_pre_umount_final_image" << 'PRE_UMOUNT_FINAL_IMAGE'
*allow config to hack into the image before the unmount*
Called before unmounting both `/root` and `/boot`.
PRE_UMOUNT_FINAL_IMAGE

	# unmount /boot/efi first, then /boot, rootfs third, image file last
	sync
	[[ $UEFISIZE != 0 ]] && umount -l "${MOUNT}${UEFI_MOUNT_POINT}"
	[[ $BOOTSIZE != 0 ]] && umount -l $MOUNT/boot
	[[ $ROOTFS_TYPE != nfs ]] && umount -l $MOUNT
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose $ROOT_MAPPER

	call_extension_method "post_umount_final_image" "config_post_umount_final_image" << 'POST_UMOUNT_FINAL_IMAGE'
*allow config to hack into the image after the unmount*
Called after unmounting both `/root` and `/boot`.
POST_UMOUNT_FINAL_IMAGE

	# to make sure its unmounted
	while grep -Eq '(${MOUNT}|${DESTIMG})' /proc/mounts; do
		display_alert "Wait for unmount" "${MOUNT}" "info"
		sleep 5
	done

	display_alert "Freeing loop device" "${LOOP}" "wrn"
	losetup -d "${LOOP}"
	# Don't delete $DESTIMG here, extensions might have put nice things there already.
	rm -rf --one-file-system $MOUNT

	mkdir -p $DESTIMG
	mv ${SDCARD}.raw $DESTIMG/${version}.img

	FINALDEST=$DEST/images
	[[ "${BUILD_ALL}" == yes ]] && MAKE_FOLDERS="yes"

	if [[ "${MAKE_FOLDERS}" == yes ]]; then
		if [[ "$RC" == yes ]]; then
			FINALDEST=$DEST/images/"${BOARD}"/RC
		elif [[ "$BETA" == yes ]]; then
			FINALDEST=$DEST/images/"${BOARD}"/nightly
		else
			FINALDEST=$DEST/images/"${BOARD}"/archive
		fi
		install -d ${FINALDEST}
	fi

	# custom post_build_image_modify hook to run before fingerprinting and compression
	[[ $(type -t post_build_image_modify) == function ]] && display_alert "Custom Hook Detected" "post_build_image_modify" "info" && post_build_image_modify "${DESTIMG}/${version}.img"

	if [[ -z $SEND_TO_SERVER ]]; then

		if [[ $COMPRESS_OUTPUTIMAGE == "" || $COMPRESS_OUTPUTIMAGE == no ]]; then
			COMPRESS_OUTPUTIMAGE="sha,gpg,img"
		elif [[ $COMPRESS_OUTPUTIMAGE == yes ]]; then
			COMPRESS_OUTPUTIMAGE="sha,gpg,7z"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *gz* ]]; then
			display_alert "Compressing" "${DESTIMG}/${version}.img.gz" "info"
			pigz -3 < $DESTIMG/${version}.img > $DESTIMG/${version}.img.gz
			compression_type=".gz"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *xz* ]]; then
			display_alert "Compressing" "${DESTIMG}/${version}.img.xz" "info"
			# compressing consumes a lot of memory we don't have. Waiting for previous packing job to finish helps to run a lot more builds in parallel
			available_cpu=$(grep -c 'processor' /proc/cpuinfo)
			#[[ ${BUILD_ALL} == yes ]] && available_cpu=$(( $available_cpu * 30 / 100 )) # lets use 20% of resources in case of build-all
			[[ ${available_cpu} -gt 16 ]] && available_cpu=16                                               # using more cpu cores for compressing is pointless
			available_mem=$(LC_ALL=c free | grep Mem | awk '{print $4/$2 * 100.0}' | awk '{print int($1)}') # in percentage
			# build optimisations when memory drops below 5%
			if [[ ${BUILD_ALL} == yes && (${available_mem} -lt 15 || $(ps -uax | grep "pixz" | wc -l) -gt 4) ]]; then
				while [[ $(ps -uax | grep "pixz" | wc -l) -gt 2 ]]; do
					echo -en "#"
					sleep 20
				done
			fi
			pixz -7 -p ${available_cpu} -f $(expr ${available_cpu} + 2) < $DESTIMG/${version}.img > ${DESTIMG}/${version}.img.xz
			compression_type=".xz"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *img* || $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
			#			mv $DESTIMG/${version}.img ${FINALDEST}/${version}.img || exit 1
			compression_type=""
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
			cd ${DESTIMG}
			display_alert "SHA256 calculating" "${version}.img${compression_type}" "info"
			sha256sum -b ${version}.img${compression_type} > ${version}.img${compression_type}.sha
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *gpg* ]]; then
			cd ${DESTIMG}
			if [[ -n $GPG_PASS ]]; then
				display_alert "GPG signing" "${version}.img${compression_type}" "info"
				if [[ -n $SUDO_USER ]]; then
					sudo chown -R ${SUDO_USER}:${SUDO_USER} "${DESTIMG}"/
					SUDO_PREFIX="sudo -H -u ${SUDO_USER}"
				else
					SUDO_PREFIX=""
				fi
				echo "${GPG_PASS}" | $SUDO_PREFIX bash -c "gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${DESTIMG}/${version}.img${compression_type}" || exit 1
			else
				display_alert "GPG signing skipped - no GPG_PASS" "${version}.img" "wrn"
			fi
		fi

		fingerprint_image "${DESTIMG}/${version}.img${compression_type}.txt" "${version}"

		if [[ $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
			display_alert "Compressing" "${DESTIMG}/${version}.7z" "info"
			7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on \
				${DESTIMG}/${version}.7z ${version}.key ${version}.img* > /dev/null 2>&1
			find ${DESTIMG}/ -type \
				f \( -name "${version}.img" -o -name "${version}.img.asc" -o -name "${version}.img.txt" -o -name "${version}.img.sha" \) -print0 |
				xargs -0 rm > /dev/null 2>&1
		fi

	fi
	display_alert "Done building" "${FINALDEST}/${version}.img" "info" # A bit predicting the future, since it's still in DESTIMG at this point.

	# Previously, post_build_image passed the .img path as an argument to the hook. Now its an ENV var.
	export FINAL_IMAGE_FILE="${DESTIMG}/${version}.img"
	call_extension_method "post_build_image" << 'POST_BUILD_IMAGE'
*custom post build hook*
Called after the final .img file is built, before it is (possibly) written to an SD writer.
- *NOTE*: this hook used to take an argument ($1) for the final image produced.
  - Now it is passed as an environment variable `${FINAL_IMAGE_FILE}`
It is the last possible chance to modify `$CARD_DEVICE`.
POST_BUILD_IMAGE

	# move artefacts from temporally directory to its final destination
	[[ -n $compression_type ]] && rm $DESTIMG/${version}.img
	rsync -a --no-owner --no-group --remove-source-files $DESTIMG/${version}* ${FINALDEST}
	rm -rf --one-file-system $DESTIMG

	# write image to SD card
	if [[ $(lsblk "$CARD_DEVICE" 2> /dev/null) && -f ${FINALDEST}/${version}.img ]]; then

		# make sha256sum if it does not exists. we need it for comparisson
		if [[ -f "${FINALDEST}/${version}".img.sha ]]; then
			local ifsha=$(cat ${FINALDEST}/${version}.img.sha | awk '{print $1}')
		else
			local ifsha=$(sha256sum -b "${FINALDEST}/${version}".img | awk '{print $1}')
		fi

		display_alert "Writing image" "$CARD_DEVICE ${readsha}" "info"

		# write to SD card
		pv -p -b -r -c -N "$(logging_echo_prefix_for_pv "write_device") dd" ${FINALDEST}/${version}.img | dd of=$CARD_DEVICE bs=1M iflag=fullblock oflag=direct status=none

		call_extension_method "post_write_sdcard" <<- 'POST_BUILD_IMAGE'
			*run after writing img to sdcard*
			After the image is written to `$CARD_DEVICE`, but before verifying it.
			You can still set SKIP_VERIFY=yes to skip verification.
		POST_BUILD_IMAGE

		if [[ "${SKIP_VERIFY}" != "yes" ]]; then
			# read and compare
			display_alert "Verifying. Please wait!"
			local ofsha=$(dd if=$CARD_DEVICE count=$(du -b ${FINALDEST}/${version}.img | cut -f1) status=none iflag=count_bytes oflag=direct | sha256sum | awk '{print $1}')
			if [[ $ifsha == $ofsha ]]; then
				display_alert "Writing verified" "${version}.img" "info"
			else
				display_alert "Writing failed" "${version}.img" "err"
			fi
		fi
	elif [[ $(systemd-detect-virt) == 'docker' && -n $CARD_DEVICE ]]; then
		# display warning when we want to write sd card under Docker
		display_alert "Can't write to $CARD_DEVICE" "Enable docker privileged mode in config-docker.conf" "wrn"
	fi

}
