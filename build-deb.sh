#!/bin/bash

SRC="$(dirname "$(realpath "${BASH_SOURCE}")")"
# fallback for Trusty
[[ -z "${SRC}" ]] && SRC="$(pwd)"

REVISION="5.67$SUBREVISION" # all boards have same revision
ROOTPWD="1234" # Must be changed @first login
[[ -z $MAINTAINER ]] && MAINTAINER="Igor Pecovnik" # deb signature
[[ -z $MAINTAINERMAIL ]] && MAINTAINERMAIL="igor.pecovnik@****l.com" # deb signature

#echo $SRC
DEST=$SRC/output
source debs/go.sh
