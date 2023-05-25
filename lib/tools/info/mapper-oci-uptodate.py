#!/usr/bin/env python3

# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
import datetime
import hashlib
import json
import logging
import os

import oras.client
import oras.logger
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common import armbian_utils

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("mapper-oci-up-to-date")

# Extra logging for ORAS library
oras.logger.setup_logger(quiet=(not armbian_utils.is_debug()), debug=(armbian_utils.is_debug()))

# Prepare Armbian cache
armbian_paths = armbian_utils.find_armbian_src_path()
cache_dir = armbian_paths["armbian_src_path"] + "/cache"
oci_cache_dir_positive = cache_dir + "/oci/positive"
os.makedirs(oci_cache_dir_positive, exist_ok=True)
oci_cache_dir_positive = os.path.abspath(oci_cache_dir_positive)

oci_cache_dir_negative = cache_dir + "/oci/negative"
os.makedirs(oci_cache_dir_negative, exist_ok=True)
oci_cache_dir_negative = os.path.abspath(oci_cache_dir_negative)

client = oras.client.OrasClient(insecure=False)
log.info(f"OCI client version: {client.version()}")

# the cutoff time for missed cache files; keep it low. positive hits are cached forever
cutoff_mtime = (datetime.datetime.now().timestamp() - 60 * 5)  # 5 minutes ago

# global counters for final stats
stats = {"lookups": 0, "skipped": 0, "hits": 0, "misses": 0, "hits_positive": 0, "hits_negative": 0, "late_misses": 0, "miss_positive": 0,
		 "miss_negative": 0}


def check_oci_up_to_date_cache(oci_target: str, really_check: bool = False):
	# increment the stats counter
	stats["lookups"] += 1

	if not really_check:
		# we're not really checking, so just return a positive hit
		stats["skipped"] += 1
		return {"up-to-date": False, "reason": "oci-check-not-performed"}

	log.info(f"Checking if '{oci_target}' is up-to-date...")

	# init the returned obj
	ret = {"up-to-date": False, "reason": "undetermined"}

	# md5 hash of the oci_target. don't use any utils, just do it ourselves with standard python
	md5_hash = hashlib.md5(oci_target.encode()).hexdigest()

	cache_file_positive = f"{oci_cache_dir_positive}/{md5_hash}.json"
	cache_file_negative = f"{oci_cache_dir_negative}/{md5_hash}.json"
	cache_hit = False
	if os.path.exists(cache_file_positive):
		# increment the stats counter
		stats["hits_positive"] += 1
		cache_hit = True
		log.debug(f"Found positive cache file for '{oci_target}'.")
		with open(cache_file_positive) as f:
			ret = json.load(f)
	elif os.path.exists(cache_file_negative):
		# increment the stats counter
		stats["hits_negative"] += 1
		cache_file_mtime = os.path.getmtime(cache_file_negative)
		log.debug(f"Cache mtime:  {cache_file_mtime} / Cutoff time:  {cutoff_mtime}")
		if cache_file_mtime > cutoff_mtime:
			cache_hit = True
			log.debug(f"Found still-valid negative cache file for '{oci_target}'.")
			with open(cache_file_negative) as f:
				ret = json.load(f)
		else:
			# increment the stats counter
			stats["late_misses"] += 1
			# remove the cache file
			log.debug(f"Removing old negative cache file for '{oci_target}'.")
			os.remove(cache_file_negative)

	# increment the stats counter
	stats["hits" if cache_hit else "misses"] += 1

	if not cache_hit:
		log.debug(f"No cache file for '{oci_target}'")

		try:
			container = client.remote.get_container(oci_target)
			client.remote.load_configs(container)
			manifest = client.remote.get_manifest(container)
			log.debug(f"Got manifest for '{oci_target}'.")
			ret["up-to-date"] = True
			ret["reason"] = "manifest_exists"
			ret["manifest"] = manifest
		except Exception as e:
			message: str = str(e)
			ret["up-to-date"] = False
			ret["reason"] = "exception"
			ret["exception"] = message  # don't store ValueError(e) as it's not json serializable
			# A known-good cache miss.
			if ": Not Found" in message:
				ret["reason"] = "not_found"
			else:
				# log warning so we implement handling above. @TODO: some "unauthorized" errors pop up sometimes
				log.warning(f"Failed to get manifest for '{oci_target}': {e}")

		# increment stats counter
		stats["miss_positive" if ret["up-to-date"] else "miss_negative"] += 1

		# stamp it with milliseconds since epoch
		ret["cache_timestamp"] = datetime.datetime.now().timestamp()
		# write to cache, positive or negative.
		cache_file = cache_file_positive if ret["up-to-date"] else cache_file_negative
		with open(cache_file, "w") as f:
			f.write(json.dumps(ret, indent=4, sort_keys=True))

	return ret


# read the targets.json file passed as first argument as a json object
with open(sys.argv[1]) as f:
	targets = json.load(f)

# Second argument is CHECK_OCI=yes/no, default no
check_oci = sys.argv[2] == "yes" if len(sys.argv) > 2 else False

# massage the targets into their full info invocations (sans-command)
uptodate_artifacts = []

oci_target_map = {}
for target in targets:
	if not target["config_ok"]:
		log.warning(f"Failed config up-to-date check target, ignoring: '{target}'")
		# @TODO this probably should be a showstopper
		continue

	oci_target = target["out"]["artifact_full_oci_target"]
	if oci_target in oci_target_map:
		log.warning(f"Duplicate oci_target: {oci_target}")
		continue

	oci_target_map[oci_target] = target

# run through the targets and see if they are up-to-date.
oci_infos = []
for oci_target in oci_target_map:
	orig_target = oci_target_map[oci_target]
	orig_target["oci"] = {}
	orig_target["oci"] = check_oci_up_to_date_cache(oci_target, check_oci)
	oci_infos.append(orig_target)

# Go, Copilot!
log.info(
	f"OCI cache stats 1:  lookups={stats['lookups']} skipped={stats['skipped']} hits={stats['hits']}  misses={stats['misses']}  hits_positive={stats['hits_positive']}  hits_negative={stats['hits_negative']}  late_misses={stats['late_misses']}  miss_positive={stats['miss_positive']}  miss_negative={stats['miss_negative']}")
log.info(
	f"OCI cache stats 2:  hit_pct={stats['hits'] / stats['lookups'] * 100:.2f}%  miss_pct={stats['misses'] / stats['lookups'] * 100:.2f}%  late_miss_pct={stats['late_misses'] / stats['lookups'] * 100:.2f}%")

print(json.dumps(oci_infos, indent=4, sort_keys=True))
