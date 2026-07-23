#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# From ROCKNIX (https://github.com/ROCKNIX/abl), (c) ROCKNIX contributors.
set -e

sha256sum -c /sdcard/rocknix_abl/SM8750/abl_signed-SM8750.elf

dd if="/sdcard/rocknix_abl/SM8750/abl_signed-SM8750.elf" of=/dev/block/by-name/abl_a bs=1M
dd if="/sdcard/rocknix_abl/SM8750/abl_signed-SM8750.elf" of=/dev/block/by-name/abl_b bs=1M
