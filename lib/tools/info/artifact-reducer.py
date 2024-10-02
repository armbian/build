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
log: logging.Logger = logging.getLogger("artifact-reducer")

# read the targets.json file passed as first argument as a json object
with open(sys.argv[1]) as f:
	build_infos = json.load(f)

all_artifacts: list[dict] = []

# loop over the build infos. for each, construct a structure with the artifacts.
for build_info in build_infos:
	if build_info["config_ok"] is False:
		if ("target_not_supported" in build_info) and (build_info["target_not_supported"] is True):
			log.debug(f"Skipping 'target not supported' config '{build_info['in']}'...")
		else:
			log.warning(f"Skipping *failed* config '{build_info['in']}'...")
		continue

	outvars = build_info["out"]

	want_uppercase: list[str] = outvars["WANT_ARTIFACT_ALL_ARRAY"]
	want_names: list[str] = outvars["WANT_ARTIFACT_ALL_NAMES_ARRAY"]
	# create a dict with uppercase keys and names for values
	want_dict: dict[str, str] = dict(zip(want_uppercase, want_names))

	# loop over the uppercases
	for uppercase in want_uppercase:
		# if uppercase != "KERNEL":
		#	log.warning(f"Skipping artifact '{uppercase}'...")
		#	continue
		inputs_keyname = f"WANT_ARTIFACT_{uppercase}_INPUTS_ARRAY"
		inputs_raw_array = outvars[inputs_keyname]
		artifact_name = want_dict[uppercase]

		# check the pipeline config for artifacts...
		if "pipeline" in build_info["in"]:
			pipeline = build_info["in"]["pipeline"]
			if "build-artifacts" in pipeline:
				if pipeline["build-artifacts"] == False:
					log.debug(f"Skipping artifact '{artifact_name}' (pipeline build-artifacts '{pipeline['build-artifacts']}' config)...")
					continue
				else:
					log.debug(f"Keeping artifact '{artifact_name}' (pipeline build-artifacts '{pipeline['build-artifacts']}' config)...")
			if "only-artifacts" in pipeline:
				only_artifacts = pipeline["only-artifacts"]
				if artifact_name not in only_artifacts:
					log.debug(f"Skipping artifact '{artifact_name}' (pipeline only-artifacts '{','.join(only_artifacts)}' config)...")
					continue
				else:
					log.debug(f"Keeping artifact '{artifact_name}' (pipeline only-artifacts '{','.join(only_artifacts)}' config)...")

		inputs: dict[str, str] = {}
		for input_raw in inputs_raw_array:
			# de-quote the value. @TODO: fragile
			input = input_raw[1:-1]
			# split the input into a tuple
			(key, value) = input.split("=", 1)
			inputs[key] = value
		# sort by key, join k=v again
		inputs_sorted = "&".join([f"{k}={v}" for k, v in sorted(inputs.items())])
		artifact_build_key = f"{artifact_name}?{inputs_sorted}"
		all_artifacts.append({"artifact_name": artifact_name, "key": artifact_build_key, "inputs": inputs, "original_inputs": build_info["in"]})

log.info(f"Found {len(all_artifacts)} total artifacts... reducing...")

# deduplicate each artifact; keep a reference to the original input of one of the duplicates
deduplicated_artifacts: dict[str, dict] = {}
for artifact in all_artifacts:
	artifact_build_key = artifact["key"]
	if artifact_build_key not in deduplicated_artifacts:
		deduplicated_artifacts[artifact_build_key] = artifact
		deduplicated_artifacts[artifact_build_key]["needed_by"] = 0
		deduplicated_artifacts[artifact_build_key]["wanted_by_targets"] = []
	deduplicated_artifacts[artifact_build_key]["needed_by"] += 1
	deduplicated_artifacts[artifact_build_key]["wanted_by_targets"].append(artifact["original_inputs"]["target_id"])

log.info(f"Found {len(deduplicated_artifacts)} unique artifacts combinations... reducing...")

# get a list of all the artifacts, sorted by how many needed_by
deduplicated_artifacts_sorted = sorted(deduplicated_artifacts.values(), key=lambda x: x["needed_by"], reverse=True)

# group again, this time by artifact name
artifacts_by_name: dict[str, list[dict]] = {}
for artifact in deduplicated_artifacts_sorted:
	artifact_name = artifact["artifact_name"]
	if artifact_name not in artifacts_by_name:
		artifacts_by_name[artifact_name] = []
	artifacts_by_name[artifact_name].append(artifact)

log.info(f"Found {len(artifacts_by_name)} unique artifacts... reducing...")

for artifact_name, artifacts in artifacts_by_name.items():
	log.info(f"Reduced '{artifact_name}' artifact to: {len(artifacts)} instances.")

# dump  as json
print(json.dumps(deduplicated_artifacts_sorted, indent=4, sort_keys=True))
