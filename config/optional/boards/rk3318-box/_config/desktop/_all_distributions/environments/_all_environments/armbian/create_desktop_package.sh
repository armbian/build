# Fix for bad device detection for x.org when lima driver is in use
if [[ "$BRANCH" != "legacy" ]]; then
	mkdir -p $destination/etc/X11/xorg.conf.d
        cp $SRC/packages/bsp/rk3328/40-serverflags.conf $destination/etc/X11/xorg.conf.d
fi

# @TODO: @paolosabatino: this is no longer included in aggregation; it will have to be handled in some kind of extension
