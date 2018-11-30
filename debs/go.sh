# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# find_deb_configs

# cycle in deb subdirectories and look for armbian.config where are stored definitions to create DEB file
#
find_deb_configs(){

	IFS=$'\n'
	names=()
	dirs=( $(find debs -maxdepth 2 -mindepth 2 -not -path "*/TEMPLATE/*" ) )

	# required for "for" command
	shopt -s nullglob dotglob

	# check subdirectories for debian package definitions
	for dir in "${dirs[@]}"; do
		for config in ${dir%%:*}/armbian.config; do
			names+=($(basename $config))
				if [[ -f ${dir%%:*}/$names ]]; then
					local location_lowerdir="$SRC/${dir%%:*}/"
					local location_upperdir="$SRC/.tmp/.upperdir/${dir%%:*}/"
					local location_workdir="$SRC/.tmp/.workdir/${dir%%:*}/"
					local location_merged="$SRC/.tmp/.merged/${dir%%:*}/"
					create_deb_package $location_lowerdir $location_upperdir $location_workdir $location_merged
				fi
		done
done
}




# Helper for creating DEBIAN package scripts
#
function process_line()
{
local filename="$4/DEBIAN/"$(echo $2 | sed -e "s/^armbian.//")
if [[ -f $1/$2 ]]; then
	postinst=$(bash $1/$2)
else
	postinst=$(bash $SRC/debs/TEMPLATE/$2)
fi
	while read -r line; do
    echo "$line" >> $filename
	done <<< "$postinst"
	chmod +x $filename
}




