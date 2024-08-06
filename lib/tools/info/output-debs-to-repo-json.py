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
log: logging.Logger = logging.getLogger("output-debs-to-repo-json")


def generate_deb_summary(info):
	ret = []
	for artifact_id in info["artifacts"]:
		artifact = info["artifacts"][artifact_id]

		# skip = not not artifact["oci"]["up-to-date"]
		# if skip:
		#	continue

		artifact_name = artifact['in']['artifact_name']

		desc = f"{artifact['out']['artifact_name']}={artifact['out']['artifact_version']}"

		out = artifact["out"]
		artifact_type = out["artifact_type"]
		artifact_version = out["artifact_version"]
		artifact_final_version_reversioned = out["artifact_final_version_reversioned"]
		artifact_deb_repo = out["artifact_deb_repo"]

		if not (artifact_type == "deb" or artifact_type == "deb-tar"):
			continue

		all_debs: dict[str, dict] = {}

		artifact_map_debs_keys = out["artifact_map_debs_keys_ARRAY"]
		artifact_map_debs_values = out["artifact_map_debs_values_ARRAY"]
		artifact_map_packages_keys = out["artifact_map_packages_keys_ARRAY"]
		artifact_map_packages_values = out["artifact_map_packages_values_ARRAY"]
		artifact_map_debs_reversioned_keys = out["artifact_map_debs_reversioned_keys_ARRAY"]
		artifact_map_debs_reversioned_values = out["artifact_map_debs_reversioned_values_ARRAY"]

		# Sanity check: all those array should have the same amount of elements.
		if not (len(artifact_map_debs_keys) == len(artifact_map_debs_values) == len(artifact_map_packages_keys) ==
				len(artifact_map_packages_values) == len(artifact_map_debs_reversioned_keys) == len(artifact_map_debs_reversioned_values)):
			log.error(f"Error: artifact {artifact_id} has different amount of keys and values in the map: {artifact}")
			continue

		# Sanity check: all keys should be the same
		if not (artifact_map_debs_keys == artifact_map_packages_keys == artifact_map_debs_reversioned_keys):
			log.error(f"Error: artifact {artifact_id} has different keys in the map: {artifact}")
			continue

		for i in range(len(artifact_map_debs_keys)):
			key = artifact_map_debs_keys[i]
			# add to all_debs, but check if it's already there
			if key in all_debs:
				log.error(f"Error: artifact {artifact_id} has duplicated key {key} in the map: {artifact}")
				continue

			if artifact_deb_repo == "global":
				repo_target = "armbian"
			else:
				repo_target = f'armbian-{artifact_deb_repo}'

			all_debs[key] = {
				"relative_deb_path": (artifact_map_debs_reversioned_values[i]),
				"package_name": (artifact_map_packages_values[i]),
				"repo_target": repo_target
			}

		# Aggregate all repo_targets from their debs. There can be only one. Eg: each artifact can only be in one repo_target, no matter how many debs.
		repo_targets = set()
		for key in all_debs:
			repo_targets.add(all_debs[key]["repo_target"])
		if len(repo_targets) > 1:
			log.error(f"Error: artifact {artifact_id} has debs in different repo_targets: {artifact}")
			continue

		repo_target = repo_targets.pop()

		inputs = artifact["in"]["original_inputs"]
		# get the invocation, in array format. "what do I run to download the debs" for this artifact. args are NOT quoted.
		invocation = (["download-artifact"] + armbian_utils.map_to_armbian_params(inputs["vars"], False) + inputs["configs"])

		item = {
			"id": artifact_id, "desc": desc,
			"artifact_name": artifact_name,
			"artifact_type": artifact_type,
			"artifact_version": artifact_version,
			"artifact_final_version_reversioned": artifact_final_version_reversioned,
			"artifact_deb_repo": artifact_deb_repo,
			"repo_target": repo_target,
			"download_invocation": invocation,
			"debs": all_debs
		}
		ret.append(item)
	return ret


# This is called like this:
# /usr/bin/python3 /armbian/lib/tools/info/output-debs-to-repo.py /armbian/output/info /armbian/output/info/outdated-artifacts-images.json

# first arg the output directory (output/info)
info_output_dir = sys.argv[1]
output_json_file = os.path.join(info_output_dir, "debs-to-repo-info.json")
outdated_artifacts_image_json_filepath = sys.argv[2]

# read the json file passed as second argument as a json object
with open(outdated_artifacts_image_json_filepath) as f:
	info = json.load(f)

artifact_debs = generate_deb_summary(info)

# dump the json to a debs-to-repo-info.json file in the output directory
with open(output_json_file, "w") as f:
	json.dump(artifact_debs, f, indent=4)

log.info(f"Done writing {output_json_file}")
