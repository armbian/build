# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
#
# find_deb_packages_prepare
# process_line
# create_deb_package

# cycle in deb subdirectories and look for armbian.config where are stored definitions to create DEB file
#
find_deb_packages_prepare(){

	local ifs=$IFS
	ARMBIAN_PACKAGE_LIST=""
	IFS=$'\n'
	names=()
	dirs=( $(find $SRC/config/packages -maxdepth 2 -mindepth 2 -not -path "*/TEMPLATE/*" ) )

	# required for "for" command
	shopt -s nullglob dotglob

	# check subdirectories for debian package definitions
	for dir in "${dirs[@]}"; do
		cleaned_dir=${dir/#$SRC}
		cleaned_dir=${cleaned_dir//config\/packages\/}

		for config in ${dir%%:*}/armbian.config; do
			names+=($(basename $config))
			local first="$(cut -d'/' -f2 <<<"${cleaned_dir%%:*}")"
			local second="$(cut -d'/' -f3 <<<"${cleaned_dir%%:*}")"
				if [[ -f ${dir%%:*}/$names ]]; then
					local location_lowerdir="${dir%%:*}/"
					local location_upperdir="$SRC/.tmp/.upperdir${cleaned_dir%%:*}/"
					local location_workdir="$SRC/.tmp/.workdir${cleaned_dir%%:*}/"
					local location_merged="$SRC/.tmp/.merged${cleaned_dir%%:*}/"
					create_deb_package $location_lowerdir $location_upperdir $location_workdir $location_merged $first $second
				fi
		done
	done
	IFS=$ifs
}




# Helper for creating DEBIAN package scripts
#
function process_line()
{
local filename="$4/DEBIAN/"$(echo $2 | sed -e "s/^armbian.//")

if [[ -f $1/$2 ]]; then
	postinst=$(source $1/$2)
else
	postinst=$(source $SRC/config/packages/TEMPLATE/$2)
fi

while read -r line; do
	echo "$line" >> $filename
done <<< "$postinst"
chmod 755 $filename
}




# Create the package
#
function create_deb_package ()
{
	# $1 = sources directory
	# $2 = destination
	# $3 = work directory
	# $4 = merged directory
	# $5 = type (board,common,family,...)
	# $6 = name (pinebook,armbian-config,rockchip64,)

	# reset variables
	unset ARMBIAN_PKG_PACKAGE ARMBIAN_PKG_ARCH ARMBIAN_PKG_SECTION ARMBIAN_PKG_PRIORITY ARMBIAN_PKG_DEPENDS \
	ARMBIAN_PKG_PROVIDES ARMBIAN_PKG_RECOMMENDS ARMBIAN_PKG_CONFLICTS ARMBIAN_PKG_REPLACES ARMBIAN_PKG_REPOSITORY \
	ARMBIAN_PKG_DESCRIPTION ARMBIAN_PKG_MAINTAINER ARMBIAN_PKG_MAINTAINERMAIL ARMBIAN_PKG_INSTALL

	# set defaults which are overwritten via package armbian.config file
	ARMBIAN_PKG_REVISION=$REVISION
	ARMBIAN_PKG_MAINTAINER=$MAINTAINER
	ARMBIAN_PKG_MAINTAINERMAIL=$MAINTAINERMAIL
	ARMBIAN_PKG_HOMEPAGE="https://www.armbian.com"
	ARMBIAN_PKG_DESCRIPTION="Unnamed Armbian package"
	ARMBIAN_PKG_ARCH=all
	ARMBIAN_PKG_PRIORITY=optional

	# read package configuration
	source $1/armbian.config

	# define local variables for better readability
	local pkgname="${ARMBIAN_PKG_PACKAGE}_${ARMBIAN_PKG_REVISION}_${ARMBIAN_PKG_ARCH}"
	local lowerdir="$1"		# source
	local upperdir="$2${pkgname}"	# destination
	local workdir="$3${pkgname}"	# reserved
	local mergeddir="$4${pkgname}"	# source overlay + destination

	# Packing only for the selected family
	[[ $5 == "family" && $LINUXFAMILY != $6 ]] && return 1
	# Packing only for the selected board
	[[ $5 == "board" && $BOARD != $6 ]] && return 1
	# Packing only for CLI
	[[ $6 == armbian-desktop* && $BUILD_DESKTOP != "yes" ]] && return 1

	# package name is mandatory
	[[ -z $ARMBIAN_PKG_PACKAGE ]] && display_alert "Packing" "Missing package name in $1 Skip building." "err" && return 1

        if [[ $TVBOXES_ROOT != yes ]]; then
		# overlay is mandatory
		[[ ! -d $1overlay ]] && display_alert "Packing" "Missing overlay directory in $1 Skip building." "err" && return 1
	fi

	# add package to the install list
	[[ $ARMBIAN_PKG_INSTALL != "no" ]] && ARMBIAN_PACKAGE_LIST+=" ${ARMBIAN_PKG_PACKAGE}"

	# check if package already exists in repository
	if [[ -n $(echo $REPOSITORY_PACKAGES | grep "${pkgname}") && $EXTERNAL_NEW != "compile" ]]; then
		display_alert "Packing" "dpkg-deb: ${pkgname} exists in the repository and force rebuilding is disabled. Skip building" "wrn"
		return 1
	fi

	# re-create temporally directories
	if [[ $upperdir != "/" && $workdir != "/" && $mergeddir != "/" ]]; then
		rm -rf $upperdir $workdir $mergeddir
		mkdir -p $upperdir/DEBIAN $workdir $mergeddir
		# destination debs subdirectories if needed
		mkdir -p $DEST/debs/${ARMBIAN_PKG_REPOSITORY}
	fi

	# merge directories with overlay so we don't need to copy anything
	mount -t overlay overlay -olowerdir=${lowerdir}overlay,upperdir=${upperdir},workdir=${workdir} ${mergeddir}

	# execute package custom build script if defined
	[[ -d $lowerdir/sources && -f $lowerdir/armbian.build ]] && source $lowerdir/armbian.build

	# calculate package size
	local packagesize=$(du -sx --exclude DEBIAN	$mergeddir | awk '{ print $1 }')

	# creaate md5sums
	local mdsum=$(cd $mergeddir;find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' \
	-printf '%P ' | xargs --no-run-if-empty md5sum > DEBIAN/md5sums)

	# compile DEBIAN scripts
	process_line $lowerdir "armbian.preinst" 	$2 $upperdir
	process_line $lowerdir "armbian.postinst"	$2 $upperdir
	process_line $lowerdir "armbian.prerm" 		$2 $upperdir
	process_line $lowerdir "armbian.postrm" 	$2 $upperdir

	# create DEBIAN control file
	local control="$upperdir/DEBIAN/control"
	echo "Package: ${ARMBIAN_PKG_PACKAGE}"									>  $control
	echo "Version: ${ARMBIAN_PKG_REVISION}" 								>> $control
	echo "Architecture: ${ARMBIAN_PKG_ARCH}" 								>> $control
	echo "Maintainer: ${ARMBIAN_PKG_MAINTAINER} ${ARMBIAN_PKG_MAINTAINERMAIL}"				>> $control
	echo "Installed-Size: ${packagesize}" 									>> $control
	echo "Section: ${ARMBIAN_PKG_SECTION}"									>> $control
	echo "Priority: ${ARMBIAN_PKG_PRIORITY}" 								>> $control
	[[ -n $ARMBIAN_PKG_DEPENDS ]] && echo "Depends: $(echo ${ARMBIAN_PKG_DEPENDS} | tr " " , | sed "s/[[:space:]]\+/ /g")"		>> $control
	[[ -n $ARMBIAN_PKG_PROVIDES ]] && echo "Provides: $(echo ${ARMBIAN_PKG_PROVIDES} | tr " " , | sed "s/[[:space:]]\+/ /g")"		>> $control
	[[ -n $ARMBIAN_PKG_RECOMMENDS ]] && echo "Recommends: $(echo ${ARMBIAN_PKG_RECOMMENDS} | tr " " , | sed "s/[[:space:]]\+/ /g")"	>> $control
	[[ -n $ARMBIAN_PKG_CONFLICTS ]] && echo "Conflicts: $(echo ${ARMBIAN_PKG_CONFLICTS} | tr " " , | sed "s/[[:space:]]\+/ /g")"	>> $control
	[[ -n $ARMBIAN_PKG_REPLACES ]] && echo "Replaces: $(echo ${ARMBIAN_PKG_REPLACES} | tr " " , | sed "s/[[:space:]]\+/ /g")"		>> $control
	[[ -n $ARMBIAN_PKG_HOMEPAGE ]] && echo "Homepage: ${ARMBIAN_PKG_HOMEPAGE}"				>> $control
	echo "Description: ${ARMBIAN_PKG_DESCRIPTION}"								>> $control

	# add slash to the variable if subdirectory is defined
	[[ -n $ARMBIAN_PKG_REPOSITORY ]] && ARMBIAN_PKG_REPOSITORY+="/"

	# build the package and save it in the output/debs directories
	display_alert "Packing" "$(fakeroot dpkg-deb -b $mergeddir $DEST/debs/${ARMBIAN_PKG_REPOSITORY}${pkgname}.deb)"
	install_deb_chroot "$DEST/debs/${ARMBIAN_PKG_REPOSITORY}${pkgname}.deb"

	umount -l $mergeddir

	# cleanup
	if [[ $upperdir != "/" && $workdir != "/" && $mergeddir != "/" ]]; then rm -rf $upperdir $workdir $mergeddir; fi
}
