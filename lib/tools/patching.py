#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
import logging
import os

import rich.box
# Let's use GitPython to query and manipulate the git repo
from git import Actor
from git import GitCmdObjectDB
from git import InvalidGitRepositoryError
from git import Repo

import common.armbian_utils as armbian_utils
import common.dt_makefile_patcher as dt_makefile_patcher
import common.patching_utils as patching_utils
from common.md_asset_log import SummarizedMarkdownWriter
from common.md_asset_log import get_gh_pages_workflow_script
from common.patching_config import PatchingConfig

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("patching")

# Show the environment variables we've been called with
armbian_utils.show_incoming_environment()

# @TODO: test that "patch --version" is >= 2.7.6 using a subprocess and parsing the output.

# Consts
CONST_CONFIG_YAML_FILE: str = '0000.patching_config.yaml'

# Let's start by reading environment variables.
# Those are always needed, and we should bomb if they're not set.
SRC = armbian_utils.get_from_env_or_bomb("SRC")
PATCH_TYPE = armbian_utils.get_from_env_or_bomb("PATCH_TYPE")
PATCH_DIRS_TO_APPLY = armbian_utils.parse_env_for_tokens("PATCH_DIRS_TO_APPLY")
APPLY_PATCHES = armbian_utils.get_from_env("APPLY_PATCHES")
PATCHES_TO_GIT = armbian_utils.get_from_env("PATCHES_TO_GIT")
REWRITE_PATCHES = armbian_utils.get_from_env("REWRITE_PATCHES")
SPLIT_PATCHES = armbian_utils.get_from_env("SPLIT_PATCHES")
ALLOW_RECREATE_EXISTING_FILES = armbian_utils.get_from_env("ALLOW_RECREATE_EXISTING_FILES")
GIT_ARCHEOLOGY = armbian_utils.get_from_env("GIT_ARCHEOLOGY")
FAST_ARCHEOLOGY = armbian_utils.get_from_env("FAST_ARCHEOLOGY")
apply_patches = APPLY_PATCHES == "yes"
apply_patches_to_git = PATCHES_TO_GIT == "yes"
git_archeology = GIT_ARCHEOLOGY == "yes"
fast_archeology = FAST_ARCHEOLOGY == "yes"
rewrite_patches_in_place = REWRITE_PATCHES == "yes"
split_patches = SPLIT_PATCHES == "yes"
apply_options = {
	"allow_recreate_existing_files": (ALLOW_RECREATE_EXISTING_FILES == "yes"),
	"set_patch_date": True,
}

# Those are optional.
GIT_WORK_DIR = armbian_utils.get_from_env("GIT_WORK_DIR")
BOARD = armbian_utils.get_from_env("BOARD")
TARGET = armbian_utils.get_from_env("TARGET")
USERPATCHES_PATH = armbian_utils.get_from_env("USERPATCHES_PATH")

# The exit exception, if any.
exit_with_exception: "Exception | None" = None

# Some path possibilities
CONST_PATCH_ROOT_DIRS = []

for patch_dir_to_apply in PATCH_DIRS_TO_APPLY:
	if USERPATCHES_PATH is not None:
		CONST_PATCH_ROOT_DIRS.append(
			patching_utils.PatchRootDir(
				f"{USERPATCHES_PATH}/{PATCH_TYPE}/{patch_dir_to_apply}", "user", PATCH_TYPE,
				USERPATCHES_PATH))

	# regular patchset
	CONST_PATCH_ROOT_DIRS.append(
		patching_utils.PatchRootDir(f"{SRC}/patch/{PATCH_TYPE}/{patch_dir_to_apply}", "core", PATCH_TYPE, SRC))

# Some sub-path possibilities:
CONST_PATCH_SUB_DIRS = []
if TARGET is not None:
	CONST_PATCH_SUB_DIRS.append(patching_utils.PatchSubDir(f"target_{TARGET}", "target"))
if BOARD is not None:
	CONST_PATCH_SUB_DIRS.append(patching_utils.PatchSubDir(f"board_{BOARD}", "board"))
