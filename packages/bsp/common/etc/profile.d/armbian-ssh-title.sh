#!/bin/sh
#
# Copyright (c) Authors: https://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

if [ -n "$PS1" ] && ( [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ] ); then
 tput tsl > /dev/null
 if [ "$?" -eq 0 ]; then
  echo `tput tsl` `whoami`@`hostname` `tput fsl`
 fi
fi