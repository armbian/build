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
# pack_upload
# build_main
# array_contains
# build_all




if [[ $BETA == "yes" ]];  then STABILITY="beta";	else STABILITY="stable"; fi
if [[ -z $KERNEL_ONLY ]]; then KERNEL_ONLY="yes"; fi
if [[ -z $MULTITHREAD ]]; then MULTITHREAD=0; fi
if [[ -z $START ]]; then START=0; fi
if [[ -z $KERNEL_CONFIGURE ]]; then KERNEL_CONFIGURE="no"; fi
if [[ -z $CLEAN_LEVEL ]]; then CLEAN_LEVEL="make,oldcache"; fi

# cleanup
rm -f /run/armbian/*.pid
mkdir -p /run/armbian

# read user defined targets if exits
if [[ -f $USERPATCHES_PATH/targets.conf ]]; then

	display_alert "Adding user provided targets configuration"
	TARGETS="${USERPATCHES_PATH}/targets.conf"

else

	TARGETS="${SRC}/config/targets.conf"

fi

pack_upload ()
{

	# pack and upload to server or just pack

	display_alert "Signing" "Please wait!" "info"
	local version="Armbian_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}"
	local subdir="archive"

	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $BUILD_MINIMAL == yes ]] && version=${version}_minimal
	[[ $BETA == yes ]] && local subdir=nightly

	cd "${DESTIMG}" || exit

	if [[ $COMPRESS_OUTPUTIMAGE == yes ]]; then
		COMPRESS_OUTPUTIMAGE="sha,gpg,7z"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
		display_alert "SHA256 calculating" "${version}.img" "info"
		sha256sum -b ${version}.img > ${version}.img.sha
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *gpg* ]]; then
		if [[ -n $GPG_PASS ]]; then
			display_alert "GPG signing" "${version}.img" "info"
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${version}.img || exit 1
		else
			display_alert "GPG signing skipped - no GPG_PASS" "${version}.img" "wrn"
		fi
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
		display_alert "Compressing" "${version}.7z" "info"
		7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on ${version}.7z ${version}.img* >/dev/null 2>&1
		find . -type f -not -name '*.7z' -print0 | xargs -0 rm --
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *gz* ]]; then
		display_alert "Compressing" "$DEST/images/${version}.img.gz" "info"
		pigz < $DESTIMG/${version}.img > ${DESTIMG}/${version}.img.gz
	fi

	if [[ -n "${SEND_TO_SERVER}" ]]; then
		ssh "${SEND_TO_SERVER}" "mkdir -p ${SEND_TO_LOCATION}${BOARD}/{archive,nightly}" &
		display_alert "Uploading" "Please wait!" "info"
		nice -n 19 bash -c "while ! rsync -arP $DESTIMG/. -e 'ssh -p 22' ${SEND_TO_SERVER}:${SEND_TO_LOCATION}${BOARD}/${subdir}; \
		do sleep 5; done; rm -r $DESTIMG" &

	else

		mv $DESTIMG/* $DEST/images

	fi

}




build_main ()
{

	source "$USERPATCHES_PATH"/lib.config
	# build images which we do pack or kernel
	local upload_image="Armbian_$(cat ${SRC}/VERSION)_${BOARD^}_${RELEASE}_${BRANCH}_*${VER/-$LINUXFAMILY/}"
	local upload_subdir="archive"

	[[ $BUILD_DESKTOP == yes ]] && upload_image=${upload_image}_desktop
	[[ $BUILD_MINIMAL == yes ]] && upload_image=${upload_image}_minimal
	[[ $BETA == yes ]] && local upload_subdir=nightly

	touch "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}_${BUILD_MINIMAL}.pid";

	if [[ $KERNEL_ONLY != yes ]]; then
		#if ssh ${SEND_TO_SERVER} stat ${SEND_TO_LOCATION}${BOARD}/${upload_subdir}/${upload_image}* \> /dev/null 2\>\&1; then
		#	echo "$n exists $upload_image"
		#else
			source "${SRC}"/lib/main.sh
			[[ $BSP_BUILD != yes ]] && pack_upload
		#fi

	else

		source "${SRC}"/lib/main.sh

	fi

	rm "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}_${BUILD_MINIMAL}.pid"
}




array_contains ()
{

	# utility snippet

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

	# main routine

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

	# TO DO!
	# find unique boards - we will build debs for all variants
	sorted_unique_ids=($(echo "${ids[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
	unique_boards=$(eval $buildlist ${SRC}/config/targets.conf | sed '/^#/ d' | awk '{print $1}')
	unique_boards=$(echo "${unique_boards[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')

	while read line; do

		[[ "$line" =~ ^#.*$ ]] && continue
		[[ -n ${REBUILD_IMAGES} ]] && [[ -z $(echo $line | eval grep -w $filter) ]] && continue
		#[[ $n -lt $START ]] && ((n+=1)) && continue
		unset LINUXFAMILY LINUXCONFIG KERNELDIR KERNELSOURCE KERNELBRANCH BOOTDIR BOOTSOURCE BOOTBRANCH ARCH \
		UBOOT_USE_GCC KERNEL_USE_GCC DEFAULT_OVERLAYS CPUMIN CPUMAX UBOOT_VER KERNEL_VER GOVERNOR BOOTSIZE \
		BOOTFS_TYPE UBOOT_TOOLCHAIN KERNEL_TOOLCHAIN DEBOOTSTRAP_LIST PACKAGE_LIST_EXCLUDE KERNEL_IMAGE_TYPE \
		write_uboot_platform family_tweaks family_tweaks_bsp setup_write_uboot_platform uboot_custom_postprocess \
		atf_custom_postprocess family_tweaks_s BOOTSCRIPT UBOOT_TARGET_MAP LOCALVERSION UBOOT_COMPILER \
		KERNEL_COMPILER BOOTCONFIG BOOTCONFIG_VAR_NAME BOOTCONFIG_DEFAULT BOOTCONFIG_NEXT BOOTCONFIG_DEV MODULES \
		MODULES_NEXT MODULES_DEV INITRD_ARCH BOOTENV_FILE BOOTDELAY MODULES_BLACKLIST MODULES_BLACKLIST_NEXT \
		ATF_TOOLCHAIN2 MODULES_BLACKLIST_DEV MOUNT SDCARD BOOTPATCHDIR KERNELPATCHDIR RELEASE FULL_DESKTOP \
		IMAGE_TYPE OVERLAY_PREFIX ASOUND_STATE ATF_COMPILER ATF_USE_GCC ATFSOURCE ATFDIR ATFBRANCH ATFSOURCEDIR \
		PACKAGE_LIST_RM NM_IGNORE_DEVICES DISPLAY_MANAGER family_tweaks_bsp_s CRYPTROOT_ENABLE CRYPTROOT_PASSPHRASE \
		CRYPTROOT_SSH_UNLOCK CRYPTROOT_SSH_UNLOCK_PORT CRYPTROOT_SSH_UNLOCK_KEY_NAME ROOT_MAPPER NETWORK HDMI \
		USB WIRELESS ARMBIANMONITOR DEFAULT_CONSOLE FORCE_BOOTSCRIPT_UPDATE SERIALCON UBOOT_TOOLCHAIN2 toolchain2 \
		BUILD_REPOSITORY_URL BUILD_REPOSITORY_COMMIT DESKTOP_AUTOLOGIN BUILD_MINIMAL BUILD_TARGET BUILD_STABILITY \
		HOST BUILD_IMAGE BOARDFAMILY DEB_STORAGE REPO_STORAGE REPO_CONFIG REPOSITORY_UPDATE PACKAGE_LIST_RELEASE \
		LOCAL_MIRROR COMPILE_ATF PACKAGE_LIST_DESKTOP_BOARD PACKAGE_LIST_DESKTOP_FAMILY ATF_COMPILE ATFPATCHDIR

		read -r BOARD BRANCH RELEASE BUILD_TARGET BUILD_STABILITY BUILD_IMAGE <<< "${line}"

		# read all possible configurations
		source ${SRC}"/config/boards/${BOARD}".eos 2> /dev/null
		source ${SRC}"/config/boards/${BOARD}".tvb 2> /dev/null
		source ${SRC}"/config/boards/${BOARD}".csc 2> /dev/null
		source ${SRC}"/config/boards/${BOARD}".wip 2> /dev/null
		source ${SRC}"/config/boards/${BOARD}".conf 2> /dev/null

		# exceptions handling
		[[ ${BOARDFAMILY} == sun*i* && $BRANCH != default ]] && BOARDFAMILY=sunxi

		# small optimisation. we only (try to) build needed kernels
		if [[ $KERNEL_ONLY == yes ]]; then

			array_contains ARRAY "${BOARDFAMILY}${BRANCH}${BUILD_STABILITY}" && continue

		elif [[ $BUILD_IMAGE == no ]] ; then

			continue

		fi
		ARRAY+=("${BOARDFAMILY}${BRANCH}${BUILD_STABILITY}")

		BUILD_DESKTOP="no"
		BUILD_MINIMAL="no"

		[[ ${BUILD_TARGET} == "desktop" ]] && BUILD_DESKTOP="yes"
		[[ ${BUILD_TARGET} == "minimal" ]] && BUILD_MINIMAL="yes"

		# create beta or stable
		if [[ "${BUILD_STABILITY}" == "${STABILITY}" ]]; then

			((n+=1))

			if [[ $1 != "dryrun" ]] && [[ $n -ge $START ]]; then

							while :
							do
							if [[ $(find /run/armbian/*.pid 2>/dev/null | wc -l) -le ${MULTITHREAD} ]]; then
								break
							fi
							sleep 5
							done

					display_alert "Building ${n}."
					if [[ "${BSP_BUILD}" == yes && ${ALLTARGETS} == "yes" ]]; then
                                                RELTARGETS=(xenial stretch buster bionic disco eoan)
                                                for RELEASE in "${RELTARGETS[@]}"
						do
							display_alert "BSP for ${RELEASE}."
							sleep .5
							(build_main) &
						done
					else
							(build_main) &
							sleep $(( ( RANDOM % 10 )  + 10 ))
					fi


			else

				# In dryrun it only prints out what will be build
				printf "%s\t%-32s\t%-8s\t%-14s\t%-6s\t%-6s\t%-6s\n" "${n}." \
				"$BOARD (${BOARDFAMILY})" "${BRANCH}" "${RELEASE}" "${BUILD_DESKTOP}" "${BUILD_MINIMAL}"

			fi

		fi

	done < ${TARGETS}

}

# display what will be build
echo ""
display_alert "Building all targets" "$STABILITY $(if [[ $KERNEL_ONLY == "yes" ]] ; then echo "kernels"; \
else echo "images"; fi)" "info"

printf "\n%s\t%-32s\t%-8s\t%-14s\t%-6s\t%-6s\t%-6s\n\n" "" "board" "branch" "release" "XFCE" "minimal"

# display what we will build
build_all "dryrun"

if [[ $BUILD_ALL != demo ]] ; then

	echo ""
	# build
	build_all

fi

# wait until they are not finshed
sleep 5
while :
do
		if [[ $(df | grep .tmp | wc -l) -lt 1 ]]; then
			break
		fi
	sleep 5
done

while :
do
		if [[ -z $(ps -uax | grep 7z | grep Armbian) ]]; then
			break
		fi
	sleep 5
done

buildall_end=$(date +%s)
buildall_runtime=$(((buildall_end - buildall_start) / 60))
display_alert "Runtime in total" "$buildall_runtime min" "info"