CONST_PATCH_SUB_DIRS.append(patching_utils.PatchSubDir("", "common"))

# Prepare the full list of patch directories to apply
ALL_DIRS: list[patching_utils.PatchDir] = []
for patch_root_dir in CONST_PATCH_ROOT_DIRS:
	for patch_sub_dir in CONST_PATCH_SUB_DIRS:
		ALL_DIRS.append(patching_utils.PatchDir(patch_root_dir, patch_sub_dir, SRC))

# Group the root directories by root_type.
ROOT_DIRS_BY_ROOT_TYPE: dict[str, list[patching_utils.PatchRootDir]] = {}
for patch_root_dir in CONST_PATCH_ROOT_DIRS:
	if patch_root_dir.root_type not in ROOT_DIRS_BY_ROOT_TYPE:
		ROOT_DIRS_BY_ROOT_TYPE[patch_root_dir.root_type] = []
	ROOT_DIRS_BY_ROOT_TYPE[patch_root_dir.root_type].append(patch_root_dir)

# Search the root directories for a 0000.patching_config.yaml file. It can be either in core or userpatches, and if both found, they're merged.
CONST_ROOT_TYPES_CONFIG_ORDER = ['core', 'user']  # user patches configs are added last, so they override core patches configs.
all_yaml_config_files: list[str] = []
for root_type in CONST_ROOT_TYPES_CONFIG_ORDER:
	if root_type not in ROOT_DIRS_BY_ROOT_TYPE:
		continue
	for root_patch_dir in ROOT_DIRS_BY_ROOT_TYPE[root_type]:
		full_yaml_config_path = os.path.join(root_patch_dir.abs_dir, CONST_CONFIG_YAML_FILE)
		log.debug(f"Looking for config file: '{full_yaml_config_path}'")
		if os.path.isfile(full_yaml_config_path):
			log.info(f"Found patching config file: '{full_yaml_config_path}'")
			all_yaml_config_files.append(full_yaml_config_path)

# load the configs and merge them.
pconfig: PatchingConfig = PatchingConfig(all_yaml_config_files)

PATCH_FILES_FIRST: list[patching_utils.PatchFileInDir] = []
EXTRA_PATCH_FILES_FIRST: list[str] = armbian_utils.parse_env_for_tokens("EXTRA_PATCH_FILES_FIRST")
EXTRA_PATCH_HASHES_FIRST: list[str] = armbian_utils.parse_env_for_tokens("EXTRA_PATCH_HASHES_FIRST")

for patch_file in EXTRA_PATCH_FILES_FIRST:
	# if the file does not exist, bomb.
	if not os.path.isfile(patch_file):
		raise Exception(f"File {patch_file} does not exist.")

	# get the directory name of the file path
	patch_dir = os.path.dirname(patch_file)

	# Fabricate fake dirs...
	driver_root_dir = patching_utils.PatchRootDir(patch_dir, "extra-first", PATCH_TYPE, SRC)
	driver_sub_dir = patching_utils.PatchSubDir("", "extra-first")
	driver_dir = patching_utils.PatchDir(driver_root_dir, driver_sub_dir, SRC)
	driver_dir.is_autogen_dir = True
	PATCH_FILES_FIRST.append(patching_utils.PatchFileInDir(patch_file, driver_dir))

log.debug(f"Found {len(PATCH_FILES_FIRST)} kernel driver patches.")

SERIES_PATCH_FILES: list[patching_utils.PatchFileInDir] = []
# Now, loop over ALL_DIRS, and find the patch files in each directory
for one_dir in ALL_DIRS:
	if one_dir.patch_sub_dir.sub_type == "common":
		# Handle series; those are directly added to SERIES_PATCH_FILES which is not sorted.
		series_patches = one_dir.find_series_patch_files()
		if len(series_patches) > 0:
			log.debug(f"Directory '{one_dir.full_dir}' contains a series.")
			SERIES_PATCH_FILES.extend(series_patches)
	# Regular file-based patch files. This adds to the internal list.
	one_dir.find_files_patch_files()

