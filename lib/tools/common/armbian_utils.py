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
import shlex
import subprocess
from pathlib import Path

import sys

from common.term_colors import background_dark_or_light

REGEX_WHITESPACE_LINEBREAK_COMMA_SEMICOLON = r"[\s,;\n]+"

ARMBIAN_BOARD_CONFIG_REGEX_GENERIC = r"^(?!\s)(?:[export |declare \-g]?)+([A-Z0-9_]+)=(?:'|\")(.*)(?:'|\")"

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
		if background_dark_or_light() == 'light':
			styles = {
				'trace': {'color': 'black', 'bright': True},
				'debug': {'color': 'black', 'bright': True},
				'info': {'color': 'green', 'bold': True, 'faint': True},
				'warning': {'color': 'yellow', 'bold': True, 'faint': True},
				'error': {'color': 'red'},
				'critical': {'bold': True, 'color': 'red'}
			}
		else:
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
def armbian_parse_board_file_for_static_info(board_file, board_id, core_or_userpatched):
	file_handle = open(board_file, 'r')
	file_lines = file_handle.readlines()
	file_handle.close()

	file_lines.reverse()
	hw_desc_line = file_lines.pop()
	file_lines.reverse()
	hw_desc_clean = None
	if hw_desc_line.startswith("# "):
		hw_desc_clean = hw_desc_line.strip("# ").strip("\n")

	# Parse generic bash vars, with a horrendous regex.
	generic_vars = {}
	generic_var_matches = re.findall(ARMBIAN_BOARD_CONFIG_REGEX_GENERIC, "\n".join(file_lines), re.MULTILINE)
	for generic_var_match in generic_var_matches:
		generic_vars[generic_var_match[0]] = generic_var_match[1]

	kernel_targets = []
	if "KERNEL_TARGET" in generic_vars:
		kernel_targets = generic_vars["KERNEL_TARGET"].split(",")
	if (len(kernel_targets) == 0) or (kernel_targets[0] == ""):
		log.warning(f"KERNEL_TARGET not found in '{board_file}', syntax error?, missing quotes? stray comma?")

	maintainers = []
	if "BOARD_MAINTAINER" in generic_vars:
		maintainers = generic_vars["BOARD_MAINTAINER"].split(" ")
		maintainers = list(filter(None, maintainers))
	else:
		if core_or_userpatched == "core":
			log.warning(f"BOARD_MAINTAINER not found in '{board_file}', syntax error?, missing quotes? stray space? missing info?")

	board_has_video = True
	if "HAS_VIDEO_OUTPUT" in generic_vars:
		if generic_vars["HAS_VIDEO_OUTPUT"] == "no":
			board_has_video = False

	if "BOARDFAMILY" not in generic_vars:
		log.warning(f"BOARDFAMILY not found in '{board_file}', syntax error?, missing quotes?")

	# Add some more vars that are not in the board file, so we've a complete BOARD_TOP_LEVEL_VARS as well as first-level
	extras: list[dict[str, any]] = [
		{"name": "BOARD", "value": board_id},
		{"name": "BOARD_SUPPORT_LEVEL", "value": (Path(board_file).suffix)[1:]},
		{"name": "BOARD_FILE_HARDWARE_DESC", "value": hw_desc_clean},
		{"name": "BOARD_POSSIBLE_BRANCHES", "value": kernel_targets},
		{"name": "BOARD_MAINTAINERS", "value": maintainers},
		{"name": "BOARD_HAS_VIDEO", "value": board_has_video},
		{"name": "BOARD_CORE_OR_USERPATCHED", "value": core_or_userpatched}
	]

	# Append the extras to the generic_vars dict.
	for extra in extras:
		generic_vars[extra["name"]] = extra["value"]

	ret = {"BOARD_TOP_LEVEL_VARS": generic_vars}
	# Append the extras to the top-level.
	for extra in extras:
		ret[extra["name"]] = extra["value"]

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

	# userspace stuff
	core_distributions_path = os.path.realpath(os.path.join(armbian_src_path, "config", "distributions"))
	log.debug(f"Real path to core distributions '{core_distributions_path}'")
	# Make sure it exists
	if not os.path.exists(core_distributions_path):
		raise Exception("Can't find config/distributions")

	# Desktop YAMLs live in an external repo (armbian/configng) that is
	# fetched on demand into cache/sources/armbian-configng. If the cache
	# is present, expose the YAML directory and parser path; otherwise
	# the desktop inventory will come back empty (see
	# get_desktop_inventory_for_distro).
	configng_cache_dir = os.path.realpath(os.path.join(armbian_src_path, "cache", "sources", "armbian-configng"))
	configng_yaml_dir = os.path.join(configng_cache_dir, "tools", "modules", "desktops", "yaml")
	configng_parser = os.path.join(configng_cache_dir, "tools", "modules", "desktops", "scripts", "parse_desktop_yaml.py")
	if os.path.isdir(configng_yaml_dir) and os.path.isfile(configng_parser):
		log.debug(f"configng desktop YAMLs available at '{configng_yaml_dir}'")
	else:
		log.debug(f"configng desktop cache not fully present at '{configng_cache_dir}' — desktop inventory will be empty")
		configng_yaml_dir = None
		configng_parser = None

	userpatches_boards_path = os.path.realpath(os.path.join(armbian_src_path, "userpatches", "config", "boards"))
	log.debug(f"Real path to userpatches boards '{userpatches_boards_path}'")
	has_userpatches_path = os.path.exists(userpatches_boards_path)

	return {
		"armbian_src_path": armbian_src_path, "compile_sh_full_path": compile_sh_full_path, "core_boards_path": core_boards_path,
		"core_distributions_path": core_distributions_path,
		"configng_yaml_dir": configng_yaml_dir, "configng_parser": configng_parser,
		"userpatches_boards_path": userpatches_boards_path, "has_userpatches_path": has_userpatches_path
	}


