#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
# Fix binman's use of pkg_resources (removed in setuptools >= 82)
# by migrating to importlib.resources.
#
# Safe for all U-Boot versions: no-op if pkg_resources is not used.
# Can be removed once all BOOTBRANCH versions are >= v2025.10.

function pre_config_uboot_target__fix_binman_pkg_resources() {
	local control_py="tools/binman/control.py"

	# Skip if file doesn't exist or doesn't use pkg_resources
	[[ -f "${control_py}" ]] || return 0
	grep -q 'import pkg_resources' "${control_py}" || return 0

	display_alert "Patching binman" "migrating pkg_resources to importlib.resources" "info"

	python3 << 'PYTHON_SCRIPT'
import re

control_py = "tools/binman/control.py"

with open(control_py, "r") as f:
    content = f.read()

# 1. Remove "import pkg_resources" line
content = re.sub(r'^import pkg_resources\b[^\n]*\n', '', content, flags=re.MULTILINE)

# 2. Ensure importlib_resources alias is available
has_importlib_alias = 'importlib_resources' in content
has_importlib_dotted = re.search(r'^import importlib\.resources\s*$', content, flags=re.MULTILINE)

if not has_importlib_alias and has_importlib_dotted:
    # New U-Boot (v2024.01+): has "import importlib.resources" without alias
    content = re.sub(
        r'^import importlib\.resources\s*$',
        'import importlib.resources as importlib_resources',
        content, count=1, flags=re.MULTILINE
    )
    # Update existing dotted usage to use the alias
    content = re.sub(r'\bimportlib\.resources\.', 'importlib_resources.', content)
elif not has_importlib_alias:
    # Old U-Boot (<=v2023.x): no importlib.resources at all
    import_block = (
        'try:\n'
        '    import importlib.resources as importlib_resources\n'
        '    importlib_resources.files\n'
        'except (ImportError, AttributeError):\n'
        '    import importlib_resources\n'
    )
    # Insert after the last top-level import line
    lines = content.split('\n')
    last_import_idx = 0
    for i, line in enumerate(lines):
        if re.match(r'^(?:import |from \S+ import )', line):
            last_import_idx = i
    lines.insert(last_import_idx + 1, import_block)
    content = '\n'.join(lines)

# 3. Replace pkg_resources.resource_string(__name__, X)
#    with importlib_resources.files(__package__).joinpath(X).read_bytes()
content = re.sub(
    r'pkg_resources\.resource_string\s*\(\s*__name__\s*,\s*(.+?)\s*\)',
    r'importlib_resources.files(__package__).joinpath(\1).read_bytes()',
    content
)

# 4. Replace pkg_resources.resource_listdir(__name__, X)
#    with [r.name for r in importlib_resources.files(__package__).joinpath(X).iterdir() if r.is_file()]
content = re.sub(
    r'pkg_resources\.resource_listdir\s*\(\s*__name__\s*,\s*(.+?)\s*\)',
    r'[r.name for r in importlib_resources.files(__package__).joinpath(\1).iterdir() if r.is_file()]',
    content
)

with open(control_py, "w") as f:
    f.write(content)

print("binman control.py patched successfully")
PYTHON_SCRIPT
}