# Gather all the PatchFileInDir objects into a single list
ALL_DIR_PATCH_FILES: list[patching_utils.PatchFileInDir] = []
for one_dir in ALL_DIRS:
	for one_patch_file in one_dir.patch_files:
		ALL_DIR_PATCH_FILES.append(one_patch_file)

ALL_DIR_PATCH_FILES_BY_NAME: dict[(str, patching_utils.PatchFileInDir)] = {}
for one_patch_file in ALL_DIR_PATCH_FILES:
	ALL_DIR_PATCH_FILES_BY_NAME[one_patch_file.file_name] = one_patch_file

# sort the dict by the key (file_name, sans dir...)
# We need a final, ordered list of patch files to apply.
# This reflects the order in which we want to apply the patches.
# For series-based patches, we want to apply the serie'd patches first.
# The other patches are separately sorted.
NORMAL_PATCH_FILES = list(dict(sorted(ALL_DIR_PATCH_FILES_BY_NAME.items())).values())
ALL_PATCH_FILES_SORTED = PATCH_FILES_FIRST + SERIES_PATCH_FILES + NORMAL_PATCH_FILES

patch_counter_desc_arr = []
if len(PATCH_FILES_FIRST) > 0:
	patch_counter_desc_arr.append(f"{len(PATCH_FILES_FIRST)} driver patches")
if len(SERIES_PATCH_FILES) > 0:
	patch_counter_desc_arr.append(f"{len(SERIES_PATCH_FILES)} patches in series")
if len(NORMAL_PATCH_FILES) > 0:
	patch_counter_desc_arr.append(f"{len(NORMAL_PATCH_FILES)} patches in regular, sorted files")
patch_file_desc = f"from {len(ALL_PATCH_FILES_SORTED)} files of which {', '.join(patch_counter_desc_arr)}"

# Now, actually read the patch files.
# Patch files might be in mailbox format, and in that case contain more than one "patch".
# It might also be just a unified diff, with no mailbox headers.
# We need to read the file, and see if it's a mailbox file; if so, split into multiple patches.
# If not, just use the whole file as a single patch.
# We'll store the patches in a list of Patch objects.
log.debug("Splitting patch files into patches")
VALID_PATCHES: list[patching_utils.PatchInPatchFile] = []
patch_file_in_dir: patching_utils.PatchFileInDir
has_critical_split_errors = False
for patch_file_in_dir in ALL_PATCH_FILES_SORTED:
	try:
		patches_from_file = patch_file_in_dir.split_patches_from_file()
		VALID_PATCHES.extend(patches_from_file)
	except Exception as e:
		has_critical_split_errors = True
		log.critical(
			f"Failed to read patch file {patch_file_in_dir.file_name}: {e}\n"
			f"Can't continue; please fix the patch file {patch_file_in_dir.full_file_path()} manually. Sorry."
		)

if has_critical_split_errors:
	raise Exception("Critical errors found while splitting patches. Please fix the patch files manually.")

log.debug("Done splitting patch files into patches")

# Now, some patches might not be mbox-formatted, or somehow else invalid. We can try and recover those.
# That is only possible if we're applying patches to git.
# Rebuilding description is only possible if we've the git repo where the patches themselves reside.
log.debug("Parsing patches...")
has_critical_parse_errors = False
for patch in VALID_PATCHES:
	try:
		patch.parse_patch()  # this handles diff-level parsing; modifies itself; throws exception if invalid
	except Exception as invalid_exception:
		has_critical_parse_errors = True
		log.critical(f"Failed to parse {patch.parent.full_file_path()}(:{patch.counter}): {invalid_exception}")
		log.critical(
			f"Can't continue; please fix the patch file {patch.parent.full_file_path()} manually;"
			f" check for possible double-mbox encoding. Sorry.")

if has_critical_parse_errors:
	raise Exception("Critical errors found while parsing patches. Please fix the patch files manually.")

log.debug(f"Parsed patches.")

