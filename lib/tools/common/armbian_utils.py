#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
import concurrent
import concurrent.futures
import glob
import json
import logging
import multiprocessing
import os
import re
import subprocess
import sys
from pathlib import Path

REGEX_WHITESPACE_LINEBREAK_COMMA_SEMICOLON = r"[\s,;\n]+"

ARMBIAN_CONFIG_REGEX_KERNEL_TARGET = r"^([export |declare -g]+)?KERNEL_TARGET=\"(.*)\""

log: logging.Logger = logging.getLogger("armbian_utils")


def parse_env_for_tokens(env_name):
	result = []
	# Read the environment; if None, return an empty	 list.
	val = os.environ.get(env_name, None)
	if val is None:
		return result
	# tokenize val; split by whitespace, line breaks, commas, and semicolons.
	tokens = re.split(REGEX_WHITESPACE_LINEBREAK_COMMA_SEMICOLON, val)
	# trim whitespace from tokens.
	return [token for token in [token.strip() for token in (tokens)] if token != ""]


def get_from_env(env_name, default=None):
	value = os.environ.get(env_name, default)
	if value is not None:
		value = value.strip()
	return value


def get_from_env_or_bomb(env_name):
	value = get_from_env(env_name)
	if value is None:
		raise Exception(f"{env_name} environment var not set")
	if value == "":
		raise Exception(f"{env_name} environment var is empty")
	return value


def yes_or_no_or_bomb(value):
	if value == "yes":
		return True
	if value == "no":
		return False
	raise Exception(f"Expected yes or no, got {value}")


def show_incoming_environment():
	log.debug("--ENV-- Environment:")
	for key in os.environ:
		log.debug(f"--ENV-- {key}={os.environ[key]}")


def is_debug():
	return get_from_env("LOG_DEBUG") == "yes"


def setup_logging():
	try:
		import coloredlogs
		level = "INFO"
		if is_debug():
			level = "DEBUG"
		format = "%(message)s"
		styles = {
			'trace': {'color': 'white', 'bold': False},
			'debug': {'color': 'white', 'bold': False},
			'info': {'color': 'green', 'bold': True},
			'warning': {'color': 'yellow', 'bold': True},
			'error': {'color': 'red'},
			'critical': {'bold': True, 'color': 'red'}
		}
		coloredlogs.install(level=level, stream=sys.stderr, isatty=True, fmt=format, level_styles=styles)
	except ImportError:
		level = logging.INFO
		if is_debug():
			level = logging.DEBUG
		logging.basicConfig(level=level, stream=sys.stderr)


def parse_json(json_contents_str):
	import json
	return json.loads(json_contents_str)


def to_yaml(gha_workflow):
	import yaml
	return yaml.safe_dump(gha_workflow, explicit_start=True, default_flow_style=False, sort_keys=False, allow_unicode=True, indent=2, width=1000)


# I've to read the first line from the board file, that's the hardware description in a pound comment.
# Also, 'KERNEL_TARGET="legacy,current,edge"' which we need to parse.
def armbian_parse_board_file_for_static_info(board_file, board_id):
	file_handle = open(board_file, 'r')
	file_lines = file_handle.readlines()
	file_handle.close()

	file_lines.reverse()
	hw_desc_line = file_lines.pop()
	hw_desc_clean = None
	if hw_desc_line.startswith("# "):
		hw_desc_clean = hw_desc_line.strip("# ").strip("\n")

	# Parse KERNEL_TARGET line.
	kernel_targets = None
	kernel_target_matches = re.findall(ARMBIAN_CONFIG_REGEX_KERNEL_TARGET, "\n".join(file_lines), re.MULTILINE)
	if len(kernel_target_matches) == 1:
		kernel_targets = kernel_target_matches[0][1].split(",")

	ret = {"BOARD": board_id, "BOARD_SUPPORT_LEVEL": (Path(board_file).suffix)[1:]}
	if hw_desc_clean is not None:
		ret["BOARD_FILE_HARDWARE_DESC"] = hw_desc_clean
	if kernel_targets is not None:
		ret["BOARD_POSSIBLE_BRANCHES"] = kernel_targets
	return ret


def armbian_get_all_boards_list(boards_path):
	ret = {}
	for file in glob.glob(boards_path + "/*.*"):
		stem = Path(file).stem
		if stem != "README":
			ret[stem] = file
	return ret


