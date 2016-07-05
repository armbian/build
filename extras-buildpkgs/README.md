Installing packages to images:

* Add a function for installing packages

* Add a variable for dependencies or function for extracting dependencies from deb files

* Add a variable for list of packages to install during debootstrap

* Add a variable for installing condition (branch, release, desktop, ...)


Building:

* Add a function / code to move packages to $DEST/debs/extras

* Adjust "debs" option of CLEAN_LEVEL to delete old packages in "extras" subdirectory

* Add a code to check if package exists / package needs (re)building


All packages:

* Add sunxi-mali package if BLOBs license allows redistribution, otherwise create an installer like oracle-jdk

* Add hostapd-realtek package - copy of hostapd with realtek-specific patches

* Delete unused files (i.e. *.lintian-overrides)

* Add missing udev rules to appropriate packages

```
KERNEL=="disp", MODE="0660", GROUP="video"
KERNEL=="cedar_dev", MODE="0660", GROUP="video"
KERNEL=="ump", MODE="0660", GROUP="video"
KERNEL=="mali", MODE="0660", GROUP="video"
```


Package-specific:

* ffmpeg: disable building documentation

* libvdpau-sunxi: select branch (master or dev)

* mpv: extract upstream version from repository