# Now, for patches missing description, try to recover descriptions from the Armbian repo.
# It might be the SRC is not a git repo (say, when building in Docker), so we need to check.
if apply_patches_to_git and git_archeology:
	try:
		armbian_git_repo = Repo(SRC)
	except InvalidGitRepositoryError:
		armbian_git_repo = None
		log.warning(f"- SRC is not a git repo, so cannot recover descriptions from there.")
	if armbian_git_repo is not None:
		bad_archeology_hexshas = ["something"]

		for patch in VALID_PATCHES:
			if patch.subject is None:  # archeology only for patches without subject
				archeology_ok = patching_utils.perform_git_archeology(
					SRC, armbian_git_repo, patch, bad_archeology_hexshas, fast_archeology)
				if not archeology_ok:
					patch.problems.append("archeology_failed")

# Now, we need to apply the patches.
git_repo: "git.Repo | None" = None
total_patches = len(VALID_PATCHES)
any_failed_to_apply = False
failed_to_apply_list = []

if apply_patches:
	log.debug("Cleaning target git directory...")
	git_repo = Repo(GIT_WORK_DIR, odbt=GitCmdObjectDB)

	# Sanity check. It might be we fail to access the repo, or it's not a git repo, etc.
	status = str(git_repo.git.status()).replace("\n", "; ")
	GIT_WORK_DIR_REL_SRC = os.path.relpath(GIT_WORK_DIR, SRC)
	log.debug(f"Git status of '{GIT_WORK_DIR_REL_SRC}': '{status}'.")

	BRANCH_FOR_PATCHES = armbian_utils.get_from_env_or_bomb("BRANCH_FOR_PATCHES")
	BASE_GIT_REVISION = armbian_utils.get_from_env("BASE_GIT_REVISION")
	BASE_GIT_TAG = armbian_utils.get_from_env("BASE_GIT_TAG")
	if BASE_GIT_REVISION is None:
		if BASE_GIT_TAG is None:
			raise Exception("BASE_GIT_REVISION or BASE_GIT_TAG must be set")
		else:
			log.debug(f"Getting revision of BASE_GIT_TAG={BASE_GIT_TAG}")
			# first, try as a tag:
			try:
				BASE_GIT_REVISION = git_repo.tags[BASE_GIT_TAG].commit.hexsha
			except IndexError:
				# not a tag, try as a branch:
				try:
					BASE_GIT_REVISION = git_repo.branches[BASE_GIT_TAG].commit.hexsha
				except IndexError:
					raise Exception(f"BASE_GIT_TAG={BASE_GIT_TAG} is neither a tag nor a branch")

			log.debug(f"Found BASE_GIT_REVISION={BASE_GIT_REVISION} for BASE_GIT_TAG={BASE_GIT_TAG}")

	patching_utils.prepare_clean_git_tree_for_patching(git_repo, BASE_GIT_REVISION, BRANCH_FOR_PATCHES)

	# the autopatcher params
	autopatcher_params: dt_makefile_patcher.AutoPatcherParams = dt_makefile_patcher.AutoPatcherParams(
		pconfig, GIT_WORK_DIR, CONST_ROOT_TYPES_CONFIG_ORDER, ROOT_DIRS_BY_ROOT_TYPE, apply_patches_to_git, git_repo
	)

	# Loop over the VALID_PATCHES, and apply them
	log.info(f"Applying {total_patches} patches {patch_file_desc}...")
	# Grab the date of the root Makefile; that is the minimum date for the patched files.
	root_makefile = os.path.join(GIT_WORK_DIR, "Makefile")
	root_makefile_mtime = os.path.getmtime(root_makefile)
	apply_options["root_makefile_date"] = root_makefile_mtime
	log.debug(f"- Root Makefile '{root_makefile}' date: '{root_makefile_mtime}'")
	chars_total = len(str(total_patches))
	counter = 0
	for one_patch in VALID_PATCHES:
		counter += 1
		counter_str = str(counter).zfill(chars_total)

		log.info(f"-> {counter_str}/{total_patches}: {one_patch.str_oneline_around('', '')}")
		one_patch.applied_ok = False
		try:
			one_patch.apply_patch(GIT_WORK_DIR, apply_options)
			one_patch.applied_ok = True
		except Exception as e:
			log.error(f"Problem with {one_patch}: {e}")
			any_failed_to_apply = True
			failed_to_apply_list.append(one_patch)

		if one_patch.applied_ok and apply_patches_to_git:
			committed = one_patch.commit_changes_to_git(git_repo, (not rewrite_patches_in_place), split_patches, pconfig)

			if not split_patches:
				commit_hash = committed['commit_hash']
				one_patch.git_commit_hash = commit_hash

				if rewrite_patches_in_place:
					rewritten_patch = patching_utils.export_commit_as_patch(git_repo, commit_hash)
					one_patch.rewritten_patch = rewritten_patch

	if (not apply_patches_to_git) and (not rewrite_patches_in_place) and any_failed_to_apply:
		log.error(
			f"Failed to apply {len(failed_to_apply_list)} patches: {','.join([failed_patch.__str__() for failed_patch in failed_to_apply_list])}")
		exit_with_exception = Exception(f"Failed to apply {len(failed_to_apply_list)} patches.")

	# Include the dts/dtsi marked dts-directories in the config
	if pconfig.has_dts_directories:
		dt_makefile_patcher.copy_bare_files(autopatcher_params, "dt")

	# Include the overlay stuff
	if pconfig.has_dts_directories:
		dt_makefile_patcher.copy_bare_files(autopatcher_params, "overlay")

	# Autopatch the Makefile(s) according to the config
	if pconfig.has_autopatch_makefile_dt_configs:
		dt_makefile_patcher.auto_patch_all_dt_makefiles(autopatcher_params)

	if rewrite_patches_in_place:
		# Now; we need to write the patches to files.
		# loop over the patches, and group them by the parent; the parent is the PatchFileInDir object.
		patch_files_by_parent: dict[(patching_utils.PatchFileInDir, list[patching_utils.PatchInPatchFile])] = {}
		for one_patch in VALID_PATCHES:
			if not one_patch.applied_ok:
				log.warning(f"Skipping patch {one_patch} from rewrite because it was not applied successfully.")
				continue

			if one_patch.parent not in patch_files_by_parent:
				patch_files_by_parent[one_patch.parent] = []
			patch_files_by_parent[one_patch.parent].append(one_patch)
		parent: patching_utils.PatchFileInDir
		for parent in patch_files_by_parent:
			patches = patch_files_by_parent[parent]
			parent.rewrite_patch_file(patches)
		UNAPPLIED_PATCHES = [one_patch for one_patch in VALID_PATCHES if not one_patch.applied_ok]
		for failed_patch in UNAPPLIED_PATCHES:
			log.info(
				f"Consider removing {failed_patch.parent.full_file_path()}(:{failed_patch.counter}); "
				f"it was not applied successfully.")

