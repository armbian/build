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

DISTROS=("wheezy" "jessie" "trusty" "xenial")
 
showall ()
{


# function: cycle trough distributions
IFS=" "
j=0
while [[ $j -lt ${#DISTROS[@]} ]]
        do
        # add each packet to distribution
		DIS=${DISTROS[$j]}
		echo $DIS
		aptly repo show -with-packages  -config=config/aptly.conf $DIS | tail -n +7
		
        j=$[$j+1]
done
}

showall
