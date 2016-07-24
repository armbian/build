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

# This scripts recreates deb repository from files in directory POT
#
# each file is added three times! wheezy-jessie-trusty
#
# We are using this only for kernel, firmware, root changes, headers


[[ -f "../userpatches/lib.config" ]] && source "../userpatches/lib.config"

POT="../output/debs/"

# load functions
source general.sh

# run repository update
addtorepo

# add a key to repo
cp bin/armbian.key ../output/repository/public
cd ../output/repository/public

# upload to server with rsync
echo "done."
