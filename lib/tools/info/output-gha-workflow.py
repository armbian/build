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


class BuildJob(gha.BaseWorkflowJob):
	def __init__(self, id: str, name: str):
		super().__init__(id, name)
		self.add_default_envs()
		self.add_ghcr_login_step()

	def add_default_envs(self):
		self.envs["OCI_TARGET_BASE"] = "ghcr.io/${{ github.repository }}/"  # This is picked up by the Docker launcher automatically
		self.envs["DOCKER_ARMBIAN_BASE_COORDINATE_PREFIX"] = "ghcr.io/${{ github.repository }}:armbian-next-"  # Use Docker image in same repo
		self.envs[
			"DOCKER_SKIP_UPDATE"] = "yes"  # Do not apt update/install/requirements/etc during Dockerfile build, trust DOCKER_ARMBIAN_BASE_COORDINATE_PREFIX's images are up-to-date

	def add_ghcr_login_step(self):
		# Login to ghcr.io, we're gonna do a lot of OCI lookups.
		login_step = self.add_step("docker-login-ghcr", "Docker Login to GitHub Container Registry")
		login_step.uses = "docker/login-action@v2"
		login_step.withs["registry"] = "ghcr.io"
		login_step.withs["username"] = "${{ github.repository_owner }}"  # GitHub username or org
		login_step.withs["password"] = "${{ secrets.GITHUB_TOKEN }}"  # GitHub actions builtin token. repo has to have pkg access.


#       # Login to ghcr.io, we're gonna do a lot of OCI lookups.
#       - name: Docker Login to GitHub Container Registry
#         uses: docker/login-action@v2
#         with:
#           registry: ghcr.io
#           username: ${{ github.repository_owner }} # GitHub username or org
#           password: ${{ secrets.GITHUB_TOKEN }}    # GitHub actions builtin token. repo has to have pkg access.

class ArtifactJob(BuildJob):
	def __init__(self, id: str, name: str):
		super().__init__(id, name)


class ImageJob(BuildJob):
	def __init__(self, id: str, name: str):
		super().__init__(id, name)


class PrepareJob(BuildJob):
	def __init__(self, id: str, name: str):
		super().__init__(id, name)

	def add_initial_checkout(self):
		# Checkout the build repo
		checkout_step = self.add_step("checkout-build-repo", "Checkout build repo")
		checkout_step.uses = "actions/checkout@v3"
		checkout_step.withs["repository"] = "${{ github.repository_owner }}/armbian-build"
		checkout_step.withs["ref"] = "extensions"
		checkout_step.withs["fetch-depth"] = 1
		checkout_step.withs["clean"] = "false"

		# Now grab the SHA1 from the checked out copy
		grab_sha1_step = self.add_step("git-info", "Grab SHA1")
		grab_sha1_step.run = 'echo "sha1=$(git rev-parse HEAD)" >> $GITHUB_OUTPUT'
		self.add_job_output_from_step(grab_sha1_step, "sha1")

	def add_cache_restore_step(self):
		# Restore the cache
		restore_cache_step = self.add_step("restore-cache", "Restore cache")
		restore_cache_step.uses = "actions/cache@v3"
		restore_cache_step.withs["path"] = "cache/memoize\ncache/oci/positive"
		restore_cache_step.withs["key"] = '${{ runner.os }}-cache-${{ github.sha }}-${{ steps.git-info.outputs.sha1 }}'
		restore_cache_step.withs["restore-keys"] = '${{ runner.os }}-matrix-cache-'

	def add_cache_chown_step(self):
		# chown the cache back to normal user
		chown_cache_step = self.add_step("chown-cache", "Chown cache")
		chown_cache_step.run = 'sudo chown -R $USER:$USER cache/memoize cache/oci/positive'

	def prepare_gh_releases_step(self):
		# @TODO this is outdated, needs replacement. Also it deletes the release if it already exists, which is not what we want. Might be necessary to move the tag.
		gh_releases_step = self.add_step("gh-releases", "Prepare GitHub Releases")
		gh_releases_step.uses = "marvinpinto/action-automatic-releases@latest"
		gh_releases_step.withs["repo_token"] = "${{ secrets.GITHUB_TOKEN }}"
		gh_releases_step.withs["automatic_release_tag"] = "latest-images"
		gh_releases_step.withs["prerelease"] = "false"
		gh_releases_step.withs["title"] = "Latest images"


# read the outdated artifacts+imaes json file passed as first argument as a json object
with open(sys.argv[1]) as f:
	info = json.load(f)

