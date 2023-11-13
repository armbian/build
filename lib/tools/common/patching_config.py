# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹
#  SPDX-License-Identifier: GPL-2.0
#  Copyright (c) 2023 Ricardo Pardini <ricardo@pardini.net>
#  This file is a part of the Armbian Build Framework https://github.com/armbian/build/
# ‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹‹

import logging

import yaml

log: logging.Logger = logging.getLogger("patching_config")


class PatchingAutoPatchMakefileDTConfig:

	def __init__(self, data: dict):
		self.config_var: str = data.get("config-var", None)
		self.directory: str = data.get("directory", None)

	def __str__(self):
		return f"PatchingAutoPatchMakefileDTConfig(config-var={self.config_var}, directory={self.directory})"


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

	def read_yaml_config(self, yaml_config_file_path):
		with open(yaml_config_file_path) as f:
			yaml_config = yaml.load(f, Loader=yaml.FullLoader)
		return yaml_config