def find_armbian_src_path():
	# Find the location of compile.sh, relative to this Python script.
	this_script_full_path = os.path.realpath(__file__)
	log.debug(f"Real path to this script: '{this_script_full_path}'")

	armbian_src_path = os.path.realpath(os.path.join(os.path.dirname(this_script_full_path), "..", "..", ".."))
	log.debug(f"Real path to Armbian SRC '{armbian_src_path}'")

	compile_sh_full_path = os.path.realpath(os.path.join(armbian_src_path, "compile.sh"))
	log.debug(f"Real path to compile.sh '{compile_sh_full_path}'")

	# Make sure it exists
	if not os.path.exists(compile_sh_full_path):
		raise Exception("Can't find compile.sh")

	core_boards_path = os.path.realpath(os.path.join(armbian_src_path, "config", "boards"))
	log.debug(f"Real path to core boards '{core_boards_path}'")

	# Make sure it exists
	if not os.path.exists(core_boards_path):
		raise Exception("Can't find config/boards")

	userpatches_boards_path = os.path.realpath(os.path.join(armbian_src_path, "userpatches", "config", "boards"))
	log.debug(f"Real path to userpatches boards '{userpatches_boards_path}'")
	has_userpatches_path = os.path.exists(userpatches_boards_path)

	return {"armbian_src_path": armbian_src_path, "compile_sh_full_path": compile_sh_full_path, "core_boards_path": core_boards_path,
			"userpatches_boards_path": userpatches_boards_path, "has_userpatches_path": has_userpatches_path}


def armbian_get_all_boards_inventory():
	armbian_paths = find_armbian_src_path()
	core_boards = armbian_get_all_boards_list(armbian_paths["core_boards_path"])

	# first, gather the board_info for every core board. if any fail, stop.
	info_for_board = {}
	for board in core_boards.keys():
		board_info = armbian_parse_board_file_for_static_info(core_boards[board], board)
		board_info["BOARD_CORE_OR_USERPATCHED"] = "core"
		# Core boards must have the KERNEL_TARGET defined.
		if "BOARD_POSSIBLE_BRANCHES" not in board_info:
			raise Exception(f"Core board '{board}' must have KERNEL_TARGET defined")
		info_for_board[board] = board_info

	# Now go for the userpatched boards. Those can be all-new, or they can be patches to existing boards.
	if armbian_paths["has_userpatches_path"]:
		userpatched_boards = armbian_get_all_boards_list(armbian_paths["userpatches_boards_path"])
		for uboard_name in userpatched_boards.keys():
			uboard = armbian_parse_board_file_for_static_info(userpatched_boards[uboard_name], uboard_name)
			uboard["BOARD_CORE_OR_USERPATCHED"] = "userpatched"
			is_new_board = not (uboard_name in info_for_board)
			if is_new_board:
				log.debug(f"Userpatched Board {uboard_name} is new")
				# New userpatched boards must have the KERNEL_TARGET defined.
				if "BOARD_POSSIBLE_BRANCHES" not in uboard:
					raise Exception(f"NEW userpatched board '{uboard_name}' must have KERNEL_TARGET defined")
				info_for_board[uboard_name] = uboard
			else:
				log.debug(f"Userpatched Board {uboard_name} is already in core boards")
				info_for_board[uboard_name] = {**info_for_board[uboard_name], **uboard}

	return info_for_board


def map_to_armbian_params(map_params, quote_params=False) -> list[str]:
	ret = []
	for param in map_params:
		ret.append(param + "=" + map_params[param])
	if quote_params:
		ret = ["'" + param + "'" for param in ret]  # single-quote each param...
	return ret