# Create a WorkflowFactory
wfFactory: gha.WorkflowFactory = gha.WorkflowFactory()

# Create prepare job
pJob: PrepareJob = PrepareJob(f"prepare", f"prepare all")
pJob.set_runs_on(["self-hosted", "Linux", "matrix-prepare"])  # @TODO: de-hardcode?
pJob.add_initial_checkout()
pJob.add_cache_restore_step()

pJobUpToDateStep = pJob.add_step(f"check-up-to-date", f"Check up to date")
pJobUpToDateStep.run = f'rm -rfv output/info; bash ./compile.sh workflow rpardini-generic # DEBUG=yes'
# The outputs are added later, for each artifact.

pJob.add_cache_chown_step()
pJob.prepare_gh_releases_step()

wfFactory.add_job(pJob)

all_artifact_jobs = {}
u2date_artifact_outputs = {}

for artifact_id in info["artifacts"]:
	artifact = info["artifacts"][artifact_id]

	skip = not not artifact["oci"]["up-to-date"]
	# if skip:
	#	continue

	artifact_name = artifact['in']['artifact_name']

	# desc = f"{artifact['out']['artifact_final_file_basename']}"
	desc = f"{artifact['out']['artifact_name']}"

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
		runs_on = ["self-hosted", "Linux", "alfa"]

	inputs = artifact['in']['original_inputs']
	cmds = (["artifact"] + armbian_utils.map_to_armbian_params(inputs["vars"], True) + inputs["configs"])
	invocation = " ".join(cmds)

	item = {"desc": desc, "runs_on": runs_on, "invocation": invocation}

	aJob: ArtifactJob = ArtifactJob(f"artifact-{artifact_id}", f"{desc}")
	aJob.set_runs_on(runs_on)
	build_step = aJob.add_step(f"build-artifact", f"Build artifact {desc}")
	build_step.run = f'echo "fake artifact: {invocation}"'

	# Add output to prepare job... & set the GHA output, right here. Hey us, it's us from the future. We're so smart.
	# write to a github actions output variable. use the filesystem.
	gha.set_gha_output(f"u2d-{artifact_id}", ("yes" if skip else "no"))

	output: gha.WorkflowJobOutput = pJob.add_job_output_from_step(pJobUpToDateStep, f"u2d-{artifact_id}")

	input: gha.WorkflowJobInput = aJob.add_job_input_from_needed_job_output(output)
	aJob.add_condition_from_input(input, "== 'no'")

	u2date_output: gha.WorkflowJobOutput = aJob.add_job_output_from_input(f"up-to-date-artifact", input)

	all_artifact_jobs[artifact_id] = aJob
	u2date_artifact_outputs[artifact_id] = u2date_output
	wfFactory.add_job(aJob)

# Ok now the images...

for image_id in info["images"]:
	image = info["images"][image_id]

	# skip = image["outdated_artifacts_count"] == 0
	# if skip:
	#	continue

	desc = f"{image['image_file_id']} {image_id}"
	runs_on = "fast"
	image_arch = image['out']['ARCH']
	if image_arch in ["arm64"]:  # , "armhf"
		runs_on = ["self-hosted", "Linux", f"image-{image_arch}"]

	inputs = image['in']
	cmds = (armbian_utils.map_to_armbian_params(inputs["vars"], True) + inputs["configs"])  # image build is "build" command, omitted here
	invocation = " ".join(cmds)

	iJob: ImageJob = ImageJob(f"image-{image_id}", f"{desc}")
	iJob.set_runs_on(runs_on)
	build_step = iJob.add_step(f"build-image", f"Build image {desc}")
	build_step.run = f'echo "fake image: {invocation}"'

	# Make it use the outputs from the artifacts needed for this image
	for artifact_id in image["artifact_ids"]:
		log.info(f"Image {image_id} wants artifact {artifact_id}")
		aJob = all_artifact_jobs[artifact_id]
		aJobU2dOutput = u2date_artifact_outputs[artifact_id]
		u2dinput = iJob.add_job_input_from_needed_job_output(aJobU2dOutput)
		iJob.add_condition_from_input(u2dinput, "== 'no'")

	wfFactory.add_job(iJob)

# Convert gha_workflow to YAML
gha_workflow_yaml = armbian_utils.to_yaml(wfFactory.render_yaml())

# Write the YAML the target file
with open(sys.argv[2], "w") as f:
	f.write(gha_workflow_yaml)
