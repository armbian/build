# Copyright (c) Authors: http://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

FORCEDRELEASE=$RELEASE

# when we want to build from certain start
#from=1
#stop=2

rm -rf /run/armbian
mkdir -p /run/armbian
RELEASE_LIST=("xenial" "jessie" "stretch" "bionic")
BRANCH_LIST=("default" "next" "dev")

pack_upload ()
{
	# pack into .7z and upload to server
	# stage: init
	display_alert "Signing and compressing" "Please wait!" "info"
	local version="Armbian_${REVISION}_${BOARD^}_${DISTRIBUTION}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}"
	local subdir="archive"
	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $BETA == yes ]] && local subdir=nightly
	local filename=$DESTIMG/${version}.7z

	# stage: generate sha256sum.sha
	cd $DESTIMG
	sha256sum -b ${version}.img > sha256sum.sha

	# stage: sign with PGP
	if [[ -n $GPG_PASS ]]; then
		echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${version}.img
	fi

	if [[ -n "${SEND_TO_SERVER}" ]]; then
	# create remote directory structure
	ssh ${SEND_TO_SERVER} "mkdir -p /var/www/dl.armbian.com/${BOARD}/{archive,nightly};";

	# pack and move file to server under new process
	nice -n 19 bash -c "\
	7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on $filename ${version}.img armbian.txt *.asc sha256sum.sha >/dev/null 2>&1 ; \
	find . -type f -not -name '*.7z' -print0 | xargs -0 rm -- ; \
	while ! rsync -arP $DESTIMG/. -e 'ssh -p 22' ${SEND_TO_SERVER}:/var/www/dl.armbian.com/${BOARD}/${subdir};do sleep 5;done; \
	rm -r $DESTIMG" &
	else
	# pack and move file to debs subdirectory
	nice -n 19 bash -c "\
	7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on $filename ${version}.img armbian.txt *.asc sha256sum.sha >/dev/null 2>&1 ; \
	find . -type f -not -name '*.7z' -print0 | xargs -0 rm -- ; \
	mv $filename $DEST/images ; rm -r $DESTIMG" &
	fi
}

build_main ()
{
	touch "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}.pid";
	source $SRC/lib/main.sh;
	[[ $KERNEL_ONLY != yes ]] && pack_upload
	rm "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${BUILD_DESKTOP}.pid"
}