# Create markdown about the patches
readme_markdown: "str | None" = None
with SummarizedMarkdownWriter(f"patching_{PATCH_TYPE}.md", f"{PATCH_TYPE} patching") as md:
	patch_count = 0
	patches_applied = 0
	patches_with_problems = 0
	problem_by_type: dict[str, int] = {}
	if total_patches == 0:
		md.write(f"- No patches found.\n")
	else:
		# Prepare the Markdown table header
		md.write(
			"| Status | Patch  | Diffstat Summary | Files patched | Author / Subject |\n")
		# Markdown table hyphen line and column alignment
		md.write("| :---:    | :---   | :---   | :---   | :---  |\n")
	for one_patch in VALID_PATCHES:
		# Markdown table row
		md.write(
			f"| {one_patch.markdown_problems()} | {one_patch.markdown_name()} | {one_patch.markdown_diffstat()} | {one_patch.markdown_link_to_patch()}{one_patch.markdown_files()} | {one_patch.markdown_author()} {one_patch.markdown_subject()} |\n")
		patch_count += 1
		if one_patch.applied_ok:
			patches_applied += 1
		if len(one_patch.problems) > 0:
			patches_with_problems += 1
			for problem in one_patch.problems:
				if problem not in problem_by_type:
					problem_by_type[problem] = 0
				problem_by_type[problem] += 1
	md.add_summary(f"{patch_count} total patches")
	md.add_summary(f"{patches_applied} applied")
	md.add_summary(f"{patches_with_problems} with problems")
	for problem in problem_by_type:
		md.add_summary(f"{problem_by_type[problem]} {problem}")
	# capture the markdown
	readme_markdown = md.get_readme_markdown()

