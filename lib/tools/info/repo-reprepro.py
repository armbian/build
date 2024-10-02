#!/usr/bin/env python3

# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
import json
import logging
import os

import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common import armbian_utils

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("repo-reprepro")

# This is called like this:
# /usr/bin/python3 /armbian/lib/tools/info/repo-reprero.py /armbian/output/info/debs-to-repo-info.json /armbian/output/info/reprepro /armbian/output/info/reprepro/conf

debs_info_json_path = sys.argv[1]
reprepro_script_output_dir = sys.argv[2]
reprepro_conf_output_dir = sys.argv[3]

reprepro_conf_distributions_fn = os.path.join(reprepro_conf_output_dir, f"distributions")
reprepro_conf_options_fn = os.path.join(reprepro_conf_output_dir, f"options")
reprepro_output_script_fn = os.path.join(reprepro_script_output_dir, f"reprepro.sh")

# From the environment...
gpg_keyid = armbian_utils.get_from_env("REPO_GPG_KEYID")

# read the json file
with open(debs_info_json_path) as f:
	artifact_debs = json.load(f)

# Now aggregate all repo_targets and their artifacts.
# This will be used to generate the reprepro config file.
repo_targets: dict[str, list] = {}
for artifact in artifact_debs:
	one_repo_target = artifact["repo_target"]
	if one_repo_target not in repo_targets:
		repo_targets[one_repo_target] = []
	repo_targets[one_repo_target].append(artifact)

# for each target
log.info(f"Generating repo config...")

all_distro_lines: list[str] = []
for one_repo_target in repo_targets:
	distro_dict: dict[str, str] = {}
	distro_dict["Origin"] = f"Armbian  origin {one_repo_target}"
	distro_dict["Label"] = f"Armbian label {one_repo_target}"
	distro_dict["Codename"] = f"{one_repo_target}"
	distro_dict["Suite"] = f"{one_repo_target}"
	distro_dict["Architectures"] = "amd64 armhf arm64 riscv64"
	distro_dict["Components"] = "main"
	distro_dict["Description"] = f"Apt repository for Armbian"
	if (gpg_keyid is not None) and (gpg_keyid != ""):
		log.warning(f'Using REPO_GPG_KEYID from environment: {gpg_keyid}')
		distro_dict["SignWith"] = gpg_keyid
	else:
		log.warning(f"Didn't get REPO_GPG_KEYID from environment. Will not sign the repo.")

	for key in distro_dict:
		all_distro_lines.append(f"{key}: {distro_dict[key]}")
	all_distro_lines.append("")

# create the reprerepo distributions file for the target
with open(reprepro_conf_distributions_fn, "w") as f:
	for line in all_distro_lines:
		log.info(f"| {line}")
		f.write(f"{line}\n")
log.info(f"Wrote {reprepro_conf_distributions_fn}")

options: list[str] = []
options.append("verbose")

# create the reprerepo options file for the target
with open(reprepro_conf_options_fn, "w") as f:
	for option in options:
		f.write(f"{option}\n")
log.info(f"Wrote {reprepro_conf_options_fn}")

# Prepare the reprepro-invoking bash script
bash_lines = [
	"#!/bin/bash",
	'set -e',
	'set -o pipefail',
	'mkdir -p "${REPO_CONF_LOCATION}"',
	'cp -rv "${REPREPRO_INFO_DIR}/conf"/* "${REPO_CONF_LOCATION}"/',
	# run clearvanished
	'echo "reprepro clearvanished..."',
	'reprepro -b "${REPO_LOCATION}" --delete clearvanished || echo "clearvanished failed"',
	# run reprepro check
	'echo "reprepro initial check..."',
	'reprepro -b "${REPO_LOCATION}" check || echo "initial check failed"'
]

# Copy the config files to the repo dir (from REPREPRO_INFO_DIR/conf to REPO_CONF_LOCATION script-side)

for one_repo_target in repo_targets:
	artifacts = repo_targets[one_repo_target]
	log.info(f"Artifacts for target '{one_repo_target}': {len(artifacts)}")
	all_debs_to_include: list[str] = []
	# for each artifact
	for artifact in artifacts:
		# for each deb
		for key in artifact["debs"]:
			deb = artifact["debs"][key]
			relative_deb_path = deb["relative_deb_path"]
			all_debs_to_include.append(relative_deb_path)

	all_debs_to_include_quoted = ['"${INCOMING_DEBS_DIR}/' + x + '"' for x in all_debs_to_include]

	if len(all_debs_to_include) > 0:
		# add all debs to the repop
		cmds = ["reprepro", "-b", '"${REPO_LOCATION}"', "--component", "main", "includedeb", one_repo_target] + all_debs_to_include_quoted
		bash_lines.append(f"echo 'reprepro importing {len(all_debs_to_include_quoted)} debs for target {one_repo_target}...' ")
		bash_lines.append(" ".join(cmds))

# Always export at the end
export_cmds = ["reprepro", "-b", '"${REPO_LOCATION}"', "export"]
bash_lines.append(f"echo 'reprepro exporting...' ")
bash_lines.append(" ".join(export_cmds))

with open(reprepro_output_script_fn, "w") as f:
	for line in bash_lines:
		f.write(f"{line}\n")

log.info(f"Wrote {reprepro_output_script_fn}")
