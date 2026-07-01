#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Fix old U-Boot's pylibfdt build on modern hosts.
#
# distutils was removed from the Python stdlib in 3.12 (trixie ships 3.13), so
# old U-Boot's pylibfdt setup.py fails at:
#     from distutils.core import setup, Extension
#     ModuleNotFoundError: No module named 'distutils'
# setuptools provides drop-in setup + Extension (incl. swig_opts), so swap the
# import to setuptools. Also raw-string the RE_KEY_VALUE regex to silence the
# "invalid escape sequence '\w'" SyntaxWarning (a hard SyntaxError on newer
# Python). Both the old (lib/libfdt/pylibfdt) and newer (scripts/dtc/pylibfdt)
# locations are handled.
#
# Safe for all U-Boot versions: no-op when setup.py is absent or already uses
# setuptools. Can be removed once all BOOTBRANCH versions ship a setuptools-based
# pylibfdt setup.py.

function pre_config_uboot_target__fix_pylibfdt_distutils() {
	local sp patched=0
	for sp in lib/libfdt/pylibfdt/setup.py scripts/dtc/pylibfdt/setup.py; do
		[[ -f "${sp}" ]] || continue

		if grep -q '^from distutils' "${sp}"; then
			display_alert "Patching pylibfdt" "distutils -> setuptools in ${sp}" "info"
			# setuptools re-exports setup and Extension (with swig_opts support)
			sed -i \
				-e 's/^from distutils\.core import /from setuptools import /' \
				-e 's/^from distutils\.extension import /from setuptools import /' \
				"${sp}"
			patched=1
		fi

		# Raw-string the Makefile-parser regex to kill the '\w' SyntaxWarning.
		# Matches the single line regardless of which pylibfdt vintage it is.
		if grep -q "re\.compile('(?P<key>" "${sp}"; then
			sed -i "s/re\.compile('(?P<key>/re.compile(r'(?P<key>/" "${sp}"
			patched=1
		fi
	done

	[[ "${patched}" -eq 1 ]] && display_alert "pylibfdt" "patched for modern Python (no distutils)" "info"
	return 0
}
