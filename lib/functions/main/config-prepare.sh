#!/usr/bin/env bash
DISTRIBUTIONS_DESC_DIR="config/distributions"

function prepare_and_config_main_build_single() {
	# default umask for root is 022 so parent directories won't be group writeable without this
	# this is used instead of making the chmod in prepare_host() recursive
	umask 002

	# destination
	if [ -d "$CONFIG_PATH/output" ]; then
		DEST="${CONFIG_PATH}"/output
	else
		DEST="${SRC}"/output
	fi

	interactive_config_prepare_terminal

	# Warnings mitigation
	[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"      # set to english if not set
	[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8" # set console to UTF-8 if not set

	interactive_config_prepare_terminal

	# set log path
	LOG_SUBPATH=${LOG_SUBPATH:=debug}

	# compress and remove old logs
	mkdir -p "${DEST}"/${LOG_SUBPATH}
	(cd "${DEST}"/${LOG_SUBPATH} && tar -czf logs-"$(< timestamp)".tgz ./*.log) > /dev/null 2>&1
	rm -f "${DEST}"/${LOG_SUBPATH}/*.log > /dev/null 2>&1
	date +"%d_%m_%Y-%H_%M_%S" > "${DEST}"/${LOG_SUBPATH}/timestamp

	# delete compressed logs older than 7 days
	(cd "${DEST}"/${LOG_SUBPATH} && find . -name '*.tgz' -mtime +7 -delete) > /dev/null

	if [[ $PROGRESS_DISPLAY == none ]]; then

		OUTPUT_VERYSILENT=yes

	elif [[ $PROGRESS_DISPLAY == dialog ]]; then

		OUTPUT_DIALOG=yes

	fi

	if [[ $PROGRESS_LOG_TO_FILE != yes ]]; then unset PROGRESS_LOG_TO_FILE; fi

	SHOW_WARNING=yes

	if [[ $USE_CCACHE != no ]]; then

		CCACHE=ccache
		export PATH="/usr/lib/ccache:$PATH"
		# private ccache directory to avoid permission issues when using build script with "sudo"
		# see https://ccache.samba.org/manual.html#_sharing_a_cache for alternative solution
		[[ $PRIVATE_CCACHE == yes ]] && export CCACHE_DIR=$SRC/cache/ccache
		# Check if /tmp is mounted as tmpfs make a temporary ccache folder there for faster operation.
		if [ "$(findmnt --noheadings --output FSTYPE --target "/tmp" --uniq)" == "tmpfs" ]; then
			export CCACHE_TEMPDIR="/tmp/ccache-tmp"
		fi

	else

		CCACHE=""

	fi

	# if KERNEL_ONLY, KERNEL_CONFIGURE, BOARD, BRANCH or RELEASE are not set, display selection menu

	backward_compatibility_build_only

	interactive_config_ask_kernel

	interactive_config_ask_board_list

	if [[ -f $SRC/config/boards/${BOARD}.conf ]]; then
		BOARD_TYPE='conf'
	elif [[ -f $SRC/config/boards/${BOARD}.csc ]]; then
		BOARD_TYPE='csc'
	elif [[ -f $SRC/config/boards/${BOARD}.wip ]]; then
		BOARD_TYPE='wip'
	elif [[ -f $SRC/config/boards/${BOARD}.eos ]]; then
		BOARD_TYPE='eos'
	elif [[ -f $SRC/config/boards/${BOARD}.tvb ]]; then
		BOARD_TYPE='tvb'
	fi

	# shellcheck source=/dev/null
	source "${SRC}/config/boards/${BOARD}.${BOARD_TYPE}"
	LINUXFAMILY="${BOARDFAMILY}"

	[[ -z $KERNEL_TARGET ]] && exit_with_error "Board configuration does not define valid kernel config"

	interactive_config_ask_branch

	build_task_is_enabled "bootstrap" && {

		interactive_config_ask_release

		interactive_config_ask_desktop_build

		interactive_config_ask_standard_or_minimal
	}

	#prevent conflicting setup
	if [[ $BUILD_DESKTOP == "yes" ]]; then
		BUILD_MINIMAL=no
		SELECTED_CONFIGURATION="desktop"
	elif [[ $BUILD_MINIMAL != "yes" || -z "${BUILD_MINIMAL}" ]]; then
		BUILD_MINIMAL=no # Just in case BUILD_MINIMAL is not defined
		BUILD_DESKTOP=no
		SELECTED_CONFIGURATION="cli_standard"
	elif [[ $BUILD_MINIMAL == "yes" ]]; then
		BUILD_DESKTOP=no
		SELECTED_CONFIGURATION="cli_minimal"
	fi

	[[ ${KERNEL_CONFIGURE} == prebuilt ]] && [[ -z ${REPOSITORY_INSTALL} ]] &&
		REPOSITORY_INSTALL="u-boot,kernel,bsp,armbian-zsh,armbian-config,armbian-bsp-cli,armbian-firmware${BUILD_DESKTOP:+,armbian-desktop,armbian-bsp-desktop}"

	do_main_configuration

	# optimize build time with 100% CPU usage
	CPUS=$(grep -c 'processor' /proc/cpuinfo)
	if [[ $USEALLCORES != no ]]; then

		CTHREADS="-j$((CPUS + CPUS / 2))"

	else

		CTHREADS="-j1"

	fi

	call_extension_method "post_determine_cthreads" "config_post_determine_cthreads" << 'POST_DETERMINE_CTHREADS'
*give config a chance modify CTHREADS programatically. A build server may work better with hyperthreads-1 for example.*
Called early, before any compilation work starts.
POST_DETERMINE_CTHREADS

	if [[ "$BETA" == "yes" ]]; then
		IMAGE_TYPE=nightly
	elif [ "$BETA" == "no" ] || [ "$RC" == "yes" ]; then
		IMAGE_TYPE=stable
	else
		IMAGE_TYPE=user-built
	fi

	BOOTSOURCEDIR="${BOOTDIR}/$(branch2dir "${BOOTBRANCH}")"
	LINUXSOURCEDIR="${KERNELDIR}/$(branch2dir "${KERNELBRANCH}")"
	[[ -n $ATFSOURCE ]] && ATFSOURCEDIR="${ATFDIR}/$(branch2dir "${ATFBRANCH}")"

	BSP_CLI_PACKAGE_NAME="armbian-bsp-cli-${BOARD}${EXTRA_BSP_NAME}"
	BSP_CLI_PACKAGE_FULLNAME="${BSP_CLI_PACKAGE_NAME}_${REVISION}_${ARCH}"
	BSP_DESKTOP_PACKAGE_NAME="armbian-bsp-desktop-${BOARD}${EXTRA_BSP_NAME}"
	BSP_DESKTOP_PACKAGE_FULLNAME="${BSP_DESKTOP_PACKAGE_NAME}_${REVISION}_${ARCH}"

	CHOSEN_UBOOT=linux-u-boot-${BRANCH}-${BOARD}
	CHOSEN_KERNEL=linux-image-${BRANCH}-${LINUXFAMILY}
	CHOSEN_ROOTFS=${BSP_CLI_PACKAGE_NAME}
	CHOSEN_DESKTOP=armbian-${RELEASE}-desktop-${DESKTOP_ENVIRONMENT}
	CHOSEN_KSRC=linux-source-${BRANCH}-${LINUXFAMILY}
}

function set_distribution_status() {

	local distro_support_desc_filepath="${SRC}/${DISTRIBUTIONS_DESC_DIR}/${RELEASE}/support"
	if [[ ! -f "${distro_support_desc_filepath}" ]]; then
		exit_with_error "Distribution ${distribution_name} does not exist"
	else
		DISTRIBUTION_STATUS="$(cat "${distro_support_desc_filepath}")"
	fi

	[[ "${DISTRIBUTION_STATUS}" != "supported" ]] && [[ "${EXPERT}" != "yes" ]] && exit_with_error "Armbian ${RELEASE} is unsupported and, therefore, only available to experts (EXPERT=yes)"

}

branch2dir() {
	[[ "${1}" == "head" ]] && echo "HEAD" || echo "${1##*:}"
}
