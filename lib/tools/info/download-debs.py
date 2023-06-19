#!/usr/bin/env python3

# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
import json
import logging
import os
import subprocess

import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common import armbian_utils

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("download-debs")


def download_using_armbian(exec_cmd: list[str], params: dict):
	result = None
	logs = []
	try:
		log.debug(f"Start calling Armbian command: {' '.join(exec_cmd)}")
		result = subprocess.run(
			exec_cmd,
			stdout=subprocess.PIPE,
			check=True,
			universal_newlines=False,  # universal_newlines messes up bash encoding, don't use, instead decode utf8 manually;
			bufsize=-1,  # full buffering
			# Early (pre-param-parsing) optimizations for those in Armbian bash code, so use an ENV (not PARAM)
			env={
				"ANSI_COLOR": "none",  # Do not use ANSI colors in logging output, don't write to log files
				"WRITE_EXTENSIONS_METADATA": "no",  # Not interested in ext meta here
				"ALLOW_ROOT": "yes",  # We're gonna be calling it as root, so allow it @TODO not the best option
				"PRE_PREPARED_HOST": "yes"  # We're gonna be calling it as root, so allow it @TODO not the best option
			},
			stderr=subprocess.PIPE
		)
	except subprocess.CalledProcessError as e:
		# decode utf8 manually, universal_newlines messes up bash encoding
		logs = armbian_utils.parse_log_lines_from_stderr(e.stderr)
		log.error(f"Error calling Armbian command: {' '.join(exec_cmd)}")
		log.error(f"Error details: params: {params} - return code: {e.returncode} - stderr: {'; '.join(logs)}")
		return {"in": params, "logs": logs, "download_ok": False}

	if result is not None:
		if result.stderr:
			logs = armbian_utils.parse_log_lines_from_stderr(result.stderr)

	info = {"in": params, "download_ok": True}
	info["logs"] = logs
	return info


# This is called like this:
# /usr/bin/python3 /armbian/lib/tools/info/download-debs.py /armbian/output/info/debs-to-repo-info.json /armbian/output/debs

debs_info_json_path = sys.argv[1]
debs_output_dir = sys.argv[2]

# read the json file
with open(debs_info_json_path) as f:
	artifact_debs = json.load(f)

log.info("Downloading debs...")
# loop over the debs. if we're missing any, download them.
missing_debs = []
missing_invocations = []
for artifact in artifact_debs:
	is_missing_deb = False
	for key in artifact["debs"]:
		deb = artifact["debs"][key]
		relative_deb_path = deb["relative_deb_path"]
		deb_path = os.path.join(debs_output_dir, relative_deb_path)
		if not os.path.isfile(deb_path):
			log.info(f"Missing deb: {deb_path}")
			missing_debs.append(deb_path)
			is_missing_deb = True
	if is_missing_deb:
		missing_invocations.append(artifact["download_invocation"])

log.info(f"Missing debs: {len(missing_debs)}")
log.info(f"Missing invocations: {len(missing_invocations)}")

# only actually invoke anything if we're in a container
# run ./compile.sh <invocation> for each missing invocation
for invocation in missing_invocations:
	cmds = [(armbian_utils.find_armbian_src_path()["compile_sh_full_path"])] + invocation
	log.info(f"Running: {' '.join(cmds)}")
	if armbian_utils.get_from_env("ARMBIAN_RUNNING_IN_CONTAINER") == "yes":
		dl_info = download_using_armbian(cmds, {"missing": "deb"})
		log.info(f"Download info: {dl_info}")
