#!/bin/bash
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# Functions:
#
# activate_zram
# activate_zram_swap
# activate_ramlog_partition
# activate_compressed_tmp


# Read in basic OS image information
. /etc/armbian-release
# and script configuration
. /usr/lib/armbian/armbian-common

# It's possible to override SWAP, ZRAM_PERCENTAGE, MEM_LIMIT_PERCENTAGE, ZRAM_MAX_DEVICES,
# SWAP_ALGORITHM, RAMLOG_ALGORITHM, TMP_ALGORITHM and TMP_SIZE here:
ENABLED=false
[ -f /etc/default/armbian-zram-config ] && . /etc/default/armbian-zram-config
# Exit if not Enabled
[[ "$ENABLED" != "true" ]] && exit 0

# Do not interfere with already present zram-config package
dpkg -l | grep -q 'zram-config' && exit 0

activate_zram() {
	# Load zram module with n instances for swap: one per CPU core, $ZRAM_MAX_DEVICES
	# defines the maximum, on modern kernels we overwrite this with 1 and rely on
	# max_comp_streams being set to count of CPU cores or $ZRAM_MAX_DEVICES
	uname -r | grep -q '^3.' && zram_max_devs=${ZRAM_MAX_DEVICES:=4} || zram_max_devs=1
	cpu_cores=$(grep -c '^processor' /proc/cpuinfo | sed 's/^0$/1/')
	[[ ${cpu_cores} -gt ${zram_max_devs} ]] && zram_devices=${zram_max_devs} || zram_devices=${cpu_cores}
	module_args="$(modinfo zram | awk -F" " '/num_devices/ {print $2}' | cut -f1 -d:)"
	[[ -n ${module_args} ]] && modprobe zram ${module_args}=$(( zram_devices + 2 )) || return

	swap_algo=${SWAP_ALGORITHM:=lzo}
	# Expose 50% of real memory as swap space by default
	zram_percent=${ZRAM_PERCENTAGE:=50}
	mem_info=$(LC_ALL=C free -w 2>/dev/null | grep "^Mem" || LC_ALL=C free | grep "^Mem")
	mem_info=$(echo $mem_info | awk '{print $2}')
	memory_total=$(( mem_info * 1024 ))
	mem_per_zram_device=$(( memory_total * zram_percent / zram_devices / 100 ))

	# Limit memory available to zram to 50% by default
	mem_limit_percent=${MEM_LIMIT_PERCENTAGE:=50}
	mem_limit_per_zram_device=$(( memory_total * mem_limit_percent / zram_devices / 100 ))
}

activate_zram_swap() {
	# Return is SWAP is disabled (enabled by default)
	[[ -n "$SWAP" && "$SWAP" != "true" ]] && return;

	# Disable zswap if zram should be used. To make use of zswap instead a
	# swap file or partition on *capable* storage needs to be chosen and
	# defined as swap and also in /etc/default/armbian-zram-config SWAP=false
	# needs to be set.
	echo 0 >/sys/module/zswap/parameters/enabled 2>/dev/null

	# Limit Journal size to 20Mb
	sed -i "s/.*SystemMaxUse=$/SystemMaxUse=20M/" /etc/systemd/journald.conf

	for (( i=1; i<=zram_devices; i++ )); do
		swap_device=$(zramctl -f |sed 's/\/dev\///')
		[[ ! ${swap_device} =~ ^zram ]] && printf "\n### No more available zram devices (%s)\n" "${swap_device}" >> ${Log} && exit 1;
		if [ -f /sys/block/${swap_device}/comp_algorithm ]; then
			# set compression algorithm, if defined as lzo choose lzo-rle if available
			# https://www.phoronix.com/scan.php?page=news_item&px=ZRAM-Linux-5.1-Better-Perform
			grep -q 'lzo-rle' /sys/block/${swap_device}/comp_algorithm && \
				[[ "X${swap_algo}" = "Xlzo" ]] && swap_algo="lzo-rle"
			echo ${swap_algo} >/sys/block/${swap_device}/comp_algorithm 2>/dev/null
		fi
		if [ "X${ZRAM_BACKING_DEV}" != "X" ]; then
			echo ${ZRAM_BACKING_DEV} >/sys/block/${swap_device}/backing_dev
		fi
		echo -n ${ZRAM_MAX_DEVICES:=4} > /sys/block/${swap_device}/max_comp_streams
		echo -n ${mem_per_zram_device} > /sys/block/${swap_device}/disksize
		echo -n ${mem_limit_per_zram_device} > /sys/block/${swap_device}/mem_limit
		mkswap /dev/${swap_device}
		swapon -p 5 /dev/${swap_device}
	done

	# Swapping to HDDs is stupid so switch to settings made for flash memory and zram/zswap
	echo 0 > /proc/sys/vm/page-cluster

	printf "\n### Activated %s %s zram swap devices with %dMB each.\n" "${zram_devices}" "${swap_algo}" "$((mem_per_zram_device / 1048576))" >> ${Log}
} # activate_zram_swap

