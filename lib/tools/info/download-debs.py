#!/usr/bin/env python3
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
import concurrent.futures
import json
import logging
import multiprocessing
import os
import subprocess

import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common import armbian_utils

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("download-debs")


def download_using_armbian(exec_cmd: list[str], params: dict, counter: int, total: int):
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
				"ALLOW_ROOT": "yes",  # We're gonna be calling it as root, so allow it
				"PRE_PREPARED_HOST": "yes",  # We're gonna be calling it as root, so allow it
				"SKIP_LOG_ARCHIVE": "yes"  # Don't waste time and conflicts trying to archive logs at this point
			},
			stderr=subprocess.PIPE
		)
	except subprocess.CalledProcessError as e:
		# decode utf8 manually, universal_newlines messes up bash encoding
		logs = armbian_utils.parse_log_lines_from_stderr(e.stderr)
		log.error(
			f"Error calling Armbian command: {' '.join(exec_cmd)} Error details: params: {params} - return code: {e.returncode} - stderr: {'; '.join(logs)}")
		return {"in": params, "logs": logs, "download_ok": False}

	if result is not None:
		if result.stderr:
			logs = armbian_utils.parse_log_lines_from_stderr(result.stderr)

	if counter % 10 == 0:
		log.info(f"Processed {counter} / {total} download invocations.")

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

if armbian_utils.get_from_env("ARMBIAN_RUNNING_IN_CONTAINER") == "yes":
	log.warning("Not running in a container. download-debs might fail. Run this in a Docker-capable machine.")

# use double the number of cpu cores, but not more than 16
max_workers = 16 if ((multiprocessing.cpu_count() * 2) > 16) else (multiprocessing.cpu_count() * 2)
# allow overriding from  PARALLEL_DOWNLOADS_WORKERS env var
if "PARALLEL_DOWNLOADS_WORKERS" in os.environ and os.environ["PARALLEL_DOWNLOADS_WORKERS"]:
	max_workers = int(os.environ["PARALLEL_DOWNLOADS_WORKERS"])
log.info(f"Using {max_workers} workers for parallel processing")

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

counter = 0
total = len(missing_invocations)
# get the number of processor cores on this machine
log.info(f"Using {max_workers} workers for parallel download processing.")
with concurrent.futures.ProcessPoolExecutor(max_workers=max_workers) as executor:
	every_future = []
	for invocation in missing_invocations:
		counter += 1
		cmds = [(armbian_utils.find_armbian_src_path()["compile_sh_full_path"])] + invocation
		future = executor.submit(download_using_armbian, cmds, {"i": invocation}, counter, total)
		every_future.append(future)

	log.info(f"Submitted {len(every_future)} download jobs to the parallel executor. Waiting for them to finish...")
	executor.shutdown(wait=True)
	log.info(f"All download jobs finished!")

	for future in every_future:
		info = future.result()
		if info is not None:
			log.info(f"Download future info: {info}")
