#!/bin/bash

BOARD="orangepipcplus"

./compile.sh KERNEL_ONLY="no" KERNEL_CONFIGURE="no" BUILD_DESKTOP="no" BUILD_ALL="no" BOARD="$BOARD" BRANCH="next" RELEASE="stretch"

