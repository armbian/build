#!/usr/bin/env python3
import collections.abc
import json
import sys


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

eprint("columns: {}".format(columns_map))

eprint("columns: {}".format(columns))

import csv

with open('boards_vs_branches.csv', 'w', newline='') as csvfile:
	fieldnames = columns
	writer = csv.DictWriter(csvfile, fieldnames=fieldnames, extrasaction='ignore')

	writer.writeheader()
	for obj in flat:
		writer.writerow(obj)
