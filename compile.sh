#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of tool chain https://github.com/igorpecovnik/lib
#
#--------------------------------------------------------------------------------------------------------------------------------

# method
KERNEL_ONLY="no"					# build only kernel
SOURCE_COMPILE="yes"                       		# force source compilation: yes / no
KERNEL_CONFIGURE="no"                       		# want to change my default configuration
KERNEL_CLEAN="yes"                         		# run MAKE clean before kernel compilation

# user 
AFTERINSTALL=""						# last command before closing image, example: apt-get install joe
DEST_LANG="en_US.UTF-8"                     		# sl_SI.UTF-8, en_US.UTF-8
CONSOLE_CHAR="UTF-8"
ROOTPWD="1234"                          		# Must be changed @first login
MAINTAINER="Igor Pecovnik"                  # deb signature
MAINTAINERMAIL="igor.pecovnik@****l.com"    # deb signature
GPG_PASS=""									# signing password

# advanced
FBTFT="yes"                                 # https://github.com/notro/fbtft 
EXTERNAL="yes"                              # compile extra drivers`
FORCE_CHECKOUT="yes"						# igre manual changes to source
BUILD_ALL="no"								# cycle through selected boards and make images
#--------------------------------------------------------------------------------------------------------------------------------

# source is where we start the script
SRC=$(pwd)

# destination
DEST=$(pwd)/output                                      

# sources download
SOURCES=$(pwd)/sources

#--------------------------------------------------------------------------------------------------------------------------------
# To preserve proper librarires updating
#--------------------------------------------------------------------------------------------------------------------------------
if [ -f "main.sh" ] && [ -d "bin" ]; then 
	echo -e "[\e[0;31m error \x1B[0m] Copy this file one level up, alter and run again." 
	exit 
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Show warning for those who updated the script
#--------------------------------------------------------------------------------------------------------------------------------
if [ -d "$DEST/output" ]; then 
	echo -e "[\e[0;35m warn \x1B[0m] Structure has been changed. Remove all files and start in a clean directory. \
	CTRL-C to exit or any key to continue. Only sources will be doubled ..."
	read
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Get updates of the main build libraries
#--------------------------------------------------------------------------------------------------------------------------------
if [ -d "$SRC/lib" ]; then
    cd $SRC/lib
    git pull
else
    # download SDK
    git clone https://github.com/igorpecovnik/lib
fi


#--------------------------------------------------------------------------------------------------------------------------------
# Do we need to build all images
#--------------------------------------------------------------------------------------------------------------------------------
if [ "$BUILD_ALL" == "yes" ]; then
	source $SRC/lib/build-all.sh
else
	source $SRC/lib/main.sh
fi
