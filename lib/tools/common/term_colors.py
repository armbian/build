#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2024 Darsey Litzenberger, dlitz@dlitz.net
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#

import os


def background_dark_or_light():
	"""
	Returns:
		'dark' if the terminal background is dark,
		'light' if the terminal background is light, or
		'' if the terminal background color is unknown.
	"""
	colorfgbg = os.environ.get("COLORFGBG", "")
	try:
		_, bg = colorfgbg.split(';')
		bg = int(bg)
	except ValueError:
		return ""
	if 0 <= bg <= 6 or bg == 8:
		return "dark"
	elif bg == 7 or 9 <= bg <= 15:
		return "light"
	return ""