def read_one_distro_config_file(filename):
	# Read the contents of filename passed in and return it as string, trimmed
	with open(filename, 'r') as file_handle:
		file_contents = file_handle.read()
		return file_contents.strip()


def split_commas_and_clean_into_list(string):
	ret = []
	for item in string.split(","):
		item = item.strip()
		if item != "":
			ret.append(item)
	return ret


def get_desktop_inventory_for_distro(distro, armbian_paths):
	"""Return [{id, support, arches}, ...] for every first-tier supported
	DE that declares a release block for `distro` in configng's YAML
	matrix.

	Only `status: supported` DEs participate in the auto-generated build
	matrix. `community` DEs are reachable interactively (EXPERT mode
	dialog) or explicitly (DESKTOP_ENVIRONMENT=...) but are not enumerated
	here. `unsupported` DEs are vendor-specific and never enumerated."""
	ret = []
	yaml_dir = armbian_paths.get("configng_yaml_dir")
	parser = armbian_paths.get("configng_parser")
	if yaml_dir is None or parser is None:
		# configng not fetched yet — inventory is empty. cli-jsoninfo.sh
		# calls fetch_from_repo before invoking userspace-inventory.py
		# so this only trips on ad-hoc Python runs.
		return ret

	# Any arch works for --list-json; each JSON entry carries its own
	# per-release `architectures` list regardless of the arg we pass.
	try:
		proc = subprocess.run(
			[sys.executable, parser, yaml_dir, "--list-json", distro, "amd64", "--filter", "all"],
			capture_output=True, text=True, check=False, timeout=30,
		)
	except subprocess.TimeoutExpired:
		log.warning(f"parse_desktop_yaml.py timed out for distro '{distro}'")
		return ret

	if proc.returncode != 0:
		log.warning(f"parse_desktop_yaml.py failed for distro '{distro}': {proc.stderr.strip()}")
		return ret

	try:
		entries = json.loads(proc.stdout) if proc.stdout.strip() else []
	except json.JSONDecodeError as e:
		log.warning(f"parse_desktop_yaml.py returned non-JSON for distro '{distro}': {e}")
		return ret

	for entry in entries:
		status = entry.get("status", "unsupported")
		# Only first-tier supported DEs participate in the auto-
		# generated build matrix. `community` DEs are still installable
		# end-to-end (dialog EXPERT mode, CLI with DESKTOP_ENVIRONMENT=…)
		# but shouldn't generate CI targets by default — leave that
		# choice to the operator.
		if status != "supported":
			continue
		arches = entry.get("architectures") or []
		if not arches:
			# DE doesn't declare this release at all; skip silently.
			continue
		ret.append({
			"id": entry.get("name", ""),
			"support": status,
			"arches": arches,
		})

	return ret


def armbian_get_all_userspace_inventory():
	armbian_paths = find_armbian_src_path()
	distros_path = armbian_paths["core_distributions_path"]
	all_distros = []
	# find and loop over every directory in distros_path, including symlinks
	for distro in os.listdir(distros_path):
		one_distro_path = os.path.join(distros_path, distro)
		if not os.path.isdir(one_distro_path):
			continue
		log.debug(f"Processing distro '{distro}'")
		support_file_path = os.path.join(one_distro_path, "support")
		arches_file_path = os.path.join(one_distro_path, "architectures")
		name_file_path = os.path.join(one_distro_path, "name")
		distro_main_info = {
			"id": distro,
			"name": read_one_distro_config_file(name_file_path),
			"support": read_one_distro_config_file(support_file_path),
			"arches": split_commas_and_clean_into_list(read_one_distro_config_file(arches_file_path)),
			"desktops": get_desktop_inventory_for_distro(distro, armbian_paths)
		}
		all_distros.append(distro_main_info)

	return all_distros


