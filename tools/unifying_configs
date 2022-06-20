#!/bin/bash
#
#	License: (MIT) <https://mit-license.org/>
#
#	Copyright (c) 2020-2022 Igor Pecovnik
#
#       This small snippet helps to unify kernel configs > v5 uptions
#
#       Usage:
#       cd config/kernel
#       bash unifying_configs CONFIG_HAVE_FUNCTION_TRACER y
#

if [[ -n $1 ]]; then

while true; do
    read -p "Do you wish to apply changes? " yn
    case $yn in
        [Yy]* )
		LOCATION=($(grep " Kernel Configuration" *.config | grep " 5." | cut -d":" -f1))
		for loc in "${LOCATION[@]}"
		do
		if grep --quiet "# $1 is not set" $loc; then
			echo "Changing ... $1 in file $loc"
			sed -i -- 's/# '$1' is not set/'$1'='$2'/g' $loc
		fi
		done
		break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
else
	echo "Example use: bash $(basename "$0") CONFIG_HAVE_FUNCTION_TRACER y"
fi
