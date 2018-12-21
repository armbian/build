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



# cycle in deb subdirectories and look for armbian.config.bash where are stored definitions to create DEB file
#
find_deb_packages_prepare(){

	REPOSITORY_PACKAGES="`wget -qO- https://apt.armbian.com/.packages.txt`"
	# recreate directories just to make sure aptly won't break
	mkdir -p $DEST/debs/extra/${RELEASE}-desktop $DEST/debs/extra/${RELEASE}-utils

	local ifs=$IFS
	ARMBIAN_PACKAGE_LIST=""
	IFS=$'\n'
	names=()
	dirs=( $(find $SRC/config/packages -maxdepth 2 -mindepth 2 -not -path "*/TEMPLATE/*" | sort ) )

	# required for "for" command
	shopt -s nullglob dotglob

	# check subdirectories for debian package definitions
	for dir in "${dirs[@]}"; do
		cleaned_dir=${dir/#$SRC}
		cleaned_dir=${cleaned_dir//config\/packages\/}

		for config in ${dir%%:*}/armbian.config.bash; do
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
local filename="$4/DEBIAN/"$(echo $2 | sed -e "s/^armbian.//" | sed -e "s/.bash$//")
if [[ -f $1/$2 ]]; then
	postinst=$(source $1/$2)
while read -r line; do
	echo "$line" >> $filename
done <<< "$postinst"
chmod 755 $filename
fi
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
	ARMBIAN_PKG_DESCRIPTION ARMBIAN_PKG_MAINTAINER ARMBIAN_PKG_MAINTAINERMAIL ARMBIAN_PKG_INSTALL ARMBIAN_PKG_SUGGESTS

	# set defaults which are overwritten via package armbian.config.bash file
	ARMBIAN_PKG_REVISION=$REVISION
	ARMBIAN_PKG_MAINTAINER=$MAINTAINER
	ARMBIAN_PKG_MAINTAINERMAIL=$MAINTAINERMAIL
	ARMBIAN_PKG_HOMEPAGE="https://www.armbian.com"
	ARMBIAN_PKG_DESCRIPTION="Unnamed Armbian package"
	ARMBIAN_PKG_ARCH=all
	ARMBIAN_PKG_PRIORITY=optional

	# read package configuration
	source $1/armbian.config.bash

	# define local variables for better readability
	local pkgname="${ARMBIAN_PKG_PACKAGE}_${ARMBIAN_PKG_REVISION}_${ARMBIAN_PKG_ARCH}"
	local lowerdir="$1"		# source
	local upperdir="$2${pkgname}"	# destination
	local workdir="$3${pkgname}"	# reserved
	local mergeddir="$4${pkgname}"	# source overlay + destination
	local dirforpacking=${upperdir}	# depandable wheather we have an overlay or not

	# Packing only for the selected family
	[[ $5 == *-family && $LINUXFAMILY != $6 ]] && return 1
	# Packing only for the selected board
	[[ $5 == *-board && $BOARD != $6 ]] && return 1
	# Packing only for CLI
	[[ $6 == armbian-desktop* && $BUILD_DESKTOP != "yes" ]] && return 1

	# install dependencies
	if [[ -n $ARMBIAN_PKG_DEPENDS && $ARMBIAN_PKG_INSTALL != "no" ]]; then
		display_alert "Dependecies for" "${ARMBIAN_PKG_PACKAGE}"
		chroot $SDCARD /bin/bash -c "apt -qq -y install ${ARMBIAN_PKG_DEPENDS}" >> $DEST/debug/install.log 2>&1
		if [[ $? == 0 ]]; then display_alert "Installed" "" "info"; else display_alert "Installed" "" "err"; fi
	fi

	# check if package already exists in repository
	if [[ -n $(echo $REPOSITORY_PACKAGES | grep "${pkgname}") && $PACKAGES_RECOMPILE != "yes" && -n ${ARMBIAN_PKG_PACKAGE} ]]; then
		chroot $SDCARD /bin/bash -c "apt -qq -y install ${ARMBIAN_PKG_PACKAGE}" >> $DEST/debug/install.log 2>&1
		if [[ $? == 0 ]]; then display_alert "Installed" "${ARMBIAN_PKG_PACKAGE} from repository. Force rebuilding is disabled." "info"; else display_alert "Installed" "${ARMBIAN_PKG_PACKAGE}" "err"; fi
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
	if [[ -d $1overlay ]]; then
		mount -t overlay overlay -olowerdir=${lowerdir}overlay,upperdir=${upperdir},workdir=${workdir} ${mergeddir}
		dirforpacking=${mergeddir}
	fi

	# execute package custom build script if defined
	if [[ -f ${lowerdir}armbian.build.bash ]]; then
		display_alert "Executing" "${lowerdir}armbian.build.bash" "info"
		source ${lowerdir}armbian.build.bash
	fi

	if [[ -d $1overlay ]]; then
	# calculate package size
	local packagesize=$(du -sx --exclude DEBIAN	$dirforpacking | awk '{ print $1 }')

	# creaate md5sums
	local mdsum=$(cd $dirforpacking;find . -type f ! -regex '.*.hg.*' ! -regex '.*?debian-binary.*' ! -regex '.*?DEBIAN.*' \
	-printf '"%p"\n' | xargs --no-run-if-empty md5sum > DEBIAN/md5sums)
	fi

	# compile DEBIAN scripts
	process_line ${lowerdir} "armbian.preinst.bash" 	$2 $upperdir
	process_line ${lowerdir} "armbian.postinst.bash"	$2 $upperdir
	process_line ${lowerdir} "armbian.prerm.bash" 		$2 $upperdir
	process_line ${lowerdir} "armbian.postrm.bash" 	$2 $upperdir
	process_line ${lowerdir} "armbian.triggers.bash" 	$2 $upperdir

	# create DEBIAN control file
	local control="$upperdir/DEBIAN/control"
	echo "Package: ${ARMBIAN_PKG_PACKAGE}"														>  $control
	echo "Version: ${ARMBIAN_PKG_REVISION}" 													>> $control
	echo "Architecture: ${ARMBIAN_PKG_ARCH}" 													>> $control
	echo "Maintainer: ${ARMBIAN_PKG_MAINTAINER} ${ARMBIAN_PKG_MAINTAINERMAIL}"					>> $control
	echo "Installed-Size: ${packagesize}" 														>> $control
	echo "Section: ${ARMBIAN_PKG_SECTION}"														>> $control
	echo "Priority: ${ARMBIAN_PKG_PRIORITY}" 													>> $control
	[[ -n $ARMBIAN_PKG_DEPENDS ]] && \
	echo "Depends: $(echo ${ARMBIAN_PKG_DEPENDS} | tr " " , | sed "s/[[:space:]]\+/ /g")"		>> $control
	[[ -n $ARMBIAN_PKG_PROVIDES ]] && \
	echo "Provides: $(echo ${ARMBIAN_PKG_PROVIDES} | tr " " , | sed "s/[[:space:]]\+/ /g")"		>> $control
	[[ -n $ARMBIAN_PKG_SUGGESTS ]] && \
	echo "Suggests: $(echo ${ARMBIAN_PKG_SUGGESTS} | tr " " , | sed "s/[[:space:]]\+/ /g")"		>> $control
	[[ -n $ARMBIAN_PKG_RECOMMENDS ]] && \
	echo "Recommends: $(echo ${ARMBIAN_PKG_RECOMMENDS} | tr " " , | sed "s/[[:space:]]\+/ /g")"	>> $control
	[[ -n $ARMBIAN_PKG_CONFLICTS ]] && \
	echo "Conflicts: $(echo ${ARMBIAN_PKG_CONFLICTS} | tr " " , | sed "s/[[:space:]]\+/ /g")"	>> $control
	[[ -n $ARMBIAN_PKG_REPLACES ]] && \
	echo "Replaces: $(echo ${ARMBIAN_PKG_REPLACES} | tr " " , | sed "s/[[:space:]]\+/ /g")"		>> $control
	[[ -n $ARMBIAN_PKG_HOMEPAGE ]] && \
	echo "Homepage: ${ARMBIAN_PKG_HOMEPAGE}"													>> $control
	echo "Description: ${ARMBIAN_PKG_DESCRIPTION}"												>> $control

	# add slash to the variable if subdirectory is defined
	[[ -n $ARMBIAN_PKG_REPOSITORY ]] && ARMBIAN_PKG_REPOSITORY+="/"

	# if package name is defined, create deb file
	if [[ -n $ARMBIAN_PKG_PACKAGE ]]; then
		# build the package and save it in the output/debs directories
		fakeroot dpkg-deb -b $dirforpacking $DEST/debs/${ARMBIAN_PKG_REPOSITORY}${pkgname}.deb >> $DEST/debug/install.log 2>&1
		if [[ $? == 0 ]]; then display_alert "Packed" "${pkgname}.deb" "info"; else \
			umount -l $mergeddir > /dev/null 2>&1
			exit_with_error "Packaging process for ${pkgname}.deb ended with error"
		fi
		[[ $ARMBIAN_PKG_INSTALL != "no" ]] && install_deb_chroot "$DEST/debs/${ARMBIAN_PKG_REPOSITORY}${pkgname}.deb"
	fi

	umount -l $mergeddir > /dev/null 2>&1

	# cleanup
	if [[ $upperdir != "/" && $workdir != "/" && $mergeddir != "/" ]]; then rm -rf $upperdir $workdir $mergeddir; fi
}
