# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹

import logging
import os
import re
import shutil

import git
from git import Actor

from common.patching_config import PatchingConfig
from common.patching_utils import PatchRootDir

log: logging.Logger = logging.getLogger("dt_makefile_patcher")


class AutoPatcherParams:
	def __init__(
		self,
		pconfig: PatchingConfig,
		git_work_dir: str,
		root_types_order: list[str],
		root_dirs_by_root_type: dict[str, list[PatchRootDir]],
		apply_patches_to_git: bool,
		git_repo: git.Repo):
		self.pconfig = pconfig
		self.git_work_dir = git_work_dir
		self.root_types_order = root_types_order
		self.root_dirs_by_root_type = root_dirs_by_root_type
		self.apply_patches_to_git = apply_patches_to_git
		self.git_repo = git_repo
		self.all_dt_files_copied: list[str] = []
		self.all_overlay_files_copied: list[str] = []


class AutomaticPatchDescription:
	def __init__(self):
		self.name = "Not initted name"
		self.description = "Not initted desc"
		self.files = []

	def rich_name_status(self):
		return f"[bold][blue]{self.name}"

	def rich_diffstats(self):
		files_bare = []
		max_files_to_show = 15  # show max 15
		for one_file in self.files[:max_files_to_show]:
			files_bare.append(os.path.basename(one_file))
		if len(self.files) > max_files_to_show:
			files_bare.append(f"and {len(self.files) - max_files_to_show} more")
		return ", ".join(files_bare)

	def rich_subject(self):
		return f"Armbian Autopatcher: {self.description}"


