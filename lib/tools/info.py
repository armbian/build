#!/bin/env python3
import concurrent.futures
import glob
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def eprint(*args, **kwargs):
	print(*args, file=sys.stderr, **kwargs)


def armbian_value_parse_list(item_value):
	return item_value.split()


def get_all_boards_list_from_armbian(src_path):
	ret = []
	for file in glob.glob(src_path + "/config/boards/*.*"):
		stem = Path(file).stem
		if stem != "README":
			ret.append(stem)
	return ret


def armbian_value_parse_newline_map(item_value):
	lines = item_value.split("\n")
	ret = []
	for line in lines:
		ret.append(line.split(";"))
	return ret


def map_to_armbian_params(map_params):
	ret = []
	for param in map_params:
		ret.append(param + "=" + map_params[param])
	return ret


def run_armbian_compile_and_parse(path_to_compile_sh, compile_params):
	result = subprocess.run(
		[path_to_compile_sh] + map_to_armbian_params(compile_params),
		stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True, universal_newlines=True
	)

	# Now parse it with regex-power!
	# regex = r"^declare (..) (.*?)=\"(.*?)\"$" # old multiline version
	regex = r"declare (..) (.*?)=\"(.*?)\""
	test_str = result.stdout
	matches = re.finditer(regex, test_str, re.DOTALL | re.MULTILINE)
	all_keys = {}

	for matchNum, match in enumerate(matches, start=1):
		flags = match.group(1)
		key = match.group(2)
		value = match.group(3)

		if ("_LIST" in key) or ("_DIRS" in key):
			value = armbian_value_parse_list(value)
		elif "_TARGET_MAP" in key:
			value = armbian_value_parse_newline_map(value)

		all_keys[key] = value

	return {"in": compile_params, "out": all_keys, "logs": result.stderr.split("\n")}


# Find the location of compile.sh, relative to this Python script.
this_script_full_path = os.path.realpath(__file__)
eprint("Real path to this script", this_script_full_path)

armbian_src_path = os.path.realpath(os.path.join(os.path.dirname(this_script_full_path), "..", ".."))
eprint("Real path to Armbian SRC", armbian_src_path)

compile_sh_full_path = os.path.realpath(os.path.join(armbian_src_path, "compile.sh"))
eprint("Real path to compile.sh", compile_sh_full_path)

# Make sure it exists
if not os.path.exists(compile_sh_full_path):
	raise Exception("Can't find compile.sh")

common_compile_params = {
	"KERNEL_ONLY": "no",
	"BUILD_MINIMAL": "no",
	"DEB_COMPRESS": "none",
	"CLOUD_IMAGE": "yes",
	"CLEAN_LEVEL": "debs",
	"SHOW_LOG": "yes",
	"CONFIG_DEFS_ONLY": "yes",
	"KERNEL_CONFIGURE": "no",
	"EXPERT": "yes"
}

board_compile_params = {
	"BOARD": "uefi-x86",
	"BRANCH": "current",
	"RELEASE": "impish",
	"BUILD_DESKTOP": "no"
}


def get_info_for_one_board(board_name, common_params):
	eprint("Getting info for board '{}'".format(board_name))
	try:
		parsed = run_armbian_compile_and_parse(compile_sh_full_path, common_params | {"BOARD": board_name})
		# print(json.dumps(parsed, indent=4, sort_keys=True))
		return parsed
	except:
		eprint("Failed get info for board '{}'".format(board_name))
		return None


if True:
	all_boards = get_all_boards_list_from_armbian(armbian_src_path)
	# print(json.dumps(all_boards, indent=4, sort_keys=True))

	every_info = []
	with concurrent.futures.ProcessPoolExecutor(max_workers=32) as executor:
		every_future = []
		for board in all_boards:
			all_params = common_compile_params | board_compile_params
			eprint("Submitting future for board {}".format(board))
			future = executor.submit(get_info_for_one_board, board, all_params)
			every_future.append(future)

		eprint("Waiting for all futures...")
		executor.shutdown(wait=True)
		eprint("Done, all futures awaited")

		for future in every_future:
			info = future.result()
			if info is not None:
				every_info.append(info)

# info = get_info_for_one_board(board, all_params)
print(json.dumps(every_info, indent=4, sort_keys=True))
