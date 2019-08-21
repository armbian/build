#!/bin/bash
#
# Copyright (c) Authors: http://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# build_main
# array_contains
# build_all
# pack_upload




if [[ $BETA == "yes" ]];  then STABILITY="beta";	else STABILITY="stable"; fi
if [[ -z $KERNEL_ONLY ]]; then KERNEL_ONLY="yes"; fi
KERNEL_CONFIGURE="no"
CLEAN_LEVEL="make,oldcache"

rm -f /run/armbian/*.pid
mkdir -p /run/armbian




pack_upload ()
{

	# pack into .7z and upload to server

	display_alert "Signing" "Please wait!" "info"
	local version="Armbian_${REVISION}_${BOARD^}_${DISTRIBUTION}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}"
	local subdir="archive"

	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $BUILD_MINIMAL == yes ]] && version=${version}_minimal

	[[ $BETA == yes ]] && local subdir=nightly
	local filename=$DESTIMG/${version}.7z

	# stage: generate sha256sum.sha
	cd "${DESTIMG}" || exit
	sha256sum -b "${version}.img" > ${version}.img.sha

	# stage: sign with PGP
	if [[ -n $GPG_PASS ]]; then
		echo "${GPG_PASS}" | gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes \
		"${version}.img"
	fi

	if [[ -n "${SEND_TO_SERVER}" ]]; then
		display_alert "Compressing and uploading" "Please wait!" "info"
		# pack and move file to server under new process
		nice -n 19 bash -c "7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on $filename ${version}.img ${version}.img.txt *.asc ${version}.img.sha >/dev/null 2>&1 ; find . -type f -not -name '*.7z' -print0 | xargs -0 rm -- ; while ! rsync -arP $DESTIMG/. -e 'ssh -p 22' ${SEND_TO_SERVER}:/var/www/dl.armbian.com/${BOARD}/${subdir}; do sleep 5; done; rm -r $DESTIMG; rm /run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}_${BUILD_MINIMAL}.pid" &
	else
		display_alert "Compressing" "Please wait!" "info"
		# pack and move file to debs subdirectory
		nice -n 19 bash -c "7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on $filename ${version}.img ${version}.img.txt *.asc ${version}.img.sha >/dev/null 2>&1 ; find . -type f -not -name '*.7z' -print0 | xargs -0 rm -- ; mv $filename $DEST/images ; rm -r $DESTIMG; rm /run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}_${BUILD_MINIMAL}.pid" &
	fi

}




build_main ()
{

	touch "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}_${BUILD_MINIMAL}.pid";
	if [[ $KERNEL_ONLY != yes ]]; then
		source "${SRC}"/lib/main.sh
		pack_upload
	else
		source "${SRC}"/lib/main.sh
		rm "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}_${BUILD_MINIMAL}.pid"
	fi

}




array_contains () {

    local array="$1[@]"
    local seeking=$2
    local in=1
    for element in "${!array}"; do
        if [[ $element == $seeking ]]; then
            in=0
            break
        fi
    done
    return $in

}




function build_all()
{

	buildall_start=$(date +%s)
	n=0
	ARRAY=()
	buildlist="cat "

	# building selected ones
	if [[ -n ${REBUILD_IMAGES} ]]; then
		buildlist="grep -w '"
		filter="'"
		for build in $(tr ',' ' ' <<< $REBUILD_IMAGES); do
				buildlist=$buildlist"$build\|"
				filter=$filter"$build\|"
		done
		buildlist=${buildlist::-2}"'"
		filter=${filter::-2}"'"
	fi

	# find unique boards - we will build debs for all variants
	sorted_unique_ids=($(echo "${ids[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
	unique_boards=$(eval $buildlist ${SRC}/config/targets.conf | sed '/^#/ d' | awk '{print $1}')
	unique_boards=$(echo "${unique_boards[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')

	while read line; do

		[[ "$line" =~ ^#.*$ ]] && continue
		[[ -n ${REBUILD_IMAGES} ]] && [[ -z $(echo $line | eval grep -w $filter) ]] && continue

		unset LINUXFAMILY LINUXCONFIG KERNELDIR KERNELSOURCE KERNELBRANCH BOOTDIR BOOTSOURCE BOOTBRANCH ARCH \
		UBOOT_USE_GCC KERNEL_USE_GCC DEFAULT_OVERLAYS CPUMIN CPUMAX UBOOT_VER KERNEL_VER GOVERNOR BOOTSIZE \
		BOOTFS_TYPE UBOOT_TOOLCHAIN KERNEL_TOOLCHAIN DEBOOTSTRAP_LIST PACKAGE_LIST_EXCLUDE KERNEL_IMAGE_TYPE \
		write_uboot_platform family_tweaks family_tweaks_bsp setup_write_uboot_platform uboot_custom_postprocess \
		atf_custom_postprocess family_tweaks_s BOOTSCRIPT UBOOT_TARGET_MAP LOCALVERSION UBOOT_COMPILER \
		KERNEL_COMPILER BOOTCONFIG BOOTCONFIG_VAR_NAME BOOTCONFIG_DEFAULT BOOTCONFIG_NEXT BOOTCONFIG_DEV MODULES \
		MODULES_NEXT MODULES_DEV INITRD_ARCH BOOTENV_FILE BOOTDELAY MODULES_BLACKLIST MODULES_BLACKLIST_NEXT \
		ATF_TOOLCHAIN2 MODULES_BLACKLIST_DEV MOUNT SDCARD BOOTPATCHDIR KERNELPATCHDIR RELEASE \
		IMAGE_TYPE OVERLAY_PREFIX ASOUND_STATE ATF_COMPILER ATF_USE_GCC ATFSOURCE ATFDIR ATFBRANCH ATFSOURCEDIR \
		PACKAGE_LIST_RM NM_IGNORE_DEVICES DISPLAY_MANAGER family_tweaks_bsp_s CRYPTROOT_ENABLE CRYPTROOT_PASSPHRASE \
		CRYPTROOT_SSH_UNLOCK CRYPTROOT_SSH_UNLOCK_PORT CRYPTROOT_SSH_UNLOCK_KEY_NAME ROOT_MAPPER NETWORK HDMI \
		USB WIRELESS ARMBIANMONITOR DEFAULT_CONSOLE FORCE_BOOTSCRIPT_UPDATE SERIALCON UBOOT_TOOLCHAIN2 toolchain2 \
		BUILD_REPOSITORY_URL BUILD_REPOSITORY_COMMIT DESKTOP_AUTOLOGIN BUILD_MINIMAL BUILD_TARGET BUILD_STABILITY \
		HOST BUILD_IMAGE BOARDFAMILY DEB_STORAGE REPO_STORAGE REPO_CONFIG REPOSITORY_UPDATE PACKAGE_LIST_RELEASE

		read -r BOARD BRANCH RELEASE BUILD_TARGET BUILD_STABILITY BUILD_IMAGE <<< "${line}"

		source ${SRC}"/config/boards/${BOARD}".eos 2> /dev/null
		source ${SRC}"/config/boards/${BOARD}".tvb 2> /dev/null
		source ${SRC}"/config/boards/${BOARD}".csc 2> /dev/null
		source ${SRC}"/config/boards/${BOARD}".wip 2> /dev/null
		source ${SRC}"/config/boards/${BOARD}".conf 2> /dev/null

		[[ ${BOARDFAMILY} == sun*i && $BRANCH == next ]] && BOARDFAMILY=sunxi

		if [[ $KERNEL_ONLY == yes ]]; then
			array_contains ARRAY "${BOARDFAMILY}${BRANCH}"
			continue
		elif [[ $BUILD_IMAGE == no ]] ; then
			continue
		fi

		ARRAY+=("${BOARDFAMILY}${BRANCH}")

		BUILD_DESKTOP="no"
		BUILD_MINIMAL="no"

		[[ ${BUILD_TARGET} == "desktop" ]] && BUILD_DESKTOP="yes"
		[[ ${BUILD_TARGET} == "minimal" ]] && BUILD_MINIMAL="yes"

		# create beta or stable
		if [[ "${BUILD_STABILITY}" == "${STABILITY}" ]]; then
			((n+=1))

			if [[ $1 != "dryrun" ]]; then

				if [[ $(find /run/armbian/*.pid 2&> /dev/null | wc -l) -lt ${MULTITHREAD} ]]; then

					display_alert "Building in the back ${n}."
					(build_main) &
					sleep $(( ( RANDOM % 10 )  + 1 ))

				else

					display_alert "Building ${n}."
					build_main

				fi

			else

		echo "${n}.	$BOARD			$BRANCH		$RELEASE\
		$BUILD_DESKTOP		$BUILD_MINIMAL		$BUILD_IMAGE"
				if [[ -n "${SEND_TO_SERVER}" ]]; then
			                # create remote directory structure
					ssh "${SEND_TO_SERVER}" "mkdir -p /var/www/dl.armbian.com/${BOARD}/{archive,nightly}"
				fi
			fi
		fi

	done < ${SRC}/config/targets.conf

}

# display what will be build
echo ""
display_alert "Building all targets" "$STABILITY $(if [[ $KERNEL_ONLY == "yes" ]] ; then echo "kernels"; \
else echo "images"; fi)" "info"
echo ""
echo "	board				branch		release		desktop		minimal		image"
build_all "dryrun"

if [[ $BUILD_ALL != demo ]] ; then

	echo ""
	# build
	build_all

fi

# wait until they are not finshed
sleep 10
while :
do
        if [[ $(df | grep .tmp | wc -l) -lt 1 ]]; then
                break
        fi
        sleep 10
done

display_alert "Compressing and uploading" "7z" "info"
# wait until builds in the background are finished
sleep 10
while :
do
        if [[ -z $(ps -uax | grep 7z | grep Armbian) ]]; then
                break
        fi
        sleep 10
done

buildall_end=$(date +%s)
buildall_runtime=$(((buildall_end - buildall_start) / 60))
display_alert "Runtime in total" "$buildall_runtime min" "info"

if [[ $BUILD_ALL != demo ]] ; then
	# recreate link to images
	ssh igor@dl.armbian.com "/home/igor/recreate.sh"
	ssh igor@dl.armbian.com "/home/igor/tools.sh"
fi
