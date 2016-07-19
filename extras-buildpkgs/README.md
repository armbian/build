# TODO

### Installing packages to images:

* Add a function for installing packages - **done**

* Use aptly to create local repository: this will allow solving dependencies on installation automatically - **done**

* Add a variable for list of packages to install during debootstrap - **done**

* Add a variable for installing condition (branch, release, desktop, ...) - **done**


### Building:

* Add a function / code to move packages to $DEST/debs/extras - **done**

* Adjust "debs" option of CLEAN_LEVEL to delete old packages in "extras" subdirectory

* Add a code to check if package exists / package needs (re)building - **done**

* Add logging to file for build process - **done**

### All packages:

* Add sunxi-mali package if BLOBs license allows redistribution, otherwise create an installer like oracle-jdk - **done**

* Add hostapd-realtek package - copy of hostapd with realtek-specific patches - **done**

* Delete unused files (i.e. \*.lintian-overrides) - **done***

* Add missing udev rules to appropriate packages - **done**

```
KERNEL=="disp", MODE="0660", GROUP="video"
KERNEL=="cedar_dev", MODE="0660", GROUP="video"
KERNEL=="ump", MODE="0660", GROUP="video"
KERNEL=="mali", MODE="0660", GROUP="video"
```


### Package-specific:

* ffmpeg: disable building documentation - **done**

* ffmpeg: disable unused features - **done**

* mpv: disable unused features **done**

* libvdpau-sunxi: select branch (master or dev)

* libcsptr-dev: upgrade to debhelper version 9 - **done**

## Note
libcedrus compiled without USE_UMP=1 requires access to /dev/ion
