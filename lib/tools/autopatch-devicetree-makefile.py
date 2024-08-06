# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹

# So this thing takes
# - an absolute path to a kernel check-ed out git tree (GIT_WORK_DIR=/Volumes/LinuxDev/mainline-kernel-3rd-party-rebase)
# - the relative path to a Device Tree directory (DT_REL_DIR=arch/arm64/boot/dts/amlogic)
# and will for the DT_REL_DIR:
# - find all the .dts files
# - find the Makefile
# It will then regex-parse the Makefile for the CONFIG_ARCH_xxx variable, find the preamble and postamble, and insert the DT files in between.

import logging

import common.armbian_utils as armbian_utils
import common.dt_makefile_patcher as dt_makefile_patcher

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("patching")

# Show the environment variables we've been called with
armbian_utils.show_incoming_environment()

GIT_WORK_DIR = armbian_utils.get_from_env("GIT_WORK_DIR", "/Volumes/LinuxDev/mainline-kernel-3rd-party-rebase")
DT_REL_DIR = armbian_utils.get_from_env("DT_REL_DIR", "arch/arm64/boot/dts/amlogic")

dt_makefile_patcher.auto_patch_dt_makefile(GIT_WORK_DIR, DT_REL_DIR)
