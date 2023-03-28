#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2022-2023 Ricardo Pardini <ricardo@pardini.net>
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
import logging
import re

log: logging.Logger = logging.getLogger("bash_declare_parser")

REGEX_BASH_DECLARE_DOUBLE_QUOTE = r"declare (-[-xr]) (.*?)=\"(.*)\""
REGEX_BASH_DECLARE_SINGLE_QUOTE = r"declare (-[-xr]) (.*?)=\$'(.*)'"
REGEX_BASH_DECLARE_ASSOCIATIVE_ARRAY = r"declare (-[A]) (.*?)=\((.*)\)"
REGEX_BASH_DECLARE_SIMPLE_ARRAY = r"declare (-[a]) (.*?)=\((.*)\)"


class BashDeclareParser:
	def __init__(self, origin: str = 'unknown'):
		self.origin = origin

	def parse_one(self, one_declare):
		all_keys = {}
		count_matches = 0

		# Now parse it with regex-power! it only parses non-array, non-dictionary values, double-quoted.
		for matchNum, match in enumerate(re.finditer(REGEX_BASH_DECLARE_DOUBLE_QUOTE, one_declare, re.DOTALL), start=1):
			count_matches += 1
			value = self.parse_dequoted_value(match.group(2), self.armbian_value_parse_double_quoted(match.group(3)))
			all_keys[match.group(2)] = value

		if count_matches == 0:
			# try for the single-quoted version
			for matchNum, match in enumerate(re.finditer(REGEX_BASH_DECLARE_SINGLE_QUOTE, one_declare, re.DOTALL), start=1):
				count_matches += 1
				value = self.parse_dequoted_value(match.group(2), self.armbian_value_parse_single_quoted(match.group(3)))
				all_keys[match.group(2)] = value

		if count_matches == 0:
			# try for the (A)ssociative Array version
			for matchNum, match in enumerate(re.finditer(REGEX_BASH_DECLARE_ASSOCIATIVE_ARRAY, one_declare, re.DOTALL), start=1):
				count_matches += 1
				all_keys[match.group(2)] = ["@TODO", "bash associative arrays aka dictionaries are not supported yet", match.group(3)]

		if count_matches == 0:
			# try for the simple (a)rray version
			for matchNum, match in enumerate(re.finditer(REGEX_BASH_DECLARE_SIMPLE_ARRAY, one_declare, re.DOTALL), start=1):
				count_matches += 1
				all_keys[match.group(2)] = ["@TODO", "bash simple-arrays are not supported yet", match.group(3)]

		if count_matches == 0:
			log.error(f"** No matches found for Bash declare regex (origin: {self.origin}), line ==>{one_declare}<==")

		return all_keys

	def parse_dequoted_value(self, key, value):
		if ("_LIST" in key) or ("_DIRS" in key) or ("_ARRAY" in key):
			value = self.armbian_value_parse_list(value, " ")
		return value

	def armbian_value_parse_double_quoted(self, value: str):
		# replace "\\\\n" with actual newline
		value = value.replace('\\\\n', "\n")
		value = value.replace('\\\\t', "\t")
		value = value.replace('\\\"', '"')
		return value

	def armbian_value_parse_single_quoted(self, value: str):
		value = value.replace('\\n', "\n")
		value = value.replace('\n', "\n")
		value = value.replace('\\t', "\t")
		value = value.replace('\t', "\t")
		return value

	def armbian_value_parse_list(self, item_value, delimiter):
		ret = []
		for item in item_value.split(delimiter):
			ret.append((item))
		# trim whitespace out of every value
		ret = list(map(str.strip, ret))
		# filter out empty strings
		ret = list(filter(None, ret))
		return ret

	def armbian_value_parse_newline_map(self, item_value):
		lines = item_value.split("\n")
		ret = []
		for line in lines:
			ret.append(self.armbian_value_parse_list(line, ":"))
		return ret
