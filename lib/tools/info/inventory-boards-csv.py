#!/usr/bin/env python3

# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023,2024 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
import collections.abc
import json
import logging
import os

import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from common import armbian_utils

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("info-gatherer-image")


def eprint(*args, **kwargs):
	print(*args, file=sys.stderr, **kwargs)


def flatten(d, parent_key='', sep='_'):
	items = []
	for k, v in d.items():
		new_key = parent_key + sep + k if parent_key else k
		if isinstance(v, collections.abc.MutableMapping):
			items.extend(flatten(v, new_key, sep=sep).items())
		else:
			items.append((new_key, v))
	return dict(items)


# read json from filename

# if ran with an argument, use it:
filename = None
if len(sys.argv) > 1:
	filename = sys.argv[1]
	with open(filename) as f:
		json_object = json.load(f)
	log.info("Loaded {} objects from file...".format(len(json_object)))
else:  # load from stdin
	log.info("Reading from stdin...")
	json_object = json.load(sys.stdin)
	log.info("Loaded {} objects from stdin...".format(len(json_object)))

flat = []
for obj in json_object:
	flat.append(flatten(obj, '', '.'))

columns_map = {}
for obj in flat:
	# get the string keys
	for key in obj.keys():
		value = obj[key]
		if type(value) == str:
			columns_map[key] = True
		if type(value) == bool:
			columns_map[key] = True

columns = columns_map.keys()

log.info("size of columns: {}".format(len(columns)))
log.info("columns: {}".format((columns)))

# Now, find the columns of which all values are the same
# and remove them
columns_to_remove = []
for column in columns:
	values = []
	for obj in flat:
		value = obj.get(column)
		values.append(value)
	if len(set(values)) == 1:
		columns_to_remove.append(column)

eprint("columns with all-identical values: {}: '{}'".format(len(columns_to_remove), columns_to_remove))

# Now actually filter columns, removing columns_to_remove
columns = [column for column in columns if column not in columns_to_remove]

# Actually remove the columns from the objects as well.
for obj in flat:
	for column in columns_to_remove:
		del obj[column]

# Now, group by 'in.inventory.BOARD' field
flat_grouped_by_board: dict[str, list[dict[str, str]]] = {}
for obj in flat:
	# if 'out.BOOT_SOC' not in obj:
	#	continue
	board = obj['in.inventory.BOARD']
	if board not in flat_grouped_by_board:
		flat_grouped_by_board[board] = []
	flat_grouped_by_board[board].append(obj)

log.info(f"Grouped by board: {flat_grouped_by_board.keys()}")

unique_boards: list[str] = flat_grouped_by_board.keys()

board_info: dict[str, dict[str, str]] = {}

# Now, for each unique board, find the columns of which all values are the same in that group.
for board in unique_boards:
	flats_for_board = flat_grouped_by_board[board]
	columns_to_keep = []
	forced_values = {}
	for column in columns:
		# Skip if column begins with 'in.inventory.BOARD_TOP_LEVEL_VARS'
		if column.startswith('in.inventory.BOARD_TOP_LEVEL_VARS'):
			continue
		values = []
		for obj in flats_for_board:
			value = obj.get(column)
			if value is None or value == "":
				continue
			values.append(str(value))
		set_of_values = set(values)
		num_diff_values = len(set_of_values)
		if num_diff_values == 1:
			columns_to_keep.append(column)
		elif num_diff_values > 0:
			forced_values[column] = "<<varies>> " + " /// ".join(set_of_values)
		else:
			forced_values[column] = "<<none>>"
	# log.info(f"Board {board} has {len(columns_to_keep)} columns with all-identical values: {columns_to_keep}")
	# Now actually filter columns
	# make a copy of only the common columns
	obj = flats_for_board[0]  # use the first value, they're all the same anyway
	obj_common = {}
	for column in columns_to_keep:
		if column in obj:
			obj_common[column] = obj[column]
		else:
			log.warning(f"Column {column} not found in first of board {board}!")
	for column in forced_values.keys():
		obj_common[column] = forced_values[column]
	# add to board_info
	board_info[board] = obj_common

common_columns: set[str] = set()
for board in board_info.keys():
	for key in board_info[board].keys():
		common_columns.add(key)

log.info(f"Common columns: {common_columns}")

# remove non-common columns from board_info
for board in board_info.keys():
	obj = board_info[board]
	for key in obj.keys():
		if key not in common_columns:
			del obj[key]

import csv

sorted_common_columns = sorted(common_columns)

handpicked_columns = [
	'in.inventory.BOARD',
	'in.inventory.BOARD_FILE_HARDWARE_DESC',
	'in.inventory.BOARD_SUPPORT_LEVEL',
	'out.BOARDFAMILY',
	'out.KERNEL_TARGET',
	'out.LINUXFAMILY',
	'out.BOARD_NAME',
	'out.BOARD_MAINTAINER',
	'out.ARCH',
	'out.BOOT_FDT_FILE',
	'out.BOOTCONFIG',
	'out.BOOT_SOC',
	'out.ATF_COMPILE',
	'out.KERNEL_MAJOR_MINOR',
	'out.BOOTBRANCH',
	'out.BOOT_SCENARIO',
	'out.OVERLAY_PREFIX'
]


def write_csv(writer, board_info):
	global board, obj
	writer.writeheader()
	for board in board_info.keys():
		obj = board_info[board]
		writer.writerow(obj)


if filename is not None:
	output_filename = filename + ".inventory.csv"
	log.info(f"Writing to {output_filename} ...")
	with open(output_filename, 'w') as csvfile:
		writer = csv.DictWriter(csvfile, fieldnames=handpicked_columns, extrasaction='ignore')
		write_csv(writer, board_info)
	log.info(f"Wrote to file {output_filename} ...")
else:
	writer = csv.DictWriter(sys.stdout, fieldnames=handpicked_columns, extrasaction='ignore')
	write_csv(writer, board_info)
	log.info("Wrote to stdout...")
