#!/usr/bin/env python3

# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
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


json_object = json.load(sys.stdin)
eprint("Loaded {} objects from stdin...".format(len(json_object)))

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

eprint("columns: {}".format(len(columns)))

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

# eprint("columns with all-identical values: {}: '{}'".format(len(columns_to_remove), columns_to_remove))

# Now actually filter columns, removing columns_to_remove
columns = [column for column in columns if column not in columns_to_remove]

import csv

writer = csv.DictWriter(sys.stdout, fieldnames=columns, extrasaction='ignore')

writer.writeheader()
for obj in flat:
	writer.writerow(obj)

eprint("Done writing CSV to stdout.")
