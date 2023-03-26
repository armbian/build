#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
import concurrent.futures
import glob
import json
import os
import re
import subprocess
import sys
import traceback
from pathlib import Path


def eprint(*args, **kwargs):
	print(*args, file=sys.stderr, **kwargs)


def get_all_boards_list_from_armbian(src_path):
	ret = {}
	for file in glob.glob(src_path + "/config/boards/*.*"):
		stem = Path(file).stem
		if stem != "README":
			ret[stem] = file
	# return ret
	return ret


def armbian_value_parse_simple(value, armbian_src_path):
	# return value.replace(armbian_src_path, "${SRC}")
	return value


def armbian_value_parse_list(item_value, delimiter, armbian_src_path):
	# return map(lambda x: armbian_value_parse_simple(x, armbian_src_path), item_value.split())
	ret = []
	for item in item_value.split(delimiter):
		ret.append(armbian_value_parse_simple(item, armbian_src_path))
	return ret


def armbian_value_parse_newline_map(item_value, armbian_src_path):
	lines = item_value.split("\n")
	ret = []
	for line in lines:
		ret.append(armbian_value_parse_list(line, ":", armbian_src_path))
	return ret


def map_to_armbian_params(map_params):
	ret = []
	for param in map_params:
		ret.append(param + "=" + map_params[param])
	return ret


def run_armbian_compile_and_parse(path_to_compile_sh, armbian_src_path, compile_params):
	exec_cmd = ([path_to_compile_sh] + ["config-dump"] + map_to_armbian_params(compile_params))
	# eprint("Running command: '{}' ", exec_cmd)
	result = None
	logs = ["Not available"]
	try:
		result = subprocess.run(
			exec_cmd,
			stdout=subprocess.PIPE, check=True, universal_newlines=True,
			env={
				"CONFIG_DEFS_ONLY": "yes",  # Dont do anything. Just output vars.
				"ANSI_COLOR": "none",  # Do not use ANSI colors in logging output
				"WRITE_EXTENSIONS_METADATA": "no"  # Not interested in ext meta here
			},
			stderr=subprocess.PIPE
		)
	except subprocess.CalledProcessError as e:
		lines_stderr = e.stderr.split("\n")
		eprint(
			"Error calling Armbian: params: {}, return code: {}, stderr: {}".format(
				compile_params, e.returncode,
				# the last 5 elements of lines_stderr, joined
				"; ".join(lines_stderr[-5:])
			)
		)
		return {"in": compile_params, "out": {}, "logs": lines_stderr, "config_ok": False}

	if result is not None:
		if result.stderr:
			# parse list, split by newline, remove armbian_src_path
			logs = armbian_value_parse_list(result.stderr, "\n", armbian_src_path)

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
			value = armbian_value_parse_list(value, " ", armbian_src_path)
		elif "_TARGET_MAP" in key:
			value = armbian_value_parse_newline_map(value, armbian_src_path)
		else:
			value = armbian_value_parse_simple(value, armbian_src_path)

		all_keys[key] = value

	info = {"in": compile_params, "out": all_keys, "config_ok": True}
	# info["logs"] = logs
	return info


# Find the location of compile.sh, relative to this Python script.
this_script_full_path = os.path.realpath(__file__)
# eprint("Real path to this script", this_script_full_path)

armbian_src_path = os.path.realpath(os.path.join(os.path.dirname(this_script_full_path), "..", ".."))
# eprint("Real path to Armbian SRC", armbian_src_path)

compile_sh_full_path = os.path.realpath(os.path.join(armbian_src_path, "compile.sh"))
# eprint("Real path to compile.sh", compile_sh_full_path)

# Make sure it exists
if not os.path.exists(compile_sh_full_path):
	raise Exception("Can't find compile.sh")

