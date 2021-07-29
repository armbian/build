<h3>Desktop configuration</h3>

Please use lowercase letters for all config / folder files

```
├──${RELEASE}                                     The name of the distribution
│   ├──environments                               DE packages lists and scripts
│   │   ├──${DESKTOP_ENVIRONMENT}                 The name of the DE (xfce, gnome, kde, ...)
│   │   │   |──${DESKTOP_ENVIRONMENT_CONFIG_NAME} Different configuration name prefixed with "config_" (config_basic, config_full, ... )
│   │──appgroups                                  Application groups packages lists and scripts
│   │   ├──${DESKTOP_APPGROUPS_SELECTED}          Appgroups names (editors, programming, ...)
```

In each directory representing a desktop environment, a desktop environment configuration or an appgroup, the following files can be present :

* `packages`  
  If present, the content of the file will be added to the list
  of packages 'required' by the Armbian desktop package.
* `debian/postinst`  
  If present, the content of the file will be added to the `postinst`
  script of the Armbian desktop package, which will be executed after
  installing it.
* `armbian/create_desktop_package.sh`  
  If present the content of this script will be executed, by the build
  script, just before actually creating the Armbian Desktop `.deb`
  package.  
  Any variable recognized and function defined by the build script,
  at that point, can be used.
* `sources/apt`  
  If present, the directory will be scanned for `.source` files,
  which should contain APT URL, in a form that `add-apt-repository`
  understand.  
  The system is restricted to ONLY ONE APT URL per file, since it's
  basically calling :  
  `add-apt-repository $(cat "/that/apt/file.source")`  
  For each `.source` file parsed, if there's a corresponding
  `.source.gpg` file, the file will be considered as a package
  signing key and will be passed to `apt-key`.  
  For this one, the file is copied into `${SDCARD}/tmp` and then
  **apt-key** is called like this : `apt-key "/tmp/file.source.gpg"`.

Then in each directory representing a desktop environment, a desktop
environment configuration or an appgroup, you can add :

* `custom/boards/${BOARD}/`  
  For example `custom/orangepipc`.  
  A Board (odroidc4, tinkerboard, bananapi, ...) specific directory
  where you can provide additional`packages`, `debian/postinst` and
  `armbian/create_desktop_package.sh`. 
  The files, if present, will be parsed accordingly when building
  for that specific board, if the element (desktop environment,
  appgroup, ...) is selected.

Then in each appgroup, you can add :

* `custom/desktops/${DESTKOP_ENVIRONMENT}/`  
  For example `custom/desktops/xfce`.  
  A desktop environment specific directory where you can provide
  additional `packages`, `debian/postinst` and
  `armbian/create_desktop_package.sh`.  
  The files, if present, will be parsed accordingly if the appgroup
  AND that desktop environment are both selected during a build.
* `custom/boards/${BOARD}/custom/desktops/${DESTKOP_ENVIRONMENT}/`  
  For example `custom/boards/tinkerboard/custom/desktops/kde`.  
  A Board AND desktop environment specific directory where you can
  provided additional `packages`, `debian/postinst` and
  `armbian/create_desktop_package.sh`.  
  The files, if present, will be parsed accordingly if the appgroup,
  that specific board and that specific desktop environments are
  all selected during a build.

### Adding a desktop environment

> Currently, only official repositories are supported.

Let's say that you want to add that new desktop environment
"superduperde", that is now available on official on Debian/Ubuntu
repositories.

First, focus on one specific distribution like `focal` (Ubuntu)
or `buster` (Debian). In our example, will take `focal`.  
We'll create our first configuration 'full', which should provide the
DE along with all its specific apps, widgets and the kitchen sink.

* Create the directory
  `config/desktop/focal/environments/superduperde/config_full`
* Create the file 
  `config/desktop/focal/environments/superduperde/config_full/packages`
* Open the `packages` file, add the list of packages for `apt`.

Then select it in the configuration menu, or pass the following
variables to `./compile.sh` :

```bash
BUILD_DESKTOP="yes" RELEASE="focal" DESKTOP_ENVIRONMENT="superduperde" DESKTOP_ENVIRONMENT_CONFIG_NAME="config_full"
```

Then test the resulting image !

### Tips

Keep most complete configuration in latest stable versions (Ubuntu Focal and Ubuntu Buster) and link their sub-components / directories. The same goes for DE. We keep XFCE as a base and others linked to it - where this make sense.