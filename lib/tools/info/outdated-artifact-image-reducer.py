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
log: logging.Logger = logging.getLogger("outdated-artifact-image-reducer")

# read the outdated-artifacts json file passed as first argument as a json object
with open(sys.argv[1]) as f:
	artifacts = json.load(f)

# read the full images info json file passed as second argument as a json object
with open(sys.argv[2]) as f:
	images = json.load(f)

# give an id to each artifact, store in dict (which is also an output)
artifacts_by_id = {}
counter = 1
for artifact in artifacts:
	# id is the counter left-padded with zeros to 10 digits
	artifact["id"] = str(counter).zfill(10)
	counter = counter + 1
	artifacts_by_id[artifact["id"]] = artifact

# lets find artifacts that have the same name, but different versions
tags_by_oci_name: dict[str, list] = {}
for artifact in artifacts:
	artifact_full_oci_target = artifact["out"]["artifact_full_oci_target"]
	# split at the colon (:)
	oci_split = artifact_full_oci_target.split(":")
	oci_name = oci_split[0]
	oci_tag = oci_split[1]
	log.debug(f"OCI name '{oci_name}' has tag '{oci_tag}'")

	# add it to the dict
	if oci_name not in tags_by_oci_name:
		tags_by_oci_name[oci_name] = []
	tags_by_oci_name[oci_name].append(oci_tag)

# loop over the dict, and warn if any have more than one instance
for oci_name in tags_by_oci_name:
	tags = tags_by_oci_name[oci_name]
	if len(tags) > 1:
		list_tags_escaped_quoted = ', '.join([f"'{tag}'" for tag in tags])
		log.warning(
			f"Artifact '{oci_name}' has {len(tags)} different tags: {list_tags_escaped_quoted}")

# map images to in.target_id
images_by_target_id = {}
for image in images:
	if "config_ok" not in image or not image["config_ok"]:
		log.warning(f"Image {image['in']['target_id']} did not config OK, skipping")
		continue

	if "out" not in image:
		log.warning(f"Image {image['in']['target_id']} has no out field, skipping")
		continue

	if "IMAGE_FILE_ID" not in image["out"]:
		log.warning(f"Image {image['in']['target_id']} has no IMAGE_FILE_ID field, skipping")
		continue

	image["image_file_id"] = image["out"]["IMAGE_FILE_ID"]
	images_by_target_id[image["in"]["target_id"]] = image

# map artifacts to in.wanted_by_targets array
artifacts_by_target_id = {}
for artifact in artifacts:
	# optional: if the artifact is up-to-date, skip?
	artifact_wanted_targets = artifact["in"]["wanted_by_targets"]
	for linked_to_target in artifact_wanted_targets:
		if linked_to_target not in artifacts_by_target_id:
			artifacts_by_target_id[linked_to_target] = []
		artifacts_by_target_id[linked_to_target].append(artifact)

artifacts_by_artifact_name = {}
for artifact in artifacts:
	if artifact["in"]["artifact_name"] not in artifacts_by_artifact_name:
		artifacts_by_artifact_name[artifact["in"]["artifact_name"]] = []
	artifacts_by_artifact_name[artifact["in"]["artifact_name"]].append(artifact["id"])

outdated_artifacts_by_artifact_name = {}
for artifact in artifacts:
	if artifact["oci"]["up-to-date"]:
		continue
	if artifact["in"]["artifact_name"] not in outdated_artifacts_by_artifact_name:
		outdated_artifacts_by_artifact_name[artifact["in"]["artifact_name"]] = []
	outdated_artifacts_by_artifact_name[artifact["in"]["artifact_name"]].append(artifact["id"])

images_with_artifacts = {}
for target_id, image in images_by_target_id.items():
	# skip the images with such pipeline config. only their artifacts are relevant.
	if "pipeline" in image["in"]:
		if "build-image" in image["in"]["pipeline"]:
			if not image["in"]["pipeline"]["build-image"]:
				log.debug(f"Image {image['in']['target_id']} has a pipeline build-image false, skipping")
				continue
			else:
				log.debug(f"Image {image['in']['target_id']} has a pipeline build-image true, processing")

	if target_id not in artifacts_by_target_id:
		continue
	image_artifacts = artifacts_by_target_id[target_id]

	image["artifact_ids"] = []
	for artifact in artifacts_by_target_id[target_id]:
		image["artifact_ids"].append(artifact["id"])

	image["outdated_artifacts_count"] = 0
	image["outdated_artifact_ids"] = []
	for artifact in image_artifacts:
		if not artifact["oci"]["up-to-date"]:
			image["outdated_artifact_ids"].append(artifact["id"])
			image["outdated_artifacts_count"] = image["outdated_artifacts_count"] + 1
	images_with_artifacts[target_id] = image

# images with outdated artifacts
images_with_outdated_artifacts = []
for target_id, image in images_with_artifacts.items():
	if image["outdated_artifacts_count"] > 0:
		images_with_outdated_artifacts.append(target_id)

result = {"images": images_with_artifacts, "artifacts": artifacts_by_id,
		  "artifacts_by_artifact_name": artifacts_by_artifact_name,
		  "outdated_artifacts_by_artifact_name": outdated_artifacts_by_artifact_name,
		  "images_with_outdated_artifacts": images_with_outdated_artifacts}

print(json.dumps(result, indent=4, sort_keys=False))