common_compile_params = {
	"BUILD_MINIMAL": "no",
	# "DEB_COMPRESS": "none",
	# "CLOUD_IMAGE": "yes",
	# "CLEAN_LEVEL": "debs",
	# "SHOW_LOG": "yes",
	# "SKIP_EXTERNAL_TOOLCHAINS": "yes",
	# "CONFIG_DEFS_ONLY": "yes",
	"KERNEL_CONFIGURE": "no",
	# "EXPERT": "yes"
}

board_compile_params = {
	"RELEASE": "jammy",
	"BUILD_DESKTOP": "no"
}


# I've to read the first line from the board file, that's the hardware description in a pound comment.
# Also, 'KERNEL_TARGET="legacy,current,edge"' which we need to parse.
def parse_board_file_for_static_info(board_file, board_id):
	file_handle = open(board_file, 'r')
	file_lines = file_handle.readlines()
	file_handle.close()

	file_lines.reverse()
	hw_desc_line = file_lines.pop()
	hw_desc_clean = hw_desc_line.strip("# ").strip("\n")

	# Parse KERNEL_TARGET line.
	kernel_target_matches = re.findall(r"^(export )?KERNEL_TARGET=\"(.*)\"", "\n".join(file_lines), re.MULTILINE)
	kernel_targets = kernel_target_matches[0][1].split(",")
	# eprint("Possible kernel branches for board: ", board_id, " : ", kernel_targets)

	return {
		"BOARD_FILE_HARDWARE_DESC": hw_desc_clean,
		"BOARD_POSSIBLE_BRANCHES": kernel_targets,
		"BOARD_DESC_ID": board_id
	}


def get_info_for_one_board(board_file, board_name, common_params, board_info, branch):
	# eprint(
	#	"Getting info for board '{}' branch '{}' in file '{}'".format(
	#		board_name, common_params["BRANCH"], board_file
	#	)
	# )

	board_info = board_info | {"BOARD_DESC_ID": f"{board_name}-{branch}"}

	# eprint("Running Armbian bash for board '{}'".format(board_name))
	try:
		parsed = run_armbian_compile_and_parse(compile_sh_full_path, armbian_src_path,
											   common_params | {"BOARD": board_name})
		# print(json.dumps(parsed, indent=4, sort_keys=True))
		return parsed | board_info
	except BaseException as e:
		eprint("Failed get info for board '{}': '{}'".format(board_name, e))
		traceback.print_exc()
		return board_info | {"ARMBIAN_CONFIG_OK": False, "PYTHON_INFO_ERROR": "{}".format(e)}


if True:
	all_boards = get_all_boards_list_from_armbian(armbian_src_path)
	# eprint(json.dumps(all_boards, indent=4, sort_keys=True))

	# first, gather the board_info for every board. if any fail, stop.
	info_for_board = {}
	for board in all_boards.keys():
		try:
			board_info = parse_board_file_for_static_info(all_boards[board], board)
			info_for_board[board] = board_info
		except BaseException as e:
			eprint("** Failed to parse board file {} static: {}".format(board, e))
			raise e
	# now loop over gathered infos
	every_info = []
	with concurrent.futures.ProcessPoolExecutor() as executor:  # max_workers=32
		every_future = []
		for board in all_boards.keys():
			board_info = info_for_board[board]
			for possible_branch in board_info["BOARD_POSSIBLE_BRANCHES"]:
				all_params = common_compile_params | board_compile_params | {"BRANCH": possible_branch}
				# eprint("Submitting future for board {} with BRANCH={}".format(board, possible_branch))
				future = executor.submit(get_info_for_one_board, all_boards[board], board, all_params,
										 board_info, possible_branch)
				every_future.append(future)

		eprint(f"Waiting for all {len(every_future)} configurations to be computed... this might take a long time.")
		executor.shutdown(wait=True)
		eprint("Done, all futures awaited")

		for future in every_future:
			info = future.result()
			if info is not None:
				every_info.append(info)

# info = get_info_for_one_board(board, all_params)
print(json.dumps(every_info, indent=4, sort_keys=True))
