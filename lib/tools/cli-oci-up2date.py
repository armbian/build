import logging
import os
import sys

import oras.client
import oras.logger

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common import armbian_utils

# Prepare logging
armbian_utils.setup_logging()
log: logging.Logger = logging.getLogger("mapper-oci-up-to-date")

# Extra logging for ORAS library
oras.logger.setup_logger(quiet=(not armbian_utils.is_debug()), debug=(armbian_utils.is_debug()))

client = oras.client.OrasClient(insecure=False)
log.info(f"OCI client version: {client.version()}")

oci_target = "ghcr.io/armsurvivors/armbian-release/uboot-rockpro64-edge:2025.01-S6d41-P295c-Ha5a3-V9ecd-B1e5e-R448a"

container = client.get_container(oci_target)
manifest = client.get_manifest(container)
log.debug(f"Got manifest for existing '{oci_target}'.")

oci_target_does_not_exist = "ghcr.io/armsurvivors/armbian-release/uboot-rockpro64-edge:does-not-exist"
try:
	container = client.get_container(oci_target_does_not_exist)
	manifest = client.get_manifest(container)
	log.info(f"Got manifest for non-existing '{oci_target_does_not_exist}'.")
except Exception as e:
	message: str = str(e)
	# A known-good cache miss.
	if ": Not Found" in message:
		log.info("Got expected 'Not Found' error for non-existing OCI target.")
	else:
		log.warning(f"Failed to get manifest for '{oci_target_does_not_exist}': {e}")
