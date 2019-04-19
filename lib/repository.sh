#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# This script shows packages in local repository

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPTPATH=${SCRIPTPATH//lib}

# load user config
[[ -f "${SCRIPTPATH}userpatches/lib.config" ]] && source "${SCRIPTPATH}/userpatches/lib.config"

# define debs path
POT="${SCRIPTPATH}/output/debs/"

# load functions
source ${SCRIPTPATH}lib/general.sh

DISTROS=("jessie" "xenial" "stretch" "bionic" "buster" "disco")

ParseOptions() {
	case $@ in
		serve)
			# display repository content
			display_alert "Serving content" "common utils" "ext"
			aptly serve -listen=:8080 -config=${SCRIPTPATH}config/aptly.conf
			exit 0
			;;
		show)
			# display repository content
			for release in "${DISTROS[@]}"; do
				display_alert "Displaying repository contents for" "$release" "ext"
				aptly repo show -with-packages -config=${SCRIPTPATH}config/aptly.conf $release | tail -n +7
				aptly repo show -with-packages -config=${SCRIPTPATH}config/aptly.conf ${release}-desktop | tail -n +7
			done
			display_alert "Displaying repository contents for" "common utils" "ext"
			aptly repo show -with-packages -config=${SCRIPTPATH}config/aptly.conf utils | tail -n +7
			echo "done."
			exit 0
			;;
		update)
			# display full help test
			# run repository update
			addtorepo "$@" ""
			# add a key to repo
			cp ${SCRIPTPATH}config/armbian.key ${SCRIPTPATH}output/repository/public
			exit 0
			;;
		purge)
			for release in "${DISTROS[@]}"; do
				repo-remove-old-packages "$release" "armhf" "5"
				repo-remove-old-packages "$release" "arm64" "5"
				repo-remove-old-packages "$release" "all" "5"
				aptly -config=${SCRIPTPATH}config/aptly.conf -passphrase=$GPG_PASS publish update $release
				# example to remove all packages from bionic that contain source in the name
				# aptly repo remove -config=${SCRIPTPATH}config/aptly.conf bionic 'Name (% *-source*)'
			done
			exit 0
			;;
		*)
			DisplayUsage
			exit 0
			;;
	esac
} # ParseOptions

# Removes old packages in the received repo
#
# $1: Repository
# $2: Architecture
# $3: Amount of packages to keep
repo-remove-old-packages() {
    local repo=$1
    local arch=$2
    local keep=$3

    for pkg in $(aptly repo search -config=${SCRIPTPATH}config/aptly.conf $repo "Architecture ($arch)" | grep -v "ERROR: no results" | sort -rV); do
        local pkg_name=$(echo $pkg | cut -d_ -f1)
        if [ "$pkg_name" != "$cur_pkg" ]; then
            local count=0
            local deleted=""
            local cur_pkg="$pkg_name"
        fi
        test -n "$deleted" && continue
        let count+=1
        if [ $count -gt $keep ]; then
            pkg_version=$(echo $pkg | cut -d_ -f2)
            aptly repo remove -config=${SCRIPTPATH}config/aptly.conf $repo "Name ($pkg_name), Version (<= $pkg_version)"
            deleted='yes'
        fi
    done
}

DisplayUsage() {
	echo -e "Usage: repository show | serve | create | update | purge\n"
	echo -e "\n show   = display repository content"
	echo -e "\n serve  = publish your repositories on current server over HTTP"
	echo -e "\n update = updating repository"
	echo -e "\n purge  = removes all but last 5 versions\n\n"
} # DisplayUsage

ParseOptions "$@"
