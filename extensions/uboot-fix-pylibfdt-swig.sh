#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Fix old U-Boot's pylibfdt failing to build against SWIG >= 4.3
# (Debian trixie ships 4.3+).
#
# SWIG 4.3.0 gave SWIG_Python_AppendOutput() a third parameter (is_void),
# so the 2-argument calls in old pylibfdt SWIG interfaces no longer compile:
#
#   scripts/dtc/pylibfdt/libfdt_wrap.c: error: too few arguments to
#   function 'SWIG_Python_AppendOutput'
#
# Upstream (dtc/U-Boot >= v2026.07) switched to the version-agnostic
# SWIG_AppendOutput() macro. Do the same substitution at build time on the
# checked-in interface (libfdt.i / libfdt.i_shipped) and, if present, on an
# already-generated wrapper (libfdt_wrap.c), so SWIG regenerates a wrapper
# that compiles.
#
# Safe for all U-Boot versions: no-op when the old 2-arg call is absent.
# Handles both the old (lib/libfdt/pylibfdt) and new (scripts/dtc/pylibfdt)
# pylibfdt locations. Can be removed once all BOOTBRANCH versions ship the
# SWIG_AppendOutput() form (>= v2026.07).

function pre_config_uboot_target__fix_pylibfdt_swig() {
	local patched=0 f
	for f in \
		scripts/dtc/pylibfdt/libfdt.i \
		scripts/dtc/pylibfdt/libfdt.i_shipped \
		scripts/dtc/pylibfdt/libfdt_wrap.c \
		lib/libfdt/pylibfdt/libfdt.i \
		lib/libfdt/pylibfdt/libfdt.i_shipped \
		lib/libfdt/pylibfdt/libfdt_wrap.c; do

		[[ -f "${f}" ]] || continue
		# Only rewrite genuine 2-arg calls; the fixed 3-arg definition
		# 'SWIG_Python_AppendOutput(PyObject* result, PyObject* obj, int is_void)'
		# and any SWIG_AppendOutput() use are left untouched.
		grep -q 'SWIG_Python_AppendOutput(resultobj' "${f}" || continue

		display_alert "Patching pylibfdt" "SWIG_Python_AppendOutput -> SWIG_AppendOutput in ${f}" "info"
		sed -i 's/SWIG_Python_AppendOutput(resultobj/SWIG_AppendOutput(resultobj/g' "${f}"
		patched=1
	done

	[[ "${patched}" -eq 1 ]] && display_alert "pylibfdt" "patched for SWIG >= 4.3 (SWIG_AppendOutput)" "info"

	return 0
}