# ARCH is declared per-family in config/sources/families/<BOARDFAMILY>.conf —
# but many families delegate to a shared include (e.g. meson-g12b.conf sources
# meson64_common.inc which then sets ARCH=arm64). Rather than hand-write a
# mini-bash to follow `source` directives, just bash-source the family file
# in a throwaway subshell and print ARCH. Cache results per family — there
# are ~60 unique families across ~370 boards.
_family_arch_cache: dict = {}


def armbian_get_arch_for_family(family_name, armbian_src_path):
	"""Return the ARCH declared by config/sources/families/<family>.conf
	(after resolving any `source` includes), or None if the file or the
	ARCH declaration is missing. Result is cached per family."""
	if not family_name:
		return None
	if family_name in _family_arch_cache:
		return _family_arch_cache[family_name]
	family_file = os.path.join(armbian_src_path, "config", "sources", "families", f"{family_name}.conf")
	arch = None
	if os.path.isfile(family_file):
		# Set ARCH via the EXIT trap so we still capture it even if the
		# family conf aborts mid-source via `${FOO:?error}` on a required
		# var that wouldn't be set in this minimal context (ls1046a, etc).
		bash_code = (
			"( trap 'printf \"%s\" \"${ARCH:-}\"; exit 0' EXIT; "
			"source " + shlex.quote(family_file) + " >/dev/null 2>&1 )"
		)
		try:
			proc = subprocess.run(
				["bash", "-c", bash_code],
				capture_output=True, text=True, timeout=5, check=False,
			)
			value = (proc.stdout or "").strip()
			if value and re.match(r"^[a-zA-Z0-9_]+$", value):
				arch = value
		except (subprocess.TimeoutExpired, OSError) as e:
			log.debug(f"Could not resolve ARCH for family '{family_name}': {e}")
	_family_arch_cache[family_name] = arch
	return arch


def armbian_get_all_boards_inventory():
	armbian_paths = find_armbian_src_path()
	core_boards = armbian_get_all_boards_list(armbian_paths["core_boards_path"])

	# first, gather the board_info for every core board. if any fail, stop.
	info_for_board = {}
	for board in core_boards.keys():
		board_info = armbian_parse_board_file_for_static_info(core_boards[board], board, "core")
		# Core boards must have the KERNEL_TARGET defined.
		if "BOARD_POSSIBLE_BRANCHES" not in board_info:
			raise Exception(f"Core board '{board}' must have KERNEL_TARGET defined")
		info_for_board[board] = board_info

	# Now go for the userpatched boards. Those can be all-new, or they can be patches to existing boards.
	if armbian_paths["has_userpatches_path"]:
		userpatched_boards = armbian_get_all_boards_list(armbian_paths["userpatches_boards_path"])
		for uboard_name in userpatched_boards.keys():
			uboard = armbian_parse_board_file_for_static_info(userpatched_boards[uboard_name], uboard_name, "userpatched")
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

	# Resolve ARCH per-board. Prefer an explicit board-level ARCH
	# declaration (picked up by the generic board-file regex into
	# BOARD_TOP_LEVEL_VARS); fall back to the family conf so boards
	# that inherit their arch transitively (most of them) don't need
	# the redundant declaration. Targets compositors use this to drop
	# matrix invocations where board arch doesn't match the requested
	# release's arch list (e.g. noble without loong64) instead of
	# relying on compile.sh to reject the combo downstream.
	for board, info in info_for_board.items():
		top_vars = info.get("BOARD_TOP_LEVEL_VARS", {})
		arch = top_vars.get("ARCH")
		if not arch:
			family = top_vars.get("BOARDFAMILY")
			arch = armbian_get_arch_for_family(family, armbian_paths["armbian_src_path"])
			if arch:
				top_vars["ARCH"] = arch
		if arch:
			info["ARCH"] = arch
		else:
			log.warning(f"Could not resolve ARCH for board '{board}' (family '{top_vars.get('BOARDFAMILY')}')")

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
		if e.returncode == 44:
			# special handling for exit_with_target_not_supported_error() in armbian core.
			log.warning(f"Skipped target: {' '.join(exec_cmd)}")
			log.warning(f"Skipped target details 1: {'; '.join(logs[-5:])}")
			return {"in": params, "out": {}, "logs": logs, "config_ok": False, "target_not_supported": True}
		else:
			log.error(f"Error calling Armbian command: {' '.join(exec_cmd)}")
			log.error(f"Error details 1: params: {params}")
			log.error(f"Error details 2: code: {e.returncode} - {'; '.join(logs[-5:])}")
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
		max_workers = multiprocessing.cpu_count() * 4  # use four times the number of cpu cores, that's the sweet spot
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
