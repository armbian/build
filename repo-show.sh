#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#

# This scripts shows packages in local repository

# load functions
source general.sh

DISTROS=("wheezy" "jessie" "trusty" "xenial")
 
showall()
{
	for release in "${DISTROS[@]}"; do
		display_alert "Displaying repository contents for" "$release" "ext"
		aptly repo show -with-packages -config=config/aptly.conf $release | tail -n +7
	done
}

showall
