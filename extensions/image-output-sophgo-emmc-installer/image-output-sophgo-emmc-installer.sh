#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Extension: image-output-sophgo-emmc-installer
#
# Turns the built .img into an eMMC installer card for the Milk-V Duo S.
#
# image-output-, because that is what this is: like image-output-oowow and the
# rest, it hooks post_build_image__900_ and rewrites the finished image into
# another format. Nothing else in here is unusual enough to deserve a category
# of its own.
#
# Opt-in, and the second-choice route. The ordinary image is already installable:
# /usr/sbin/sophgo-emmc-install writes it onto the eMMC from a running card
# system - two dd's, one to the user area and one to the hardware boot partition
# the image cannot reach. That is the path to prefer: what comes out is a system
# rather than a flasher, so it can be inspected, mounted, and written by any
# means that can reach a block device.
#
# This extension is for when there is no running system to do that from - a
# board whose card slot is occupied, in use, or whose only Linux is the one
# being installed. Enable it explicitly:
#
#   ./compile.sh build BOARD=milkv-duos-arm BRANCH=edge \
#       ENABLE_EXTENSIONS=image-output-sophgo-emmc-installer
#
# It also remains the one path exercised end to end on real hardware.
#
# With no Linux to hand, a blank eMMC has to be written by something that is not
# Linux, because nothing on the eMMC boots yet and the BootROM is what has to be
# satisfied first. That something is the vendor bootloader, running off a card.
#
# At first it appeared that the microSD slot and the eMMC are mutually exclusive, and that
# a running system never sees both. That is wrong, and worth recording because it
# shaped this whole extension. They are separate controllers - eMMC at 4300000,
# card at 4310000 - and they coexist.
#
# The claim came from the vendor bootloader, where it is true by construction:
# cv181x_asic_sd.dtsi does '/delete-node/ cv-emmc@4300000', so an SD build simply
# has no eMMC in its device tree. A software choice in their U-Boot, not board
# wiring, and it does not follow Linux.
#
# This discovery opened up the armbian-install style route - boot a card, write the
# eMMC from the running system, fip.bin into /dev/mmcblkXboot0 included. That is
# now packages/bsp/sophgo-sg200x/usr/sbin/sophgo-emmc-install, and it is the
# default route.
#
# The Sophgo U-Boot carries a 'cvi_update' command (cmd/cvi_update.c) which reads
# files out of the FAT root of the SD card and writes them to the raw eMMC. In
# U-Boot the card is mmc 1 and the eMMC is mmc 0; see the DTS comments in
# patch/u-boot/u-boot-sophgo-sg200x/cvitek-board-files/*/dts/*_emmc.dts for how
# that numbering arises.
#
# What makes it fire is not a file on the card but how the bootloader was built.
# cvitek.mk turns STORAGE_TYPE=emmc into -DCONFIG_EMMC_SUPPORT, and
# cv181x-asic.h then sets
#
#     CONFIG_BOOTCOMMAND "cvi_update || run distro_bootcmd || ..."
#
# where the SD build gets "run distro_bootcmd || run sdboot" instead. The FSBL,
# for its part, writes MAGIC_NUM_SD_DL to SRAM on *every* boot whose source was
# the SD card (setup_dl_flag() in plat/cv181x/platform.c), which is what
# cvi_update checks. So an -emmc bootloader plus any SD boot means: flash.
#
# The installer and the installed system therefore share one fip.bin - the same
# file cvi_update copies into the eMMC boot hardware partition.
#
# The payload is the entire Armbian disk image, MBR and all, written at offset 0.
# The installer this produces replaces ${version}.img, so it flows through the
# rest of the pipeline as an ordinary image: fingerprinted, optionally written to
# CARD_DEVICE, then xz'd and checksummed. It is not a bootable Armbian system and
# does not need to be - cvi_update runs inside U-Boot and never loads a kernel or
# mounts a rootfs. All the card has to carry is an MBR, a FAT partition, fip.bin
# and the payload, so the installer is the payload plus about a megabyte rather
# than a second copy of anything.
#
# Installation, for the record:
#
#   0. build it - the ordinary image, plus this extension by name:
#
#        ./compile.sh build BOARD=milkv-duos-arm BRANCH=edge \
#            ENABLE_EXTENSIONS=image-output-sophgo-emmc-installer
#
#      -> Armbian_..._Milkv-duos-arm_...-installer_minimal.img.xz.
#      "-installer" comes from here; the board name is the same one the plain
#      image uses.
#
#   1. write that image to an SD card, as any other Armbian image
#   2. insert the card and power on; watch the serial console
#   3. when it finishes, power off
#   4. remove the card - otherwise it flashes again on the next boot
#   5. power on
#
# The card is never booted into Linux, so nothing here is a system you can log
# into. If you want to reuse a card that already holds something else, the two
# files can equally be copied into the root of any FAT32 partition by hand -
# that is the vendor's own procedure, and cvi_update cannot tell the difference.
#