def armbian_run_command_and_parse_json_from_stdout(exec_cmd: list[str], params: dict):
	result = None
	logs = []
	try:
		log.debug(f"Start calling Armbian command: {' '.join(exec_cmd)}")
		result = subprocess.run(
			exec_cmd,
			stdout=subprocess.PIPE,
			check=True,
			universal_newlines=False,  # universal_newlines messes up bash encoding, don't use, instead decode utf8 manually;
			bufsize=-1,  # full buffering
			# Early (pre-param-parsing) optimizations for those in Armbian bash code, so use an ENV (not PARAM)
			env={
				"CONFIG_DEFS_ONLY": "yes",  # Dont do anything. Just output vars.
				"ANSI_COLOR": "none",  # Do not use ANSI colors in logging output, don't write to log files
				"WRITE_EXTENSIONS_METADATA": "no",  # Not interested in ext meta here
				"ALLOW_ROOT": "yes",  # We're gonna be calling it as root, so allow it @TODO not the best option
				"PRE_PREPARED_HOST": "yes"  # We're gonna be calling it as root, so allow it @TODO not the best option
			},
			stderr=subprocess.PIPE
		)
	except subprocess.CalledProcessError as e:
		# decode utf8 manually, universal_newlines messes up bash encoding
		logs = parse_log_lines_from_stderr(e.stderr)
		log.error(f"Error calling Armbian command: {' '.join(exec_cmd)}")
		log.error(f"Error details: params: {params} - return code: {e.returncode} - stderr: {'; '.join(logs[-5:])}")
		return {"in": params, "out": {}, "logs": logs, "config_ok": False}

	if result is not None:
		if result.stderr:
			logs = parse_log_lines_from_stderr(result.stderr)

	# parse the result.stdout as json.
	try:
		parsed = json.loads(result.stdout.decode("utf8"))
		info = {"in": params, "out": parsed, "config_ok": True}
		info["logs"] = logs
		return info
	except json.decoder.JSONDecodeError as e:
		log.error(f"Error parsing Armbian JSON: params: {params}, stderr: {'; '.join(logs[-5:])}")
		# return {"in": params, "out": {}, "logs": logs, "config_ok": False}
		raise e


def parse_log_lines_from_stderr(lines_stderr: str):
	# parse list, split by newline
	lines = lines_stderr.decode("utf8").split("\n")
	# trim lines, remove empty ones
	logs = [line.strip() for line in lines if line.strip()]
	# each line, split at the first ocurrence of two colons ("::")
	result = []
	for line in logs:
		line = line.strip()
		if not line:
			continue
		parts = line.split("::", 1)
		if len(parts) != 2:
			# very probably something that leaked out of logging manager, grab it
			result.append("[LEAKED]:" + line.strip())
			continue
		type = parts[0].strip()
		msg = parts[1].strip()
		# if type begins "err" or "warn" or "wrn":
		if type.startswith("err") or type.startswith("warn") or type.startswith("wrn"):
			# remove some redundant stuff we don't want
			if ("Exiting with error " in msg) or ("please wait for cleanups to finish" in msg):
				continue
			result.append(f"{type}: {msg}")
	return result


def gather_json_output_from_armbian(command: str, targets: list[dict]):
	armbian_paths = find_armbian_src_path()
	# now loop over gathered infos
	every_info = []
	use_parallel: bool = True
	if use_parallel:
		counter = 0
		total = len(targets)
		# get the number of processor cores on this machine
		max_workers = multiprocessing.cpu_count() * 2  # use double the number of cpu cores, that's the sweet spot
		log.info(f"Using {max_workers} workers for parallel processing.")
		with concurrent.futures.ProcessPoolExecutor(max_workers=max_workers) as executor:
			every_future = []
			for target in targets:
				counter += 1
				future = executor.submit(get_info_for_one_build, armbian_paths, command, target, counter, total)
				every_future.append(future)

			log.info(f"Submitted {len(every_future)} jobs to the parallel executor. Waiting for them to finish...")
			executor.shutdown(wait=True)
			log.info(f"All jobs finished!")

			for future in every_future:
				info = future.result()
				if info is not None:
					every_info.append(info)
	else:
		for target in targets:
			info = get_info_for_one_build(armbian_paths, command, target)
			if info is not None:
				every_info.append(info)

	return every_info


def get_info_for_one_build(armbian_paths: dict[str, str], command: str, params: dict, counter: int, total: int):
	try:
		try:
			sh: str = armbian_paths["compile_sh_full_path"]
			cmds: list[str] = ([sh] + [command] + map_to_armbian_params(params["vars"]) + params["configs"])
			parsed = armbian_run_command_and_parse_json_from_stdout(cmds, params)
			return parsed
		except BaseException as e:
			log.error(f"Failed get info for build '{command}' '{params}': '{e}'", exc_info=True)
			return {"ARMBIAN_CONFIG_OK": False, "PYTHON_INFO_ERROR": "{}".format(e), "INPUT": params}
	finally:
		if counter % 10 == 0:
			log.info(f"Processed {counter} / {total} targets.")
