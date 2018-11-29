find_deb_configs(){
IFS=$'\n'
names=()
dirs=( $(find debs -maxdepth 2 -mindepth 2 -not -path "*/TEMPLATE/*" ) )

#echo $dirs

# required for "for" command
shopt -s nullglob dotglob

# check subdirectories for debian package definitions
for dir in "${dirs[@]}"; do
	for config in ${dir%%:*}/armbian.config; do
	#echo $config
		names+=($(basename $config))
		if [[ -f ${dir%%:*}/$names ]]; then
			local location_source="$SRC/${dir%%:*}/"
			local location_destination="$SRC/.tmp/${dir%%:*}/"
			create_deb_control $location_source $location_destination

			#echo $SRC/.tmp/${dir%%:*}/$names
		fi
	done
done
}

function process_line()
{
if [[ -f $1/$2 ]]; then
	local filename="$3$PACKAGE/DEBIAN/"$(echo $2 | sed -e "s/^armbian.//")
	postinst=$(bash $1/$2)
	while read -r line; do
    echo "$line" >> $filename
	done <<< "$postinst"
	chmod +x $filename
fi
}

function create_deb_control ()
{
	echo $1 $2
	unset PACKAGE ARCH SECTION PRIORITY DEPENDS PROVIDES RECOMMENDS REPOSITORY
	[[ -f $1/armbian.config ]] && source $1/armbian.config
	[[ -z $PACKAGE ]] && echo "Error. Package name must be defined" && return 1
	[[ -z $DESCRIPTION ]] && DESCRIPTION="Unnamed Armbian package"
	[[ -n $REPOSITORY ]] && REPOSITORY=$REPOSITORY"/"
	[[ $2 != "/" ]] && rm -rf $2 && mkdir -p $2/$PACKAGE $2/$PACKAGE/DEBIAN
	[[ -d $1/overlay ]] && cp -rp $1/overlay/. $2/$PACKAGE/
	local packagesize=$(du -sx --exclude DEBIAN	$2 | awk '{ print $1 }')

	process_line $1 "armbian.preinst" 	$2
	process_line $1 "armbian.postinst"	$2
	process_line $1 "armbian.prerm" 	$2
	process_line $1 "armbian.postrm" 	$2

	echo "Package: ${PACKAGE}"																	>  $2/$PACKAGE/DEBIAN/control
	echo "Version: ${REVISION}" 																>> $2/$PACKAGE/DEBIAN/control
	echo "Architecture: ${ARCH}" 																>> $2/$PACKAGE/DEBIAN/control
	echo "Maintainer: ${MAINTAINER} ${MAINTAINERMAIL}" 											>> $2/$PACKAGE/DEBIAN/control
	echo "Installed-Size: ${packagesize}" 														>> $2/$PACKAGE/DEBIAN/control
	echo "Section: ${SECTION}"																	>> $2/$PACKAGE/DEBIAN/control
	echo "Priority: ${PRIORITY}" 																>> $2/$PACKAGE/DEBIAN/control
	[[ -n $DEPENDS ]] && 		echo "Depends: $(echo ${DEPENDS} | tr " " ,)"					>> $2/$PACKAGE/DEBIAN/control
	[[ -n $PROVIDES ]] && 		echo "Provides: $(echo ${PROVIDES} | tr " " ,)"					>> $2/$PACKAGE/DEBIAN/control
	[[ -n $RECOMMENDS ]] && 	echo "Recommends: $(echo ${RECOMMENDS} | tr " " ,)"				>> $2/$PACKAGE/DEBIAN/control
	[[ -n $CONFLICTS ]] && 		echo "Conflicts: $(echo ${CONFLICTS} | tr " " ,)"				>> $2/$PACKAGE/DEBIAN/control
	[[ -n $REPLACES ]] && 		echo "Replaces: $(echo ${REPLACES} | tr " " ,)"					>> $2/$PACKAGE/DEBIAN/control
	echo -e "Homepage: ${HOMEPAGE}"																>> $2/$PACKAGE/DEBIAN/control
	echo -e "Description: ${DESCRIPTION}\n"														>> $2/$PACKAGE/DEBIAN/control

	fakeroot dpkg-deb -b $2/$PACKAGE $DEST/debs/${REPOSITORY}$PACKAGE.deb
}

find_deb_configs
#create_deb_control