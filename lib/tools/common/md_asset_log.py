#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2023 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
import logging

from . import armbian_utils as armbian_utils

log: logging.Logger = logging.getLogger("md_asset_log")

ASSET_LOG_BASE = armbian_utils.get_from_env("ASSET_LOG_BASE")


def write_md_asset_log(file: str, contents: str):
	"""Log a message to the asset log file."""
	if ASSET_LOG_BASE is None:
		log.debug(f"ASSET_LOG_BASE not defined; here's the contents:\n{contents}")
		return
	target_file = ASSET_LOG_BASE + file
	with open(target_file, "w") as asset_log:
		asset_log.write(contents)
	log.debug(f"- Wrote to {target_file}.")


class SummarizedMarkdownWriter:
	def __init__(self, file_name, title):
		self.file_name = file_name
		self.title = title
		self.summary: list[str] = []
		self.contents = ""

	def __enter__(self):
		return self

	def __exit__(self, *args):
		write_md_asset_log(self.file_name, self.get_summarized_markdown())
		log.info(f"Summary: {self.title}: {'; '.join(self.summary)}")

	def add_summary(self, summary):
		self.summary.append(summary)

	def write(self, text):
		self.contents += text

	# see https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/organizing-information-with-collapsed-sections
	def get_summarized_markdown(self):
		if len(self.title) == 0:
			raise Exception("Markdown Summary Title not set")
		if len(self.summary) == 0:
			raise Exception("Markdown Summary not set")
		if self.contents == "":
			raise Exception("Markdown Contents not set")
		return f"<details><summary>{self.title}: {'; '.join(self.summary)}</summary>\n<p>\n\n{self.contents}\n\n</p></details>\n"

	def get_readme_markdown(self):
		if len(self.title) == 0:
			raise Exception("Markdown Summary Title not set")
		if len(self.summary) == 0:
			raise Exception("Markdown Summary not set")
		if self.contents == "":
			raise Exception("Markdown Contents not set")
		return f"#### {self.title}: {'; '.join(self.summary)}\n\n{self.contents}\n\n"


def get_gh_pages_workflow_script():
	return """
name: publish-ghpages

on:
  workflow_dispatch:
  push:
    branches:
      - '*'

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      # Do NOT checkout this. It is a kernel tree and takes a long time, and it's not necessary.
      - name: Grab README.md
        env:
          BRANCH_NAME: ${{ github.head_ref || github.ref_name }}
        run: |
          curl -s https://raw.githubusercontent.com/${{ github.repository }}/${BRANCH_NAME}/README.md > README.md
          ls -la README.md
      
      # install grip via pip, https://github.com/joeyespo/grip; rpardini's fork https://github.com/rpardini/grip
      - name: Install grip
        run: |
          pip3 install https://github.com/rpardini/grip/archive/refs/heads/master.tar.gz

      - name: Run grip to gen  ${{ github.head_ref || github.ref_name }}
        env:
          BRANCH_NAME: ${{ github.head_ref || github.ref_name }}
        run: |
          mkdir -p public
          grip README.md --context=${{ github.repository }} --title="${BRANCH_NAME}" --wide --user-content --export "public/${BRANCH_NAME}.html" || true
          ls -la public/

      - name: Deploy to GitHub Pages (gh-pages branch)
        if: success()
        uses: crazy-max/ghaction-github-pages@v3
        with:
          target_branch: gh-pages
          build_dir: public
          keep_history: true
          jekyll: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
"""
