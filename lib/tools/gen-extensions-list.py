#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
#
# Generate the Armbian build-framework extensions reference (Markdown) from the
# `# @description` headers in extensions/**/*.sh. Prints the full page to stdout.
#
# Extension authors document an extension with a one-line header near the top of
# the file:
#
#   # @description <one sentence or two describing what the extension does>
#   # @doc-page /build-framework/extensions/<slug>/   # optional: link to a dedicated page
#
# This page is consumed by the documentation repo's "pull extensions" workflow.

import re
import sys
from pathlib import Path

FRONT_MATTER = '''---
seo_title: "Armbian build extensions list & ENABLE_EXTENSIONS"
description: "Alphabetical reference of official Armbian build framework extensions, how to enable them with ENABLE_EXTENSIONS, and what each one does."
---
'''

INTRO = '''# Extensions Reference

Alphabetical reference of all official Armbian build framework extensions.
Extensions live in the [`extensions/`](https://github.com/armbian/build/tree/main/extensions)
directory of the build repository.

To enable one or more extensions:

```bash
./compile.sh BOARD=... BRANCH=... ENABLE_EXTENSIONS="ext-name,another-ext"
```

!!! info "This page is generated"
    Each entry comes from the `# @description` header of the extension's source
    file in `armbian/build`. To change a description, edit that header — not this
    page. Extensions with a dedicated page are linked from their entry.
'''


def extensions_root():
    # lib/tools/gen-extensions-list.py -> repo root is two levels up
    return Path(__file__).resolve().parents[2] / "extensions"


def collect(root: Path):
    exts = {}
    for sh in root.rglob("*.sh"):
        text = sh.read_text(errors="replace")
        m = re.search(r"^#\s*@description\s+(.+?)\s*$", text, re.MULTILINE)
        if not m:
            continue
        name = sh.stem
        desc = m.group(1).strip()
        dp = re.search(r"^#\s*@doc-page\s+(\S+)\s*$", text, re.MULTILINE)
        exts[name] = {"desc": desc, "doc_page": dp.group(1) if dp else None}
    return exts


def render(exts):
    out = [FRONT_MATTER, "", INTRO, ""]
    for name in sorted(exts, key=str.lower):
        e = exts[name]
        out.append(f"## {name}")
        out.append("")
        out.append(e["desc"])
        if e["doc_page"]:
            out.append("")
            out.append(f"See: [{name} extension]({e['doc_page']})")
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main():
    root = extensions_root()
    if not root.is_dir():
        sys.exit(f"extensions directory not found: {root}")
    exts = collect(root)
    if not exts:
        sys.exit("no extensions with a '# @description' header were found")
    sys.stderr.write(f"gen-extensions-list: {len(exts)} extensions\n")
    sys.stdout.write(render(exts))


if __name__ == "__main__":
    main()