# Create the package
#
function create_deb_package ()
{
	# $1 = sources directory
	# $2 = destination
	# $3 = work directory
	# $4 = merged directory

	# reset variables
	unset ARMBIAN_PKG_PACKAGE ARMBIAN_PKG_ARCH ARMBIAN_PKG_SECTION ARMBIAN_PKG_PRIORITY ARMBIAN_PKG_DEPENDS ARMBIAN_PKG_PROVIDES \
	ARMBIAN_PKG_RECOMMENDS ARMBIAN_PKG_CONFLICTS ARMBIAN_PKG_REPLACES ARMBIAN_PKG_REPOSITORY ARMBIAN_PKG_DESCRIPTION \
	ARMBIAN_PKG_MAINTAINER ARMBIAN_PKG_MAINTAINERMAIL

	# defaults
	ARMBIAN_PKG_REVISION=$REVISION
	ARMBIAN_PKG_MAINTAINER=$MAINTAINER
	ARMBIAN_PKG_MAINTAINERMAIL=$MAINTAINERMAIL
	ARMBIAN_PKG_HOMEPAGE="https://www.armbian.com"
	ARMBIAN_PKG_ARCH=all
	ARMBIAN_PKG_PRIORITY=optional

	# read package configuration
	source $1/armbian.config

	local upperdir="$2${ARMBIAN_PKG_PACKAGE}_${ARMBIAN_PKG_REVISION}_${ARMBIAN_PKG_ARCH}"
	local workdir="$3${ARMBIAN_PKG_PACKAGE}_${ARMBIAN_PKG_REVISION}_${ARMBIAN_PKG_ARCH}"
	local mergeddir="$4${ARMBIAN_PKG_PACKAGE}_${ARMBIAN_PKG_REVISION}_${ARMBIAN_PKG_ARCH}"

	# check if package already exists in repository
	[[ -n $(echo $REPOSITORY_PACKAGES | grep "${ARMBIAN_PKG_PACKAGE}_${ARMBIAN_PKG_REVISION}_${ARMBIAN_PKG_ARCH}") && $EXTERNAL_NEW != "compile" ]] && echo "${ARMBIAN_PKG_PACKAGE}_${ARMBIAN_PKG_REVISION}_${ARMBIAN_PKG_ARCH} exists. Skip building" && return 1

	# package name is mandatory
	[[ -z $ARMBIAN_PKG_PACKAGE ]] && echo "Error in $1 Package name must be defined" && return 1
	# overlay is mandatory
	[[ ! -d $1overlay ]] && echo "Error in $1overlay Overlay directory is missing" && return 1

	# description failover
	[[ -z $ARMBIAN_PKG_DESCRIPTION ]] && ARMBIAN_PKG_DESCRIPTION="Unnamed Armbian package"

	# add slash to the variable if subdirectory is defined
	[[ -n $ARMBIAN_PKG_REPOSITORY ]] && ARMBIAN_PKG_REPOSITORY+="/"

	# re-create directories
	if [[ $upperdir != "/" && $workdir != "/" && $mergeddir != "/" ]]; then
		rm -rf $upperdir $workdir $mergeddir
		mkdir -p $upperdir/DEBIAN $workdir $mergeddir
		# destination debs subdirectories if needed
		mkdir -p $DEST/debs/${ARMBIAN_PKG_REPOSITORY}
	fi

	# merge directories with overlay so we don't need to copy anything
	mount -t overlay overlay -olowerdir=$1overlay,upperdir=${upperdir},workdir=${workdir} ${mergeddir}

	# execute package custom build script if defined
	[[ -d $1/sources && -f $1/armbian.build ]] && source $1/armbian.build

	# calculate package size
	local packagesize=$(du -sx --exclude DEBIAN	$mergeddir | awk '{ print $1 }')

	echo "Packagin sources: $mergeddir"

	# compile DEBIAN scripts
	process_line $1 "armbian.preinst" 	$2 $upperdir
	process_line $1 "armbian.postinst"	$2 $upperdir
	process_line $1 "armbian.prerm" 	$2 $upperdir
	process_line $1 "armbian.postrm" 	$2 $upperdir

	# create DEBIAN control file
	echo "Package: ${ARMBIAN_PKG_PACKAGE}"																		>  $upperdir/DEBIAN/control
	echo "Version: ${ARMBIAN_PKG_REVISION}" 																	>> $upperdir/DEBIAN/control
	echo "Architecture: ${ARMBIAN_PKG_ARCH}" 																	>> $upperdir/DEBIAN/control
	echo "Maintainer: ${ARMBIAN_PKG_MAINTAINER} ${ARMBIAN_PKG_MAINTAINERMAIL}" 									>> $upperdir/DEBIAN/control
	echo "Installed-Size: ${packagesize}" 																		>> $upperdir/DEBIAN/control
	echo "Section: ${ARMBIAN_PKG_SECTION}"																		>> $upperdir/DEBIAN/control
	echo "Priority: ${ARMBIAN_PKG_PRIORITY}" 																	>> $upperdir/DEBIAN/control
	[[ -n $ARMBIAN_PKG_DEPENDS ]] && 		echo "Depends: $(echo ${ARMBIAN_PKG_DEPENDS} | tr " " ,)"			>> $upperdir/DEBIAN/control
	[[ -n $ARMBIAN_PKG_PROVIDES ]] && 		echo "Provides: $(echo ${ARMBIAN_PKG_PROVIDES} | tr " " ,)"			>> $upperdir/DEBIAN/control
	[[ -n $ARMBIAN_PKG_RECOMMENDS ]] && 	echo "Recommends: $(echo ${ARMBIAN_PKG_RECOMMENDS} | tr " " ,)"		>> $upperdir/DEBIAN/control
	[[ -n $ARMBIAN_PKG_CONFLICTS ]] && 		echo "Conflicts: $(echo ${ARMBIAN_PKG_CONFLICTS} | tr " " ,)"		>> $upperdir/DEBIAN/control
	[[ -n $ARMBIAN_PKG_REPLACES ]] && 		echo "Replaces: $(echo ${ARMBIAN_PKG_REPLACES} | tr " " ,)"			>> $upperdir/DEBIAN/control
	[[ -n $ARMBIAN_PKG_HOMEPAGE ]] &&		echo "Homepage: ${ARMBIAN_PKG_HOMEPAGE}"							>> $upperdir/DEBIAN/control
	echo -e "Description: ${ARMBIAN_PKG_DESCRIPTION}\n"															>> $upperdir/DEBIAN/control
	[[ -n $DEBUG_PKG ]] && cat $upperdir/DEBIAN/control
	# build the package and save in the output/debs directories
	fakeroot dpkg-deb -b $mergeddir $DEST/debs/${ARMBIAN_PKG_REPOSITORY}${ARMBIAN_PKG_PACKAGE}_${ARMBIAN_PKG_REVISION}_${ARMBIAN_PKG_ARCH}.deb
	umount -l $mergeddir
	# cleanup
	if [[ $upperdir != "/" && $workdir != "/" && $mergeddir != "/" ]]; then rm -rf $upperdir $workdir $mergeddir; fi
}

find_deb_configs