def auto_patch_dt_makefile(git_work_dir: str, dt_rel_dir: str, config_var: str, dt_files_to_add: list[str], incremental: bool) -> dict[str, str]:
	ret: dict[str, str] = {}
	dt_path = os.path.join(git_work_dir, dt_rel_dir)
	# Bomb if it does not exist or is not a directory
	if not os.path.isdir(dt_path):
		raise ValueError(f"DT_PATH={dt_path} is not a directory")
	makefile_path = os.path.join(dt_path, "Makefile")
	# Bomb if it does not exist or is not a file
	if not os.path.isfile(makefile_path):
		raise ValueError(f"MAKEFILE_PATH={makefile_path} is not a file")

	ret["MAKEFILE_PATH"] = makefile_path

	# Grab the contents of the Makefile
	with open(makefile_path, "r") as f:
		makefile_contents = f.read()
	log.info(f"Read {len(makefile_contents)} bytes from {makefile_path}")
	log.debug(f"Contents:\n{makefile_contents}")
	# Parse it into a list of lines
	makefile_lines = makefile_contents.splitlines()
	log.info(f"Read {len(makefile_lines)} lines from {makefile_path}")
	regex_dtb = r"(.*)\s(([a-zA-Z0-9-_]+)\.dtb)(.*)"
	regex_configopt = r"^dtb-\$\(([a-zA-Z0-9_]+)\)\s+"

	# For each line, check if it matches the regex_dtb, extract the groups
	line_counter = 0
	line_first_match = 0
	line_last_match = 0
	list_dts_basenames: list[str] = []
	list_configvars: list[str] = []
	for line in makefile_lines:
		line_counter += 1
		match_dtb = re.match(regex_dtb, line)
		match_configopt = re.match(regex_configopt, line)
		if match_dtb or match_configopt:
			line_first_match = line_counter if line_first_match == 0 else line_first_match
			line_last_match = line_counter
			if match_dtb:
				list_dts_basenames.append(match_dtb.group(3))
			if match_configopt:
				list_configvars.append(match_configopt.group(1))

	dict_dts_basenames = set(list_dts_basenames)  # reduce list to set
	# Sanity checks
	# SC: make sure dict_dts_basenames has at least one element
	if len(dict_dts_basenames) < 1:
		raise ValueError(
			f"dict_dts_basenames={dict_dts_basenames} -- found {len(dict_dts_basenames)} dtbs, expected more than zero in {makefile_path}")

	dict_configvars = set(list_configvars)  # reduce list to set
	# SC: make sure dict_configvars has exactly one element
	if len(dict_configvars) != 1:
		raise ValueError(f"dict_configvars={dict_configvars} -- found {len(dict_configvars)} configvars, expected exactly one in {makefile_path}")

	# Now compute the preambles and the postamble
	preamble_lines = makefile_lines[:line_first_match - 1]
	postamble_lines = makefile_lines[line_last_match:]

	dts_files = []
	if incremental:
		# For incremental, we'll just use the parsed-from-Makefile list of .dts files...
		for previously_in_makefile_dt in list_dts_basenames:
			log.debug(f"Adding {previously_in_makefile_dt} to the list of .dts files")
			dts_files.append(previously_in_makefile_dt)
		# ...and add the ones we copied. We're passed the list as parameter
		for one_dt_file in dt_files_to_add:
			log.debug(f"Adding newly-added DT {one_dt_file} to the list of .dts files")
			dts_files.append(one_dt_file[:-4])  # remove the .dts suffix
	else:
		# Find all .dts files in DT_PATH (not subdirectories), but add to the list without .dts suffix
		listdir: list[str] = os.listdir(dt_path)
		for file in listdir:
			if file.endswith(".dts"):
				dts_files.append(file[:-4])
		# sort the list. alpha-sort: `meson-sm1-a95xf3-air-gbit` should come sooner than `meson-sm1-a95xf3-air`? why?
		dts_files.sort()
		log.info(f"Found {len(dts_files)} .dts files in {dt_path}")
		# Show them all
		for dts_file in dts_files:
			log.debug(f"Found {dts_file}")

	# Create the mid-amble, which is the list of .dtb files to be built
	midamble_lines = []

	# If we've found an equal number of dtbs and configvars, means one-rule-per-dtb (arm64) style
	if len(list_dts_basenames) == len(list_configvars):
		ret["extra_desc"] = "one-rule-per-dtb (arm64) style"
		for dts_file in dts_files:
			midamble_lines.append(f"dtb-$({config_var}) += {dts_file}.dtb")
	# Otherwise one-rule-for-all-dtbs (arm 32-bit) style, where the last one hasn't a trailing backslash
	# Important, this requires 6.5-rc1's move to subdir-per-vendor and can't handle the all-in-one Makefile before it
	else:
		ret["extra_desc"] = "one-rule-for-all-dtbs (arm 32-bit) style"
		midamble_lines.append(f"dtb-$({config_var}) += \\")
		dtb_single_rule_list = []
		for dts_file in dts_files:
			dtb_single_rule_list.append(f"\t{dts_file}.dtb")
		midamble_lines.append(" \\\n".join(dtb_single_rule_list))

	# Late to the game: if DT_DIR/overlay/Makefile exists, add it.
	overlay_lines = []
	DT_OVERLAY_PATH = os.path.join(dt_path, "overlay")
	DT_OVERLAY_MAKEFILE_PATH = os.path.join(DT_OVERLAY_PATH, "Makefile")
	overlay_lines.append("")
	if os.path.isfile(DT_OVERLAY_MAKEFILE_PATH):
		if incremental:
			overlay_lines.append("# Armbian: Incremental: assuming overlay targets are already in the Makefile")
		else:
			ret["DT_OVERLAY_MAKEFILE_PATH"] = DT_OVERLAY_MAKEFILE_PATH
			ret["DT_OVERLAY_PATH"] = DT_OVERLAY_PATH
			overlay_lines.append("# Added by Armbian autopatcher for DT overlay")
			overlay_lines.append("subdir-y       := $(dts-dirs) overlay")

	# Now join the preambles, midamble, postamble and overlay stuff into a single list
	new_makefile_lines = preamble_lines + midamble_lines + postamble_lines + overlay_lines
	# Rewrite the Makefile with the new contents
	with open(makefile_path, "w") as f:
		f.write("\n".join(new_makefile_lines))
	log.info(f"Wrote {len(new_makefile_lines)} lines to {makefile_path}")

	if incremental:
		ret["extra_desc"] += " (incremental)"

	return ret


