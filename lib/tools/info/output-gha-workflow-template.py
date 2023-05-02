#!/usr/bin/env python3

# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
import logging
import os
import yaml

import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common import armbian_utils
from jinja2 import Environment
from jinja2 import StrictUndefined

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("output-gha-workflow-template")

# Parse cmdline

output_file = sys.argv[1]
config_yaml_file = sys.argv[2]
template_dir = sys.argv[3]
num_chunks_artifacts = int(sys.argv[4])
num_chunks_images = int(sys.argv[5])

log.info(f"output_file: {output_file}")
log.info(f"template_dir: {template_dir}")
log.info(f"num_chunks_artifacts: {num_chunks_artifacts}")
log.info(f"num_chunks_images: {num_chunks_images}")

# load the yaml config (context for all entries)
config = {}
with open(config_yaml_file, "r") as f:
	config_yaml = f.read()
	config = yaml.load(config_yaml, Loader=yaml.FullLoader)

# get a list of the .yaml files in the template dir
template_files = [f for f in os.listdir(template_dir) if f.endswith(".yaml") or f.endswith(".yml")]
# sort it
template_files.sort()
log.info(f"template_files: {template_files}")

out: str = ""


# here is a list of the filenames we expect:
# 050.single_header.yaml
# 150.per-chunk-artifacts_prep-outputs.yaml
# 151.per-chunk-images_prep-outputs.yaml
# 250.single_aggr.jobs.yaml
# 550.per-chunk-artifacts_job.yaml
# 650.per-chunk-images_job.yaml
def handle_template(template_content: str, context: dict) -> str:
	env = Environment(block_start_string='[%', block_end_string='%]',
					  variable_start_string='[[', variable_end_string=']]', comment_start_string='[#', comment_end_string='#]',
					  undefined=StrictUndefined)
	jinja_template = env.from_string(template_content)

	rendered = jinja_template.render(context)

	# Now, strip all the lines that contain the string "<TEMPLATE-IGNORE>"
	rendered = "\n".join([line for line in rendered.split("\n") if "<TEMPLATE-IGNORE>" not in line])

	# More crazy. For the string '"TEMPLATE-JOB-NAME": # <TEMPLATE-JOB-NAME>' we will replace it with the actual job name
	rendered = rendered.replace('"TEMPLATE-JOB-NAME": # <TEMPLATE-JOB-NAME>', f'"{context["job_name"]}": # templated "{context["job_name"]}"')

	# ensure it ends with a newline
	if not rendered.endswith("\n"):
		rendered += "\n"

	return rendered


# loop over the template files
for template_file in template_files:
	# parse the filename according to the above list
	template_order, rest = template_file.split(".", 1)
	template_order = int(template_order)
	# parse the type of template, separated by "_"
	template_type, rest = rest.split("_", 1)
	# parse the name of the template and the extension. the extension is anything after the first "."
	template_name, template_ext = rest.split(".", 1)
	# read the full contents of the template file as UTF-8
	with open(os.path.join(template_dir, template_file), "r") as f:
		template_content = f.read()

	log.info(
		f"Processing template file: {template_file} (order: {template_order}, type: {template_type}, name: {template_name}, ext:{template_ext}, len:{len(template_content)} bytes)")

	# prepare quoted comma lists of the chunks, remove the first and last quotes
	quoted_comma_list_artifact_chunk_jobs = ",".join([f"\"build-artifacts-chunk-{chunk + 1}\"" for chunk in range(num_chunks_artifacts)])[1:-1]

	# same, but for images, remove the first and last quotes
	quoted_comma_list_image_chunk_jobs = ",".join([f"\"build-images-chunk-{chunk + 1}\"" for chunk in range(num_chunks_images)])[1:-1]

	context = {
		"num_chunks_artifacts": num_chunks_artifacts,
		"num_chunks_images": num_chunks_images,
		"quoted_comma_list_artifact_chunk_jobs": quoted_comma_list_artifact_chunk_jobs,
		"quoted_comma_list_image_chunk_jobs": quoted_comma_list_image_chunk_jobs
	}

	# all 'config' dict on top, for common things re-used everywhere
	context.update(config)

	out += f"\n# template file: {template_file}\n\n"

	if template_type == "single":
		context["job_name"] = "ERROR_IN_TEMPLATE!!!"
		out += handle_template(template_content, context)
	elif template_type == "per-chunk-artifacts":
		for chunk in range(num_chunks_artifacts):
			context["chunk"] = chunk + 1
			context["num_chunks"] = num_chunks_artifacts
			context["job_name"] = f"build-artifacts-chunk-{chunk + 1}"
			out += handle_template(template_content, context)
	elif template_type == "per-chunk-images":
		for chunk in range(num_chunks_images):
			context["chunk"] = chunk + 1
			context["num_chunks"] = num_chunks_images
			context["job_name"] = f"build-images-chunk-{chunk + 1}"
			out += handle_template(template_content, context)
	else:
		raise Exception(f"Unknown template type: {template_type}")

# write the out str to the output file
with open(output_file, "w") as f:
	f.write(out)

log.info(f"Done. Wrote {len(out)} bytes to {output_file}")
