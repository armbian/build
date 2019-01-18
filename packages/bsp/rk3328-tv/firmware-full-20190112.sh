
NAME_PKG="firmware-full-20190112"

build_firmware-aml()
{
	display_alert "Merging and packaging linux $NAME_PKG" "@host" "info"

	local plugin_repo="https://github.com/150balbes/pkg-aml"
	local plugin_dir=${NAME_PKG}
	[[ -d $SRC/cache/sources/$plugin_dir ]] && rm -rf $SRC/cache/sources/$plugin_dir

	fetch_from_repo "$plugin_repo" "$plugin_dir/lib" "branch:${NAME_PKG}"

	rm -R $SRC/cache/sources/$plugin_dir/lib/.git
	cd $SRC/cache/sources/$plugin_dir

	# set up control file
	mkdir -p DEBIAN
	cat <<-END > DEBIAN/control
	Package: $NAME_PKG
	Version: $REVISION
	Architecture: $ARCH
	Maintainer: $MAINTAINER <$MAINTAINERMAIL>
	Installed-Size: 1
	Replaces: linux-firmware
	Section: kernel
	Priority: optional
	Description: Linux $NAME_PKG
	END

	cd $SRC/cache/sources
	# pack
	mv ${NAME_PKG} ${NAME_PKG}_${REVISION}_${ARCH}
	dpkg -b ${NAME_PKG}_${REVISION}_${ARCH} >> $DEST/debug/install.log
# 2>&1
	mv ${NAME_PKG}_${REVISION}_${ARCH} ${NAME_PKG}
	mv ${NAME_PKG}_${REVISION}_${ARCH}.deb $DEST/debs/ || display_alert "Failed moving ${NAME_PKG} package" "" "wrn"
}

[[ ! -f $DEST/debs/${NAME_PKG}_${REVISION}_${ARCH}.deb ]] && build_firmware-aml

# install basic firmware by default
display_alert "Installing $NAME_PKG" "$REVISION" "info"
install_deb_chroot "$DEST/debs/${NAME_PKG}_${REVISION}_${ARCH}.deb"