def copy_bare_files(autopatcher_params: AutoPatcherParams, type: str) -> list[AutomaticPatchDescription]:
	ret_desc_list: list[AutomaticPatchDescription] = []

	# group the pconfig.dts_directories by target dir
	dts_dirs_by_target = {}
	if type == "dt":
		config_dirs = autopatcher_params.pconfig.dts_directories
	elif type == "overlay":
		config_dirs = autopatcher_params.pconfig.overlay_directories
	else:
		raise ValueError(f"Unknown copy_bare_files::type {type}")

	for one_dts_dir in config_dirs:
		if one_dts_dir.target not in dts_dirs_by_target:
			dts_dirs_by_target[one_dts_dir.target] = []
		dts_dirs_by_target[one_dts_dir.target].append(one_dts_dir.source)

	# for each target....
	for target_dir in dts_dirs_by_target:
		all_files_to_copy = []
		dts_source_dirs = dts_dirs_by_target[target_dir]
		full_path_target_dir = os.path.join(autopatcher_params.git_work_dir, target_dir)
		if not os.path.exists(full_path_target_dir):
			os.makedirs(full_path_target_dir)

		for one_dts_dir in dts_source_dirs:
			for type_in_order in autopatcher_params.root_types_order:
				root_dirs = autopatcher_params.root_dirs_by_root_type[type_in_order]
				for root_dir in root_dirs:
					full_path_source = os.path.join(root_dir.abs_dir, one_dts_dir)
					log.debug(f"Will copy {full_path_source} to {full_path_target_dir}...")
					if not os.path.isdir(full_path_source):
						continue
					# get a list of regular files in the source directory
					files_to_copy = [
						os.path.join(full_path_source, f) for f in os.listdir(full_path_source)
						if os.path.isfile(os.path.join(full_path_source, f))
					]
					all_files_to_copy.extend(files_to_copy)
		# Create a dict of base filename -> list of full paths; this way userpatches with same name take precedence
		all_files_to_copy_dict = {}
		for one_file in all_files_to_copy:
			base_filename = os.path.basename(one_file)
			all_files_to_copy_dict[base_filename] = one_file
		# do the actual copy
		all_copied_files = []
		for one_file in all_files_to_copy_dict:
			log.debug(f"Copy '{one_file}' (from {all_files_to_copy_dict[one_file]}) to '{full_path_target_dir}'...")
			full_path_target_file = os.path.join(full_path_target_dir, one_file)
			shutil.copyfile(all_files_to_copy_dict[one_file], full_path_target_file)
			all_copied_files.append(full_path_target_file)
			if type == "dt":
				if one_file.endswith(".dts"):
					autopatcher_params.all_dt_files_copied.append(one_file)
			elif type == "overlay":
				autopatcher_params.all_overlay_files_copied.append(one_file)

		# If more than 0 files were copied, commit them if we're doing commits
		desc = AutomaticPatchDescription()
		desc.name = f"Armbian Bare {type.upper()} auto-patch"
		desc.description = f"Armbian Bare {type.upper()} files for {target_dir}"
		desc.files = all_copied_files
		ret_desc_list.append(desc)

		if autopatcher_params.apply_patches_to_git and len(all_copied_files) > 0:
			autopatcher_params.git_repo.git.add(all_copied_files)
			maintainer_actor: Actor = Actor(f"Armbian Bare {type.upper()} AutoPatcher", "patching@armbian.com")
			commit = autopatcher_params.git_repo.index.commit(
				message=f"Armbian Bare Device Tree files for {target_dir}"
				, author=maintainer_actor, committer=maintainer_actor, skip_hooks=True
			)
			log.info(f"Committed Bare {type.upper()} changes to git: {commit.hexsha} for {target_dir}")
			log.info(f"Done with Bare {type.upper()} autopatch commit for {target_dir}.")

	return ret_desc_list


def auto_patch_all_dt_makefiles(autopatcher_params: AutoPatcherParams) -> list[AutomaticPatchDescription]:
	ret_desc_list: list[AutomaticPatchDescription] = []
	for one_autopatch_config in autopatcher_params.pconfig.autopatch_makefile_dt_configs:
		log.warning(f"Autopatching DT Makefile in {one_autopatch_config.directory} with config '{one_autopatch_config.config_var}'...")
		autopatch_makefile_info = auto_patch_dt_makefile(
			autopatcher_params.git_work_dir, one_autopatch_config.directory, one_autopatch_config.config_var,
			autopatcher_params.all_dt_files_copied, one_autopatch_config.incremental
		)

		desc = AutomaticPatchDescription()
		desc.name = "Armbian DT Makefile auto-patch"
		desc.description = f"Armbian DT Makefile AutoPatch for {one_autopatch_config.directory}; {autopatch_makefile_info['extra_desc']}"
		desc.files = [autopatch_makefile_info["MAKEFILE_PATH"]]
		ret_desc_list.append(desc)

		if autopatcher_params.apply_patches_to_git:
			autopatcher_params.git_repo.git.add(autopatch_makefile_info["MAKEFILE_PATH"])
			maintainer_actor: Actor = Actor("Armbian DT Makefile AutoPatcher", "patching@armbian.com")
			commit = autopatcher_params.git_repo.index.commit(
				message=f"Armbian automatic DT Makefile patch for {one_autopatch_config.directory}",
				author=maintainer_actor, committer=maintainer_actor, skip_hooks=True
			)
			log.info(f"Committed changes to git: {commit.hexsha} for {one_autopatch_config.directory}")
			log.info(f"Done with Makefile autopatch commit for {one_autopatch_config.directory}.")
	return ret_desc_list
