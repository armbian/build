#!/usr/bin/env python3
"""Collect the deterministic facts an artifact prediction needs.

Everything here is read straight from the build framework - board configs,
family configs, the patch tree, the artifact registry. Nothing is inferred and
nothing is asked of a model; this is the ground truth that predict.py reasons
over, and the vocabulary its answer is validated against.

Usage: collect_facts.py [--root .] [--out facts.json]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

# Board files carry a support-status suffix: .conf = supported, .csc = community,
# .wip = work in progress, .tvb = TV box, .eos = end of support.
BOARD_SUFFIXES = (".conf", ".csc", ".wip", ".tvb", ".eos")

# Assignments we care about, with or without a `declare -g` prefix and leading
# whitespace: BOARD_NAME="Foo Bar" / declare -g KERNEL_TARGET="current,edge"
def _assign_re(key: str) -> re.Pattern:
    return re.compile(
        r'^\s*(?:declare\s+-g\s+)?%s=(?:"([^"]*)"|\'([^\']*)\'|(\S+))' % key,
        re.MULTILINE,
    )


KEYS = ("BOARD_NAME", "BOARDFAMILY", "KERNEL_TARGET", "BOOTCONFIG", "BOARD_MAINTAINER")
PATTERNS = {k: _assign_re(k) for k in KEYS}
PATCHDIR_RE = _assign_re("KERNELPATCHDIR")
BOOTPATCHDIR_RE = _assign_re("BOOTPATCHDIR")


def _first(pattern: re.Pattern, text: str) -> str:
    m = pattern.search(text)
    if not m:
        return ""
    return next((g for g in m.groups() if g is not None), "")


def _all(pattern: re.Pattern, text: str) -> list[str]:
    """Every value a key is assigned, kept verbatim - templates included.

    Values are frequently templated (KERNELPATCHDIR="archive/sunxi-${KERNEL_MAJOR_MINOR}")
    or defaulted (BOOTPATCHDIR="${BOOTPATCHDIR:-"v2026.07-sunxi"}"). Resolving
    those needs the branch, which only the build knows, so they are passed
    through as written and matched by prefix downstream.
    """
    out = []
    for m in pattern.finditer(text):
        val = next((g for g in m.groups() if g is not None), "")
        # `VAR="${VAR:-"default"}"` closes the outer quote early, so the captured
        # value is just `${VAR:-`. Recover the default from the raw line.
        if val.endswith(":-") or "${" in val:
            inner = re.search(r':-"?([^"}\s]+)"?\}', m.group(0))
            if inner:
                val = inner.group(1)
        for v in val.split():
            v = v.strip('"\'}').removeprefix("archive/")
            if v:
                out.append(v)
    return sorted(set(out))


def collect_boards(root: Path) -> list[dict]:
    boards = []
    bdir = root / "config" / "boards"
    for f in sorted(bdir.iterdir()) if bdir.is_dir() else []:
        if f.suffix not in BOARD_SUFFIXES or not f.is_file():
            continue
        text = f.read_text(errors="replace")
        boards.append(
            {
                "board": f.stem,
                "file": str(f.relative_to(root)),
                "status": f.suffix.lstrip("."),
                "family": _first(PATTERNS["BOARDFAMILY"], text),
                "branches": [
                    b.strip()
                    for b in _first(PATTERNS["KERNEL_TARGET"], text).split(",")
                    if b.strip()
                ],
                "bootconfig": _first(PATTERNS["BOOTCONFIG"], text),
            }
        )
    return boards


def collect_families(root: Path) -> list[dict]:
    """Family configs, plus the patch dirs each one names.

    KERNELPATCHDIR is frequently set inside a `case $BRANCH` block, so a static
    read cannot say which branch owns which dir. Every dir a family mentions is
    reported as a candidate and labelled as such - predict.py is told to treat
    these as hints, never as a mapping.
    """
    families = []
    fdir = root / "config" / "sources" / "families"
    if not fdir.is_dir():
        return families
    for f in sorted(fdir.rglob("*")):
        if f.suffix not in (".conf", ".inc") or not f.is_file():
            continue
        text = f.read_text(errors="replace")
        entry = {
            "family": f.stem,
            "file": str(f.relative_to(root)),
            "kernel_patch_dirs": _all(PATCHDIR_RE, text),
            "uboot_patch_dirs": _all(BOOTPATCHDIR_RE, text),
        }
        includes = re.findall(r'source\s+"\$\{BASH_SOURCE%/\*\}/([^"]+)"', text)
        if includes:
            entry["includes"] = includes
        families.append(entry)
    return families


def collect_artifacts(root: Path) -> list[str]:
    """The artifact names ./compile.sh accepts, from the registry itself."""
    reg = root / "lib" / "functions" / "artifacts" / "artifacts-registry.sh"
    if not reg.is_file():
        return []
    # ARMBIAN_ARTIFACTS_TO_HANDLERS_DICT maps every name the CLI accepts (keys,
    # including aliases like u-boot/uboot) to its handler.
    return sorted(set(re.findall(r'\["([a-z0-9_-]+)"\]=', reg.read_text(errors="replace"))))


def collect_patch_tree(root: Path) -> dict:
    def subdirs(rel: str) -> list[str]:
        d = root / rel
        return sorted(p.name for p in d.iterdir() if p.is_dir()) if d.is_dir() else []

    return {
        "kernel": subdirs("patch/kernel/archive"),
        "uboot": subdirs("patch/u-boot"),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--out", default="facts.json")
    args = ap.parse_args()
    root = Path(args.root).resolve()

    facts = {
        "boards": collect_boards(root),
        "families": collect_families(root),
        "artifacts": collect_artifacts(root),
        "patch_dirs": collect_patch_tree(root),
    }
    facts["counts"] = {
        "boards": len(facts["boards"]),
        "families": len(facts["families"]),
        "artifacts": len(facts["artifacts"]),
    }

    Path(args.out).write_text(json.dumps(facts, indent=1, sort_keys=True))
    print(
        f"facts: {facts['counts']['boards']} boards, "
        f"{facts['counts']['families']} family configs, "
        f"{facts['counts']['artifacts']} artifacts -> {args.out}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
