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
from common import gha

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("output-gha-matrix")


def resolve_gha_runner_tags_via_pipeline_gha_config(input: dict, artifact_name: str, artifact_arch: str):
	log.debug(f"Resolving GHA runner tags for artifact/image '{artifact_name}' '{artifact_arch}'")

	# if no config, default to "ubuntu-latest" as a last-resort
	ret = "ubuntu-latest"

	if not "pipeline" in input:
		log.warning(f"No 'pipeline' config in input, defaulting to '{ret}'")
		return ret

	pipeline = input["pipeline"]

	if not "gha" in pipeline:
		log.warning(f"No 'gha' config in input.pipeline, defaulting to '{ret}'")
		return ret

	gha = pipeline["gha"]

	if (gha is None) or (not "runners" in gha):
		log.warning(f"No 'runners' config in input.pipeline.gha, defaulting to '{ret}'")
		return ret

	runners = gha["runners"]

	if "default" in runners:
		ret = runners["default"]
		log.debug(f"Found 'default' config in input.pipeline.gha.runners, defaulting to '{ret}'")

	# Now, 'by-name' first.
	if "by-name" in runners:
		by_names = runners["by-name"]
		if artifact_name in by_names:
			ret = by_names[artifact_name]
			log.debug(f"Found 'by-name' value '{artifact_name}' config in input.pipeline.gha.runners, using '{ret}'")

	# Now, 'by-name-and-arch' second.
	artifact_name_and_arch = f"{artifact_name}{f'-{artifact_arch}' if artifact_arch is not None else ''}"
	if "by-name-and-arch" in runners:
		by_names_and_archs = runners["by-name-and-arch"]
		if artifact_name_and_arch in by_names_and_archs:
			ret = by_names_and_archs[artifact_name_and_arch]
			log.debug(f"Found 'by-name-and-arch' value '{artifact_name_and_arch}' config in input.pipeline.gha.runners, using '{ret}'")

	log.info(f"Resolved GHA runs_on for name:'{artifact_name}' arch:'{artifact_arch}' to runs_on:'{ret}'")

	return ret


def generate_matrix_images(info) -> list[dict]:
	# each image
	matrix = []
	for image_id in info["images"]:
		image = info["images"][image_id]

		if armbian_utils.get_from_env("IMAGES_ONLY_OUTDATED_ARTIFACTS") == "yes":
			skip = image["outdated_artifacts_count"] == 0
			if skip:
				log.info(f"Skipping image {image_id} because it has no outdated artifacts")
				continue

		if armbian_utils.get_from_env("SKIP_IMAGES") == "yes":
			log.warning(f"Skipping image {image_id} because SKIP_IMAGES=yes")
			continue

		desc = f"{image['image_file_id']} {image_id}"

		inputs = image['in']

		image_arch = image['out']['ARCH']
		runs_on = resolve_gha_runner_tags_via_pipeline_gha_config(inputs, "image", image_arch)

		cmds = (armbian_utils.map_to_armbian_params(inputs["vars"]) + inputs["configs"])  # image build is "build" command, omitted here
		invocation = " ".join(cmds)

		item = {"desc": desc, "runs_on": runs_on, "invocation": invocation}
		matrix.append(item)
	return matrix


def generate_matrix_artifacts(info):
	# each artifact
	matrix = []
	for artifact_id in info["artifacts"]:
		artifact = info["artifacts"][artifact_id]
		skip = not not artifact["oci"]["up-to-date"]
		if skip:
			continue

		artifact_name = artifact['in']['artifact_name']

		desc = f"{artifact['out']['artifact_final_file_basename']}"

		inputs = artifact['in']['original_inputs']

		artifact_arch = None
		# Try via the inputs to artifact...
		if "inputs" in artifact['in']:
			if "ARCH" in artifact['in']['inputs']:
				artifact_arch = artifact['in']['inputs']['ARCH']

		runs_on = resolve_gha_runner_tags_via_pipeline_gha_config(inputs, artifact_name, artifact_arch)

		cmds = (["artifact"] + armbian_utils.map_to_armbian_params(inputs["vars"]) + inputs["configs"])
		invocation = " ".join(cmds)

		item = {"desc": desc, "runs_on": runs_on, "invocation": invocation}
		matrix.append(item)
	return matrix


# generate images or artifacts?
type_gen = sys.argv[1]

# read the outdated artifacts+imaes json file passed as first argument as a json object
with open(sys.argv[2]) as f:
	info = json.load(f)

matrix = None
if type_gen == "artifacts":
	matrix = generate_matrix_artifacts(info)
elif type_gen == "images":
	matrix = generate_matrix_images(info)
else:
	log.error(f"Unknown type: {type_gen}")
	sys.exit(1)

# third argument is the number of chunks wanted.
ideal_chunk_size = 150
max_chunk_size = 250

# check is sys.argv[3] exists...
if len(sys.argv) >= 4:
	num_chunks = int(sys.argv[3])
else:
	log.warning(f"Number of chunks not specified. Calculating automatically, matrix: {len(matrix)} chunk ideal: {ideal_chunk_size}.")
	# calculate num_chunks by dividing the matrix size by the ideal chunk size, and rounding always up.
	num_chunks = int(len(matrix) / ideal_chunk_size) + 1
	log.warning(f"Number of chunks: {num_chunks}")

# distribute the matrix items equally along the chunks. try to keep every chunk the same size.
chunks = []
for i in range(num_chunks):
	chunks.append([])
for i, item in enumerate(matrix):
	chunks[i % num_chunks].append(item)

# ensure chunks are not too big
for i, chunk in enumerate(chunks):
	if len(chunk) > ideal_chunk_size:
		log.warning(f"Chunk '{i + 1}' is bigger than ideal: {len(chunk)}")

	if len(chunk) > max_chunk_size:
		log.error(f"Chunk '{i + 1}' is too big: {len(chunk)}")
		sys.exit(1)

	# Directly set outputs for _each_ GHA chunk here. (code below is for all the chunks)
	gha.set_gha_output(f"{type_gen}-chunk-json-{i + 1}", json.dumps({"include": chunk}))
	# An output that is used to test for empty matrix.
	gha.set_gha_output(f"{type_gen}-chunk-not-empty-{i + 1}", "yes" if len(chunk) > 0 else "no")
	gha.set_gha_output(f"{type_gen}-chunk-size-{i + 1}", len(chunk))

	# For the full matrix, we can't have empty chunks; use a "really" field to indicate a fake entry added to make it non-empty.
	if len(chunk) == 0:
		log.warning(f"Chunk '{i + 1}' for '{type_gen}' is empty, adding fake invocation.")
		chunks[i] = [{"desc": "Fake matrix element so matrix is not empty", "runs_on": "ubuntu-latest", "invocation": "none", "really": "no"}]
	else:
		for item in chunk:
			item["really"] = "yes"

# massage the chunks so they're objects with "include" key, the way GHA likes it.
all_chunks = {}
for i, chunk in enumerate(chunks):
	log.info(f"Chunk {i + 1} has {len(chunk)} elements.")
	all_chunks[f"chunk{i + 1}"] = {"include": chunk}

print(json.dumps(all_chunks))
