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
log: logging.Logger = logging.getLogger("output-gha-matrix")


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

		runs_on = "ubuntu-latest"
		image_arch = image['out']['ARCH']
		if image_arch in ["arm64"]:  # , "armhf"
			runs_on = ["self-hosted", "Linux", f"image-{image_arch}"]

		inputs = image['in']
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

		# runs_in = ["self-hosted", "Linux", 'armbian', f"artifact-{artifact_name}"]
		runs_on = "fast"

		# @TODO: externalize this logic.

		# rootfs's fo arm64 are built on self-hosted runners tagged with "rootfs-<arch>"
		if artifact_name in ["rootfs"]:
			rootfs_arch = artifact['in']['inputs']['ARCH']  # @TODO we should resolve arch _much_ ealier in the pipeline and make it standard
			if rootfs_arch in ["arm64"]:  # (future: add armhf)
				runs_on = ["self-hosted", "Linux", f"rootfs-{rootfs_arch}"]

		# all kernels are built on self-hosted runners.
		if artifact_name in ["kernel"]:
			runs_on = ["self-hosted", "Linux", 'alfa']

		inputs = artifact['in']['original_inputs']
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

	# Ensure matrix is sane...
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
