#!/bin/bash

# create directories
mkdir -p $upperdir/usr/bin
mkdir -p $upperdir/usr/sbin
mkdir -p $upperdir/usr/lib/armbian-config

# copy files to target directories

install -m 755 $lowerdir/sources/scripts/tv_grab_file				$upperdir/usr/bin/tv_grab_file
install -m 755 $lowerdir/sources/debian-config					$upperdir/usr/sbin/armbian-config
install -m 644 $lowerdir/sources/debian-config-jobs 				$upperdir/usr/lib/armbian-config/jobs.sh
install -m 644 $lowerdir/sources/debian-config-submenu 			$upperdir/usr/lib/armbian-config/submenu.sh
install -m 644 $lowerdir/sources/debian-config-functions 			$upperdir/usr/lib/armbian-config/functions.sh
install -m 644 $lowerdir/sources/debian-config-functions-network 		$upperdir/usr/lib/armbian-config/functions-network.sh
install -m 755 $lowerdir/sources/softy 					$upperdir/usr/sbin/softy

# fallback to replace armbian-config in BSP
ln -s /usr/sbin/armbian-config $upperdir/usr/bin/armbian-config
ln -s /usr/sbin/softy $upperdir/usr/bin/softy