# Finally, write the README.md and the GH pages workflow file to the git dir, add them, and commit them.
if apply_patches_to_git and readme_markdown is not None and git_repo is not None:
	log.debug("Writing README.md and .github/workflows/gh-pages.yml")
	with open(os.path.join(GIT_WORK_DIR, "README.md"), 'w') as f:
		f.write(readme_markdown)
	git_repo.git.add("README.md")
	github_workflows_dir = os.path.join(GIT_WORK_DIR, ".github", "workflows")
	if not os.path.exists(github_workflows_dir):
		os.makedirs(github_workflows_dir)
	with open(os.path.join(github_workflows_dir, "publish-ghpages.yaml"), 'w') as f:
		f.write(get_gh_pages_workflow_script())
	log.debug("Committing README.md and .github/workflows/gh-pages.yml")
	git_repo.git.add("-f", [".github/workflows/publish-ghpages.yaml", "README.md"])
	maintainer_actor: Actor = Actor("Armbian AutoPatcher", "patching@armbian.com")
	commit = git_repo.index.commit(
		message="Armbian patching summary README",
		author=maintainer_actor,
		committer=maintainer_actor,
		skip_hooks=True
	)
	log.info(f"Committed changes to git: {commit.hexsha}")
	log.info("Done with summary commit.")

# Use Rich.
from rich.console import Console
from rich.table import Table
from rich.syntax import Syntax

# console width is COLUMNS env var minus 12, or just 160 if GITHUB_ACTIONS env is not empty
console_width = (int(os.environ.get("COLUMNS", 160)) - 12) if os.environ.get("GITHUB_ACTIONS", "") == "" else 160
console = Console(color_system="standard", width=console_width, highlight=False)

# Use Rich to print a summary of the patches
if True:
	summary_table = Table(title=f"Summary of {PATCH_TYPE} patches", show_header=True, show_lines=True, box=rich.box.ROUNDED)
	summary_table.add_column("Patch / Status", overflow="fold", min_width=25, max_width=35)
	summary_table.add_column("Diffstat / files", max_width=35)
	summary_table.add_column("Author / Subject", overflow="ellipsis")
	for one_patch in VALID_PATCHES:
		summary_table.add_row(
			# (one_patch.markdown_name(skip_markdown=True)),  # + " " + one_patch.markdown_problems()
			one_patch.rich_name_status(),
			(one_patch.text_diffstats() + " " + one_patch.text_files()),
			(one_patch.text_author() + ": " + one_patch.text_subject())
		)
	console.print(summary_table)

# Use Rich to print a summary of the failed patches and their rejects
if any_failed_to_apply:
	summary_table = Table(title="Summary of failed patches", show_header=True, show_lines=True, box=rich.box.ROUNDED)
	summary_table.add_column("Patch", overflow="fold", min_width=5, max_width=20)
	summary_table.add_column("Patching output", overflow="fold", min_width=20, max_width=40)
	summary_table.add_column("Rejects")
	for one_patch in failed_to_apply_list:
		reject_compo = "No rejects"
		if one_patch.rejects is not None:
			reject_compo = Syntax(one_patch.rejects, "diff", line_numbers=False, word_wrap=True)

		summary_table.add_row(
			one_patch.rich_name_status(),
			one_patch.rich_patch_output(),
			reject_compo
		)
	console.print(summary_table)

if exit_with_exception is not None:
	raise exit_with_exception
