#!/bin/bash

SRC="$(dirname "$(realpath "${BASH_SOURCE}")")"
# fallback for Trusty
[[ -z "${SRC}" ]] && SRC="$(pwd)"

REPOSITORY_PACKAGES="`wget -qO- https://apt.armbian.com/.packages.txt`"

REVISION="5.67" # all boards have same revision
MAINTAINER="Igor Pecovnik" # deb signature
MAINTAINERMAIL="igor@armbian.com" # deb signature
#EXTERNAL_NEW="compile"


#echo $SRC
DEST=$SRC/output
source config/packages/go.sh
