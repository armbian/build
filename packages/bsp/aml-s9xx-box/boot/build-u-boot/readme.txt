The u-boot binary files originally included in this distribution are the 
ones originally built by @balbes150 as part of his former TV Box builds
based on work by @hexdump

We shouldn't be releasing binary blobs of unknown source code origin, 
however as these are what has been the norm for the amlogic TV box builds
in the past, we are continuing with that as the status quo, until something
better is put in place.

All of the u-boot binaries should be recreated from scratch and either built 
automatically as part of the Armbian build process, or at least instructions 
should be provided here as to how to rebuild them from source.

Update (3/13/23):
Instructions for building u-boot-s905x-s912 from source
(This is based on the work of @hexdump that can be found here:
https://github.com/hexdump0815/u-boot-misc/blob/master/readme.gxl)

git clone https://gitlab.denx.de/u-boot/u-boot.git/
cd u-boot
git checkout v2020.07
patch -p1 < /path/to/u-boot-s905x-s912.patch
make libretech-cc_defconfig
make
cp u-boot.bin u-boot-s905x-s912


Update (1/27/24):
Instructions for building u-boot-s905x2-s922 from source
(This is based on the work of @hexdump that can be found here:
https://github.com/hexdump0815/u-boot-misc/blob/master/readme.gxy)

git clone https://gitlab.denx.de/u-boot/u-boot.git/
cd u-boot
git checkout v2024.01
patch -p1 < /path/to/u-boot-s905x2-s922.patch
make sei510_defconfig
make
cp u-boot.bin u-boot-s905x2-s922


Update (1/28/24):
Instructions for building u-boot-s905x3 from source
(This is based on the work of @hexdump that can be found here:
https://github.com/hexdump0815/u-boot-misc/blob/master/readme.gxy)

git clone https://gitlab.denx.de/u-boot/u-boot.git/
cd u-boot
git checkout v2023.10
patch -p1 < /path/to/u-boot-s905x3.patch
make sei610_defconfig
make
cp u-boot.bin u-boot-s905x3

TODO: rebuild u-boot-s905 from source
TODO: automate the manual build process in the armbian build framework