make_targets ()
{
	if [[ -n $CLI_TARGET && -z $1 ]]; then
		# RELEASES : BRANCHES
		CLI_TARGET=($(tr ':' ' ' <<< "$CLI_TARGET"))
		build_settings_target=($(tr ',' ' ' <<< "${CLI_TARGET[0]}"))
		build_settings_branch=($(tr ',' ' ' <<< "${CLI_TARGET[1]}"))

		[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
		[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

		for release in ${build_settings_target[@]}; do
			for kernel in ${build_settings_branch[@]}; do
				buildlist+=("$BOARD $kernel $release no")
			done
		done
	fi

	if [[ -n $DESKTOP_TARGET && -z $1 ]]; then
		# RELEASES : BRANCHES
		DESKTOP_TARGET=($(tr ':' ' ' <<< "$DESKTOP_TARGET"))
		build_settings_target=($(tr ',' ' ' <<< "${DESKTOP_TARGET[0]}"))
		build_settings_branch=($(tr ',' ' ' <<< "${DESKTOP_TARGET[1]}"))

		[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
		[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

		for release in ${build_settings_target[@]}; do
			for kernel in ${build_settings_branch[@]}; do
				buildlist+=("$BOARD $kernel $release yes")
			done
		done
	fi

	if [[ -n $CLI_BETA_TARGET && -n $1 ]]; then
		# RELEASES : BRANCHES
		CLI_BETA_TARGET=($(tr ':' ' ' <<< "$CLI_BETA_TARGET"))
		build_settings_target=($(tr ',' ' ' <<< "${CLI_BETA_TARGET[0]}"))
		build_settings_branch=($(tr ',' ' ' <<< "${CLI_BETA_TARGET[1]}"))

		[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
		[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

		for release in ${build_settings_target[@]}; do
			for kernel in ${build_settings_branch[@]}; do
				buildlist+=("$BOARD $kernel $release no")
			done
		done
	fi

	if [[ -n $DESKTOP_BETA_TARGET && -n $1 ]]; then
		# RELEASES : BRANCHES
		DESKTOP_BETA_TARGET=($(tr ':' ' ' <<< "$DESKTOP_BETA_TARGET"))
		build_settings_target=($(tr ',' ' ' <<< "${DESKTOP_BETA_TARGET[0]}"))
		build_settings_branch=($(tr ',' ' ' <<< "${DESKTOP_BETA_TARGET[1]}"))

		[[ ${build_settings_target[0]} == "%" ]] && build_settings_target[0]="${RELEASE_LIST[@]}"
		[[ ${build_settings_branch[0]} == "%" ]] && build_settings_branch[0]="${BRANCH_LIST[@]}"

		for release in ${build_settings_target[@]}; do
			for kernel in ${build_settings_branch[@]}; do
				buildlist+=("$BOARD $kernel $release yes")
			done
		done
	fi
}

create_images_list()
{
	#
	# if parameter is true, than we build beta list
	#
	local naming="$SRC/config/boards/*.conf";
        if [[ "$EXPERT" == "yes" ]]; then naming=$naming" $SRC/config/boards/*.wip"; fi
	if [[ -n $REBUILD_IMAGES ]]; then naming=$naming" $SRC/config/boards/*.csc"; REBUILD_IMAGES=$REBUILD_IMAGES","; fi

	for board in $naming; do
		BOARD=$(basename $board | cut -d'.' -f1)
		local file="${SRC}/config/boards/${BOARD}"
		if [[ -f $file".conf" ]]; then source $file".conf"; fi
		if [[ -f $file".wip"  ]]; then source $file".wip"; fi
		if [[ -f $file".csc"  ]]; then source $file".csc"; fi
		if [[ -f $file".tvb"  ]]; then source $file".tvb"; fi

		# beta targets are the same as stable. To build the same set beta set as future stable.
		if [[ "$MERGETARGETS" == "yes" ]]; then
			CLI_BETA_TARGET=$CLI_TARGET
			DESKTOP_BETA_TARGET=$DESKTOP_TARGET
		fi

		if [[ -z $REBUILD_IMAGES ]]; then
			make_targets $1
		elif [[ $REBUILD_IMAGES == *"$BOARD,"* ]]; then
			make_targets $1
		fi
		unset CLI_TARGET CLI_BRANCH DESKTOP_TARGET DESKTOP_BRANCH KERNEL_TARGET CLI_BETA_TARGET DESKTOP_BETA_TARGET
	done
}

create_kernels_list()
{
	local naming="$SRC/config/boards/*.conf";
	if [[ "$EXPERT" == "yes" ]]; then naming=$naming" $SRC/config/boards/*.wip"; fi
	if [[ -n $REBUILD_IMAGES ]]; then naming=$naming" $SRC/config/boards/*.csc"; fi
	for board in $naming; do
		BOARD=$(basename $board | cut -d'.' -f1)
		local file="${SRC}/config/boards/${BOARD}"
		if [[ -f $file".conf" ]]; then source $file".conf"; fi
		if [[ -f $file".wip"  ]]; then source $file".wip"; fi
		if [[ -f $file".csc"  ]]; then source $file".csc"; fi
		if [[ -f $file".tvb"  ]]; then source $file".tvb"; fi

		if [[ -n $KERNEL_TARGET ]]; then
			for kernel in $(tr ',' ' ' <<< $KERNEL_TARGET); do
				buildlist+=("$BOARD $kernel")
			done
		fi
		unset KERNEL_TARGET
	done
}

buildlist=()


htmlicons ()
{
[[ ${1^^} == YES ]] && echo "<img width=16 src=https://assets-cdn.github.com/images/icons/emoji/unicode/2714.png>"
[[ ${1^^} == NO ]] && echo "<img width=16 src=https://assets-cdn.github.com/images/icons/emoji/unicode/274c.png>"
[[ ${1^^} == NT ]] && echo "<img width=16 src=https://assets-cdn.github.com/images/icons/emoji/unicode/2753.png>"
[[ ${1^^} == NA ]] && echo "<img width=16 src=https://assets-cdn.github.com/images/icons/emoji/unicode/26d4.png>"
}

if [[ $KERNEL_ONLY == yes ]]; then
	create_kernels_list
	printf "%-3s %-20s %-10s %-10s %-10s\n" \#   BOARD BRANCH
	REPORT="|#  |Board|Branch|U-boot|Kernel version| Network | Wireless | HDMI | USB| Armbianmonitor |"
	REPORTHTML="<table cellpadding=5 cellspacing=5 border=1><tr><td>#</td><td>Board</td><td>Branch</td><td>U-boot</td><td>Kernel</td><td>Network</td><td>WiFi</td><td>HDMI</td><td>USB</td><td>Logs</td></tr>"
	REPORT=$REPORT"\n|--|--|--|--:|--:|--:|--:|--:|--:|--:|"
else
	create_images_list $BETA
	printf "%-3s %-20s %-10s %-10s %-10s\n" \#   BOARD BRANCH RELEASE DESKTOP
fi

n=0
for line in "${buildlist[@]}"; do
	n=$[$n+1]
	printf "%-3s %-20s %-10s %-10s %-10s\n" $n $line
done
echo -e "\n${#buildlist[@]} total\n"

[[ $BUILD_ALL == demo ]] && exit 0

buildall_start=`date +%s`
n=0
for line in "${buildlist[@]}"; do
	unset LINUXFAMILY LINUXCONFIG KERNELDIR KERNELSOURCE KERNELBRANCH BOOTDIR BOOTSOURCE BOOTBRANCH ARCH UBOOT_USE_GCC KERNEL_USE_GCC DEFAULT_OVERLAYS \
		CPUMIN CPUMAX UBOOT_VER KERNEL_VER GOVERNOR BOOTSIZE BOOTFS_TYPE UBOOT_TOOLCHAIN KERNEL_TOOLCHAIN PACKAGE_LIST_EXCLUDE KERNEL_IMAGE_TYPE \
		write_uboot_platform family_tweaks family_tweaks_bsp setup_write_uboot_platform uboot_custom_postprocess atf_custom_postprocess family_tweaks_s \
		BOOTSCRIPT UBOOT_TARGET_MAP LOCALVERSION UBOOT_COMPILER KERNEL_COMPILER BOOTCONFIG BOOTCONFIG_VAR_NAME BOOTCONFIG_DEFAULT BOOTCONFIG_NEXT BOOTCONFIG_DEV \
		MODULES MODULES_NEXT MODULES_DEV INITRD_ARCH BOOTENV_FILE BOOTDELAY MODULES_BLACKLIST MODULES_BLACKLIST_NEXT ATF_TOOLCHAIN2 \
		MODULES_BLACKLIST_DEV MOUNT SDCARD BOOTPATCHDIR KERNELPATCHDIR buildtext RELEASE IMAGE_TYPE OVERLAY_PREFIX ASOUND_STATE \
		ATF_COMPILER ATF_USE_GCC ATFSOURCE ATFDIR ATFBRANCH ATFSOURCEDIR PACKAGE_LIST_RM NM_IGNORE_DEVICES DISPLAY_MANAGER family_tweaks_bsp_s \
		CRYPTROOT_ENABLE CRYPTROOT_PASSPHRASE CRYPTROOT_SSH_UNLOCK CRYPTROOT_SSH_UNLOCK_PORT CRYPTROOT_SSH_UNLOCK_KEY_NAME ROOT_MAPPER \
		NETWORK HDMI USB WIRELESS ARMBIANMONITOR DEFAULT_CONSOLE

	read BOARD BRANCH RELEASE BUILD_DESKTOP <<< $line
	n=$[$n+1]
	[[ -z $RELEASE ]] && RELEASE=$FORCEDRELEASE;
	if [[ $from -le $n ]]; then
		[[ -z $BUILD_DESKTOP ]] && BUILD_DESKTOP="no"
		jobs=$(ls /run/armbian | wc -l)
		if [[ $jobs -lt $MULTITHREAD ]]; then
			display_alert "Building in the back $n / ${#buildlist[@]}" "Board: $BOARD Kernel:$BRANCH${RELEASE:+ Release: $RELEASE}${BUILD_DESKTOP:+ Desktop: $BUILD_DESKTOP}" "ext"
			(build_main) &
			[[ $KERNEL_ONLY != yes ]] && sleep $(( ( RANDOM % 10 )  + 1 ))
		else
			display_alert "Building $buildtext $n / ${#buildlist[@]}" "Board: $BOARD Kernel:$BRANCH${RELEASE:+ Release: $RELEASE}${BUILD_DESKTOP:+ Desktop: $BUILD_DESKTOP}" "ext"
			build_main
			# include testing report if exist
			if [[ -f $SRC/cache/sources/testing-reports/${BOARD}-${BRANCH}.report ]]; then
				display_alert "Loading board report" "${BOARD}-${BRANCH}.report" "info"
				source $SRC/cache/sources/testing-reports/${BOARD}-${BRANCH}.report
			fi
			if [[ $KERNEL_ONLY == yes ]]; then
				REPORT=$REPORT"\n|$n|$BOARD|$BRANCH|$UBOOT_VER|$VER|$NETWORK|$WIRELESS|$HDMI|$USB|$ARMBIANMONITOR|"
				[[ -n $ARMBIANMONITOR ]] && ARMBIANMONITOR="<a href=$ARMBIANMONITOR target=_blank><img border=0 width=16 src=https://assets-cdn.github.com/images/icons/emoji/unicode/1f517.png></a>"
				REPORTHTML=$REPORTHTML"\n<tr><td>$n</td><td>$BOARD</td><td>$BRANCH</td><td>$UBOOT_VER</td><td align=right>$VER</td><td align=center>$(htmlicons "$NETWORK")</td><td align=center>$(htmlicons "$WIRELESS")</td><td align=center>$(htmlicons "$HDMI")</td><td align=center>$(htmlicons "$USB")</td><td align=center>$ARMBIANMONITOR</td></tr>"
			fi
		fi

	fi
	if [[ -n $stop && $n -ge $stop ]]; then break; fi
done

display_alert "Build report" "$DEST/debug/report.md" "info"
buildall_end=`date +%s`
buildall_runtime=$(((buildall_end - buildall_start) / 60))
display_alert "Runtime in total" "$buildall_runtime min" "info"

if [[ $KERNEL_ONLY == yes ]]; then

	echo -e $REPORT > $DEST/debug/report.md

	echo -e "\nSummary:\n\n|Armbian version | Built date| Built time in total\n|--|--:|--:|" >> $DEST/debug/report.md
	echo -e "|$REVISION|$(date -d "@$buildall_end")|$buildall_runtime|" >> $DEST/debug/report.md
	echo -e "$REPORTHTML<tr><td colspan=10>Current version: $REVISION - Refreshed at: $(date -d "@$buildall_end")</td></tr></table>" > $DEST/debug/report.html

fi
