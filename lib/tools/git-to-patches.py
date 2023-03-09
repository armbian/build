#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
import os.path

# Let's use GitPython to query and manipulate the git repo
from git import Repo, GitCmdObjectDB

import common.armbian_utils as armbian_utils
import common.patching_utils as patching_utils

# Show the environment variables we've been called with
armbian_utils.show_incoming_environment()

# Parse env vars.
SRC = armbian_utils.get_from_env_or_bomb("SRC")
GIT_WORK_DIR = armbian_utils.get_from_env_or_bomb("GIT_WORK_DIR")
GIT_BRANCH = armbian_utils.get_from_env_or_bomb("GIT_BRANCH")
GIT_TARGET_REPLACE = armbian_utils.get_from_env("GIT_TARGET_REPLACE")
GIT_TARGET_SEARCH = armbian_utils.get_from_env("GIT_TARGET_SEARCH")

git_repo = Repo(GIT_WORK_DIR, odbt=GitCmdObjectDB)


BASE_GIT_REVISION = armbian_utils.get_from_env("BASE_GIT_REVISION")
BASE_GIT_TAG = armbian_utils.get_from_env("BASE_GIT_TAG")
if BASE_GIT_REVISION is None:
	if BASE_GIT_TAG is None:
		raise Exception("BASE_GIT_REVISION or BASE_GIT_TAG must be set")
	else:
		BASE_GIT_REVISION = git_repo.tags[BASE_GIT_TAG].commit.hexsha
		print(f"Found BASE_GIT_REVISION={BASE_GIT_REVISION} for BASE_GIT_TAG={BASE_GIT_TAG}")

# Using GitPython, get the list of commits between the HEAD of the branch and the base revision
# (which is either a tag or a commit)
git_commits = list(git_repo.iter_commits(f"{BASE_GIT_REVISION}..{GIT_BRANCH}"))


class ParsedPatch:
	def __init__(self, original_patch: str, sha1, title):
		self.sha1: str = sha1
		self.title: str = title
		self.original_patch: str = original_patch
		self.patch_diff: str | None = None
		self.original_header: str | None = None
		self.final_desc: str | None = None
		self.final_patch: str | None = None
		self.tags: dict[str, str] | None = None
		self.target_dir_fn: str | None = None
		self.target_dir: str | None = None
		self.target_filename: str | None = None
		self.target_counter: int | None = None

	def parse(self):
		# print(f"Patch: {patch}")
		self.original_header, self.patch_diff = patching_utils.PatchFileInDir.split_description_and_patch(
			self.original_patch)
		self.final_desc, self.tags = self.remove_tags_from_description(self.original_header)
		self.final_patch = self.final_desc + "\n---\n" + self.patch_diff
		# print(f"Description: ==={desc}===")
		# print(f"Diff: ==={diff}===")
		# print(f"Tags: {self.tags}")
		self.target_dir = self.tags.get("Patch-Rel-Directory", None)
		self.target_filename = self.tags.get("Patch-File", None)
		self.target_counter = int(self.tags.get("Patch-File-Counter", "0"))

	def remove_tags_from_description(self, desc: str) -> (str, dict[str, str]):
		tag_prefix = "X-Armbian: "
		ret_desc = []
		ret_tags = {}
		lines: list[str] = desc.splitlines()
		for line in lines:
			if line.startswith(tag_prefix):
				# remove the prefix
				line = line[len(tag_prefix):]
				tag, value = line.split(":", 1)
				ret_tags[tag.strip()] = value.strip()
			else:
				ret_desc.append(line)
		return "\n".join(ret_desc), ret_tags

	def prepare_target_dir_fn(self, search: "str | None", replace: "str | None"):
		if search is not None and replace is not None:
			self.target_dir = self.target_dir.replace(search, replace)
		self.target_dir_fn = self.target_dir + "/" + self.target_filename


parsed_patches: list[ParsedPatch] = []

for commit in git_commits:
	patch = patching_utils.export_commit_as_patch(git_repo, commit.hexsha)
	parsed = ParsedPatch(patch, commit.hexsha, commit.message.splitlines()[0])
	parsed.parse()
	parsed.prepare_target_dir_fn(GIT_TARGET_SEARCH, GIT_TARGET_REPLACE)
	parsed_patches.append(parsed)

# Now we have a list of parsed patches, each with its target dir, filename and counter.
for patch in parsed_patches:
	print(f"- Patch: target_dir_fn: {patch.target_dir_fn} counter: {patch.target_counter}")

# Now we need to sort the patches by target_dir_fn and counter
# We'll use a dict of lists, where the key is the target_dir_fn and the value is a list of patches
# with that target_dir_fn
patches_by_target_dir_fn: dict[str, list[ParsedPatch]] = {}
for patch in parsed_patches:
	if patch.target_dir_fn not in patches_by_target_dir_fn:
		patches_by_target_dir_fn[patch.target_dir_fn] = []
	patches_by_target_dir_fn[patch.target_dir_fn].append(patch)

# sort the patches by counter
for patches in patches_by_target_dir_fn.values():
	patches.sort(key=lambda p: p.target_counter)

# Show the stuff; write it to files, replacing
for target_dir_fn, patches in patches_by_target_dir_fn.items():
	print(f"Target dir/fn: {target_dir_fn}")
	full_target_file = os.path.join(SRC, f"{target_dir_fn}.patch")
	print(f"Writing to {full_target_file}")
	full_target_dir = os.path.dirname(full_target_file)
	if not os.path.exists(full_target_dir):
		os.makedirs(full_target_dir)
	with open(full_target_file, "w") as f:
		for patch in patches:
			print(f"  - Patch: {patch.target_counter}: '{patch.title}'")
			f.write(patch.final_patch)