activate_ramlog_partition() {
	# /dev/zram0 will be used as a compressed /var/log partition in RAM if
	# ENABLED=true in /etc/default/armbian-ramlog is set
	ENABLED=$(awk -F"=" '/^ENABLED/ {print $2}' /etc/default/armbian-ramlog)
	[[ "$ENABLED" != "true" ]] && return
	log_device=$(zramctl -f |sed 's/\/dev\///')
	[[ ! ${log_device} =~ ^zram ]] && printf "\n### No more available zram devices (%s)\n" "${log_device}" >> ${Log} && exit 1;

	# read size also from /etc/default/armbian-ramlog
	ramlogsize=$(awk -F"=" '/^SIZE/ {print $2}' /etc/default/armbian-ramlog)
	disksize=$(sed -e 's/M$/*1048576/' -e 's/K$/*1024/' <<<${ramlogsize:=50M} | bc)

	# choose RAMLOG_ALGORITHM if defined in /etc/default/armbian-zram-config
	# otherwise try to choose most efficient compression scheme available.
	# See https://patchwork.kernel.org/patch/9918897/
	if [ "X${RAMLOG_ALGORITHM}" = "X" ]; then
		for algo in lz4 lz4hc quicklz zlib brotli zstd ; do
			echo ${algo} >/sys/block/${log_device}/comp_algorithm 2>/dev/null
		done
	else
		echo ${RAMLOG_ALGORITHM} >/sys/block/${log_device}/comp_algorithm 2>/dev/null
	fi
	echo -n ${disksize} > /sys/block/${log_device}/disksize

	# if it fails, select $swap_algo. Workaround for some older kernels
	if [[ $? == 1 ]]; then
		echo ${swap_algo} > /sys/block/${log_device}/comp_algorithm 2>/dev/null
		echo -n ${disksize} > /sys/block/${log_device}/disksize
	fi

	mkfs.ext4 -O ^has_journal -s 1024 -L log2ram /dev/${log_device}
	algo=$(sed 's/.*\[\([^]]*\)\].*/\1/g' </sys/block/${log_device}/comp_algorithm)
	printf "### Activated Armbian ramlog partition with %s compression\n" "${algo}" >> ${Log}
} # activate_ramlog_partition

activate_compressed_tmp() {
	# create /tmp not as tmpfs but zram compressed if no fstab entry exists
	grep -q '^tmpfs /tmp' /etc/mtab && return
	tmp_device=$(zramctl -f |sed 's/\/dev\///')
	[[ ! ${tmp_device} =~ ^zram ]] && printf "\n### No more available zram devices (%s)\n" "${tmp_device}" >> ${Log} && exit 1;

	if [[ -f /sys/block/${tmp_device}/comp_algorithm ]]; then
		if [ "X${TMP_ALGORITHM}" = "X" ]; then
			echo ${swap_algo} >/sys/block/${tmp_device}/comp_algorithm 2>/dev/null
		else
			echo ${TMP_ALGORITHM} >/sys/block/${tmp_device}/comp_algorithm 2>/dev/null
		fi
	fi
	[[ -z ${TMP_SIZE} ]] && echo -n $(( memory_total / 2 )) > /sys/block/${tmp_device}/disksize || echo -n ${TMP_SIZE} > /sys/block/${tmp_device}/disksize
	mkfs.ext4 -O ^has_journal -s 1024 -L tmp /dev/${tmp_device}
	mount -o nosuid,discard /dev/${tmp_device} /tmp
	chmod 1777 /tmp
	algo=$(sed 's/.*\[\([^]]*\)\].*/\1/g' </sys/block/${tmp_device}/comp_algorithm)
	printf "\n### Activated %s compressed /tmp\n" "${algo}" >> ${Log}
} # activate_compressed_tmp

case $1 in
	*start*)
		activate_zram
		activate_zram_swap
		activate_ramlog_partition
		activate_compressed_tmp
		;;
esac
