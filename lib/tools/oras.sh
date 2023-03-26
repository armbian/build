#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/

set -e

SRC="$(
	cd "$(dirname "$0")/../.."
	pwd -P
)"

# shellcheck source=lib/single.sh
source "${SRC}"/lib/single.sh

# initialize logging variables.
logging_init

run_tool_oras "$@"
