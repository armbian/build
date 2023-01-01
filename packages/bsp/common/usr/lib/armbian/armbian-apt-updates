#!/bin/bash
#
#   40-updates - create the list of packages for update with caching
#   Copyright (c) 2015 Arkadiusz Raj
#
#   Author: Arkadiusz Raj arek.raj@gmail.com
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License along
#   with this program; if not, write to the Free Software Foundation, Inc.,
#   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.


lock_file='/var/run/armbian-motd-updates.lock'
if { set -C; 2>/dev/null >${lock_file}; }; then
    trap "rm -f ${lock_file}" EXIT
else
    exit 0
fi

# give up if packages are broken
[[ $(dpkg -l | grep ^..r) ]] && exit 0

# give up if there is a dependency problem
[[ "$((apt-get upgrade -s -qq) 2>&1)" == *"Unmet dependencies"* ]] && exit 0

myfile="/var/cache/apt/archives/updates.number"
myfiles="/var/cache/apt/archives/updates.list"

# update procedure
DISTRO=$(lsb_release -c | cut -d ":" -f 2 |  tr -d '[:space:]') && DISTRO=${DISTRO,,}

# run around the packages
upgrades=0
security_upgrades=0

while IFS= read -r LINE; do
        # increment the upgrade counter
        (( upgrades++ ))
        # keep another count for security upgrades
        [[ ${LINE} == *"${DISTRO}-sec"* ]] && (( security_upgrades++ ))
done < <(apt-get upgrade -s -qq | sed -n '/^Inst/p')

cat >|${myfile} <<EOT
NUM_UPDATES="${upgrades}"
NUM_UPDATES_ONHOLD="$(dpkg --list | grep ^hi | grep $(uname -r) | wc -l)"
NUM_SECURITY_UPDATES="${security_upgrades}"
DATE="$(date +"%Y-%m-%d %H:%M")"
EOT

# store packages list
dpkg --list | grep ^hi | grep $(uname -r) | awk '{ print $2 }' >| ${myfiles}

exit 0