function extension_prepare_config__sophgo_emmc_installer() {
	# No storage type to check any more: every image carries both bootloaders,
	# and this extension takes the eMMC one out of /boot/fip-emmc.bin. It used to
	# demand SOPHGO_CVI_STORAGE=emmc, because with an SD bootloader in
	# /boot/fip.bin the card would boot, never run cvi_update, and sit there doing
	# nothing.

	# Distinguishes the flasher from the ordinary bootable image it carries.
	EXTRA_IMAGE_SUFFIXES+=("-installer")

	# COMPRESS_OUTPUTIMAGE is deliberately left alone. The installer is an
	# ordinary .img, so whatever the user asked for is right for it - and xz on
	# a payload whose free space is zeroes does better than any archive format
	# would.

	display_alert "${EXTENSION}" "eMMC installer image for ${BOARD}" "info"
}

function add_host_dependencies__sophgo_emmc_installer() {
	# mtools gives us mformat and mcopy, which build and populate the FAT
	# partition through a file offset - no loop device and no root. sfdisk is
	# util-linux, already required by the partitioning code.
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} mtools"
}

function post_build_image__900_sophgo_emmc_installer() {
	[[ -z "${version}" ]] && exit_with_error "version is not set"

	declare image_file="${DESTIMG}/${version}.img"
	[[ -f "${image_file}" ]] || exit_with_error "image not found" "${image_file}"

	declare mkcimg="${SRC}/extensions/image-output-sophgo-emmc-installer/mkcimg.py"
	[[ -f "${mkcimg}" ]] || exit_with_error "mkcimg.py not found" "${mkcimg}"

	# Work area for the two files that end up in the FAT root, plus the installer
	# while it is being built. In DESTIMG because the payload is image-sized and
	# /tmp is often tmpfs, but deliberately without the ${version} prefix:
	# output_images_compress_and_checksum and move_images_to_final_destination
	# both glob "${version}*", and anything left behind by a failed build would
	# land in their way.
	declare work="${DESTIMG}/emmc-installer-work"
	run_host_command_logged rm -rf "${work}"
	run_host_command_logged mkdir -p "${work}"

	# The bootloader this card boots is the *eMMC* one, and that is the whole
	# trick: only its CONFIG_BOOTCOMMAND runs cvi_update, and cvi_update only acts
	# when the FSBL says it booted from SD. A card carrying it is the one
	# combination that flashes an eMMC, which everywhere else in this family is
	# the hazard to avoid and here is the entire point.
	#
	# It comes out of the image's own FAT partition, where write_uboot_platform()
	# puts it as fip-emmc.bin beside the SD one, rather than being hunted down in
	# output/debs: several u-boot .debs for one BOARD/BRANCH can coexist there,
	# one per artifact hash, and picking among them by name risks shipping a
	# bootloader from an earlier configuration.
	declare boot_offset
	boot_offset="$(sfdisk -J "${image_file}" | python3 -c \
		'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][0]["start"] * 512)')"
	[[ "${boot_offset}" =~ ^[0-9]+$ ]] || exit_with_error "could not read partition 1 offset" "${image_file}"

	display_alert "${EXTENSION}" "extracting fip-emmc.bin from /boot (partition 1 at ${boot_offset})" "info"
	run_host_command_logged mcopy -n -i "${image_file}@@${boot_offset}" ::/fip-emmc.bin "${work}/fip.bin"
	[[ -s "${work}/fip.bin" ]] ||
		exit_with_error "no fip-emmc.bin in the image's boot partition" "${image_file}"

	# The payload is an ordinary image, so its /boot/fip.bin is the SD bootloader.
	# Once cvi_update has written it into the eMMC user area, boot0 will hold the
	# eMMC one this card booted from - and the two would disagree, leaving a board
	# that boots one bootloader and shows you another. Nothing reads /boot/fip.bin
	# on an eMMC, but sophgo-emmc-install keeps them in step on the manual route
	# and there is no reason for this one to be sloppier. cvi_update cannot be
	# hooked, so fix the payload before it is wrapped.
	display_alert "${EXTENSION}" "pointing the payload's /boot/fip.bin at the eMMC bootloader" "info"
	echo "emmc" > "${work}/sophgo-storage.txt"
	run_host_command_logged mcopy -o -i "${image_file}@@${boot_offset}" "${work}/fip.bin" ::/fip.bin
	run_host_command_logged mcopy -o -i "${image_file}@@${boot_offset}" \
		"${work}/sophgo-storage.txt" ::/sophgo-storage.txt

	# armbian.emmc: the name cvi_update looks for, from imgs.h in
	# patch/u-boot/u-boot-sophgo-sg200x/cvitek-board-files/*/include/emmc/.
	# Offset 0 - the image starts with its own MBR and owns the whole device.
	display_alert "${EXTENSION}" "wrapping $(( $(stat -c %s "${image_file}") / 1024 / 1024 ))MB image in CIMG" "info"
	run_host_command_logged python3 "${mkcimg}" \
		--offset 0 --label ROOTFS \
		"${image_file}" "${work}/armbian.emmc"

	# The target image is now carried inside the payload, so drop it before
	# building the installer rather than after - that keeps the peak at two
	# image-sized files instead of three.
	display_alert "${EXTENSION}" "target image is in the payload; discarding the original" "info"
	run_host_command_logged rm -f "${image_file}"

	# Size the carrier: payload + fip.bin + room for the FAT32 metadata (two
	# FATs, reserved sectors, root directory) and some slack, rounded up to a
	# MiB. Being generous costs nothing in the deliverable - the spare space is
	# zeroes and compresses to almost nothing - and being too tight would fail
	# only at the final mcopy, after minutes of work.
	declare -i payload_bytes fip_bytes part_bytes total_bytes
	payload_bytes="$(stat -c %s "${work}/armbian.emmc")"
	fip_bytes="$(stat -c %s "${work}/fip.bin")"
	part_bytes=$(( payload_bytes + fip_bytes + 32 * 1024 * 1024 ))
	part_bytes=$(( (part_bytes + 1048576 - 1) / 1048576 * 1048576 ))
	total_bytes=$(( 1048576 + part_bytes ))

	declare installer="${work}/installer.img"
	display_alert "${EXTENSION}" "building $(( total_bytes / 1024 / 1024 ))MB installer image" "info"

	# One FAT partition starting at 1MiB, type 0x0c and bootable, matching what
	# sophgo-sg200x_common.inc gives the SD images - the BootROM reads fip.bin
	# out of the first FAT partition and wants a plain FAT type there.
	#
	# mformat/mcopy address the partition through mtools' @@offset syntax, so
	# the whole thing is built without a loop device and without root. -T is the
	# partition size in sectors; sfdisk gives the partition the rest of the file,
	# so the two agree by construction.
	run_host_command_logged truncate -s "${total_bytes}" "${installer}"
	run_host_command_logged "printf 'label: dos\nstart=2048, type=c, bootable\n' | sfdisk -q ${installer}"
	run_host_command_logged mformat -i "${installer}@@1048576" -F -T "$(( part_bytes / 512 ))" ::
	run_host_command_logged mcopy -i "${installer}@@1048576" "${work}/fip.bin" ::/fip.bin
	run_host_command_logged mcopy -i "${installer}@@1048576" "${work}/armbian.emmc" ::/armbian.emmc

	# Listed in the log because it is the one cheap end-to-end check that the
	# card will look the way cvi_update expects.
	display_alert "${EXTENSION}" "FAT root of the installer:" "info"
	run_host_command_logged mdir -i "${installer}@@1048576" ::

	run_host_command_logged mv -f "${installer}" "${image_file}"
	run_host_command_logged rm -rf "${work}"

	[[ -f "${image_file}" ]] || exit_with_error "installer image was not produced" "${image_file}"

	display_alert "${EXTENSION}" \
		"$(basename "${image_file}") is $(( $(stat -c %s "${image_file}") / 1024 / 1024 ))MB" "info"
	display_alert "${EXTENSION}" \
		"write to a card, boot once, power off, remove the card" "info"

	return 0
}
