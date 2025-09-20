# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹

import logging
import re

import yaml

log: logging.Logger = logging.getLogger("patching_config")


class PatchingAutoPatchMakefileDTConfig:

	def __init__(self, data: dict):
		self.config_var: str = data.get("config-var", None)
		self.directory: str = data.get("directory", None)
		self.incremental: bool = not not data.get("incremental", False)

	def __str__(self):
		return f"PatchingAutoPatchMakefileDTConfig(config-var={self.config_var}, directory={self.directory}, incremental={self.incremental})"


class PatchingDTSDirectoryConfig:
	def __init__(self, data: dict):
		self.source: str = data.get("source", None)
		self.target: str = data.get("target", None)

	def __str__(self):
		return f"PatchingDTSDirectoryConfig(source={self.source}, target={self.target})"


class PatchingOverlayDirectoryConfig:
	def __init__(self, data: dict):
		self.source: str = data.get("source", None)
		self.target: str = data.get("target", None)

	def __str__(self):
		return f"PatchingOverlayDirectoryConfig(source={self.source}, target={self.target})"


class PatchingOverlaySupportConfig:
	def __init__(self, data: dict):
		self.enabled: bool = data.get("enabled", False)
		self.overlay_pattern: str = data.get("overlay-pattern", r"^([a-zA-Z0-9_-]+)-dtbs\s*:=\s*(.+)$")
		self.overlay_extension: str = data.get("overlay-extension", ".dtbo")
		self.base_extension: str = data.get("base-extension", ".dtb")
		# Compile the regex pattern for efficiency
		try:
			self.compiled_overlay_pattern = re.compile(self.overlay_pattern)
		except re.error as e:
			log.warning(f"Invalid overlay pattern regex '{self.overlay_pattern}': {e}")
			self.compiled_overlay_pattern = None

	def is_overlay_definition_line(self, line: str) -> bool:
		"""Check if a line matches the overlay definition pattern"""
		if not self.enabled or not self.compiled_overlay_pattern:
			return False
		return bool(self.compiled_overlay_pattern.match(line.strip()))

	def parse_overlay_definition(self, line: str) -> tuple[str, list[str]] | None:
		"""Parse an overlay definition line and return (target_name, [dependencies])"""
		if not self.enabled or not self.compiled_overlay_pattern:
			return None
		
		match = self.compiled_overlay_pattern.match(line.strip())
		if not match:
			return None
		
		target_name = match.group(1)
		dependencies_str = match.group(2)
		dependencies = [dep.strip() for dep in dependencies_str.split() if dep.strip()]
		
		return target_name, dependencies

	def is_overlay_file(self, filename: str) -> bool:
		"""Check if a filename is an overlay file"""
		return filename.endswith(self.overlay_extension)

	def is_base_dtb_file(self, filename: str) -> bool:
		"""Check if a filename is a base DTB file"""
		return filename.endswith(self.base_extension)

	def __str__(self):
		return f"PatchingOverlaySupportConfig(enabled={self.enabled}, overlay_pattern={self.overlay_pattern}, overlay_extension={self.overlay_extension}, base_extension={self.base_extension})"


class PatchingToGitConfig:
	def __init__(self, data: dict):
		self.do_not_commit_files: list[str] = data.get("do-not-commit-files", [])
		self.do_not_commit_regexes: list[str] = data.get("do-not-commit-regexes", [])

	def __str__(self):
		return f"PatchingToGitConfig(do_not_commit_files={self.do_not_commit_files}, do_not_commit_regexes={self.do_not_commit_regexes})"


class PatchingConfig:
	def __init__(self, yaml_config_file_paths: list[str]):
		self.yaml_config_file_paths = yaml_config_file_paths
		if len(yaml_config_file_paths) == 0:
			self.yaml_config = {}
		else:
			# I'm lazy, single one for now.
			self.yaml_config = self.read_yaml_config(yaml_config_file_paths[0])["config"]

		self.patches_to_git_config: PatchingToGitConfig = PatchingToGitConfig(self.yaml_config.get("patches-to-git", {}))

		# Parse out the different parts of the config
		# DT Makefile auto-patch config
		self.autopatch_makefile_dt_configs: list[PatchingAutoPatchMakefileDTConfig] = [
			PatchingAutoPatchMakefileDTConfig(data) for data in self.yaml_config.get("auto-patch-dt-makefile", [])
		]
		self.has_autopatch_makefile_dt_configs: bool = len(self.autopatch_makefile_dt_configs) > 0

		# DTS directories to copy config
		self.dts_directories: list[PatchingDTSDirectoryConfig] = [
			PatchingDTSDirectoryConfig(data) for data in self.yaml_config.get("dts-directories", [])
		]
		self.has_dts_directories: bool = len(self.dts_directories) > 0

		# Overlay directories to copy config
		self.overlay_directories: list[PatchingOverlayDirectoryConfig] = [
			PatchingOverlayDirectoryConfig(data) for data in self.yaml_config.get("overlay-directories", [])
		]
		self.has_overlay_directories: bool = len(self.overlay_directories) > 0

		# Overlay support configuration
		self.overlay_support: PatchingOverlaySupportConfig = PatchingOverlaySupportConfig(self.yaml_config.get("overlay-support", {}))
		self.has_overlay_support: bool = self.overlay_support.enabled

	def read_yaml_config(self, yaml_config_file_path):
		with open(yaml_config_file_path) as f:
			yaml_config = yaml.load(f, Loader=yaml.FullLoader)
		return yaml_config
