#!/usr/bin/env python3
"""
Validate Armbian board configuration files.

Walks each given config/boards/*.{conf,csc,tvb,wip,eos} file and checks
for required / recommended fields. Designed to run in CI on PRs that
touch board configs, but also runnable locally:

    tools/validate-board-config.py config/boards/orangepi5.conf
    tools/validate-board-config.py config/boards/*.conf

Output:
- Plain text findings to stdout (one per line, prefixed by ERROR / WARNING)
- When --github is passed, also emits ::error / ::warning workflow
  commands so GitHub Actions annotates the PR diff
- Exit code 0 if no errors; 1 if any error

Per-extension behavior:
- .conf  (supported)         — full rule set
- .csc   (community)         — full rule set
- .tvb   (TV box)            — full rule set, skip BOOT_FDT_FILE warning
- .wip   (work in progress)  — only BOARD_NAME is an error; rest are warnings
- .eos   (end of support)    — skipped entirely (no point validating dead boards)

The validator does NOT source the bash file (boards have side-effecty
function bodies). It extracts top-level `KEY=value` assignments via
regex, which is enough for the required-field check.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Top-level assignment, optionally with `declare -g`. Captures KEY and value
# (raw, including any quotes — we only care about emptiness here).
_ASSIGN_RE = re.compile(
    r'^(?:(?:export|declare)\s+(?:-[a-zA-Z]+\s+)*)?([A-Z_][A-Z0-9_]*)=(.*)$',
    re.MULTILINE,
)

# Top-level `source ${SRC}/config/boards/<foo>.csc` (or .conf/.tvb/.wip).
# Anchored to start-of-line so a `source` call inside a function body
# (which is always indented) doesn't get followed. Captures the relative
# path under config/boards/ so the validator can resolve it next to the
# child file being validated.
_SOURCE_RE = re.compile(
    r'^source\s+["\']?\$\{?SRC\}?/config/boards/([^"\'\s]+\.(?:conf|csc|tvb|wip))["\']?',
    re.MULTILINE,
)



@dataclass
class Finding:
    severity: str   # "error" | "warning"
    file: str
    field: str
    message: str

    def render(self, github: bool) -> str:
        prefix = self.severity.upper()
        plain = f"{prefix}: {self.file}: {self.field}: {self.message}"
        if not github:
            return plain
        # GitHub Actions workflow command — annotates the PR diff.
        # We point at line 1 since these are file-level checks; the message
        # itself names the field so reviewers know what to fix.
        return (
            f"::{self.severity} file={self.file},line=1::"
            f"{self.field}: {self.message}\n{plain}"
        )


def parse_assignments(text: str) -> dict[str, str]:
    """Extract top-level KEY=VALUE assignments. Last assignment wins."""
    out: dict[str, str] = {}
    for m in _ASSIGN_RE.finditer(text):
        key, value = m.group(1), m.group(2).strip()
        # Strip trailing inline comment (bash semantics: # preceded by
        # whitespace). Unquoted values like `COLOR=#deadbeef` keep the #.
        if value and not (value.startswith('"') or value.startswith("'")):
            m2 = re.search(r'\s#', value)
            if m2:
                value = value[:m2.start()].strip()
        # Strip surrounding matching quotes for the empty-check.
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        out[key] = value
    return out


def collect_inherited_assignments(path: Path, _visited: set[Path] | None = None) -> dict[str, str]:
    """Resolve fields a board inherits via `source ${SRC}/config/boards/<foo>`.

    Some boards (e.g. ayn-odin2{mini,portal}.csc, ayn-thor.csc) consist
    of one `source` line pointing at a base .csc plus a handful of
    overrides for the fields they actually change. Fields the child
    doesn't redeclare — BOARDFAMILY, KERNEL_TARGET, KERNEL_TEST_TARGET
    in the typical case — live in the sourced parent.

    Returns a flat dict of effective fields the parent chain provides,
    in the same shape parse_assignments() returns. Caller merges this
    behind the child's own dict so the child's explicit values still
    win.

    Cycles (a sources b sources a) are guarded by the _visited set;
    missing or unresolvable source targets are silently skipped — the
    main validator will still flag any field that ends up unset.
    """
    if _visited is None:
        _visited = set()
    try:
        resolved = path.resolve()
    except OSError:
        return {}
    if resolved in _visited:
        return {}
    _visited.add(resolved)

    text = path.read_text(errors="replace")
    inherited: dict[str, str] = {}
    for m in _SOURCE_RE.finditer(text):
        sourced = path.parent / m.group(1)
        if not sourced.is_file():
            continue
        # Recurse first so transitive parents are merged behind the
        # immediate parent's fields. Within a single chain, nearest
        # parent's value should win over a more distant ancestor's,
        # which falls out naturally from setdefault's "skip if set".
        ancestors = collect_inherited_assignments(sourced, _visited)
        parent_fields = parse_assignments(sourced.read_text(errors="replace"))
        # Parent's own assignments win over its ancestors; merge in
        # that order, then those become the inheritance pool the
        # caller will lay behind the child.
        for k, v in parent_fields.items():
            inherited.setdefault(k, v)
        for k, v in ancestors.items():
            inherited.setdefault(k, v)
    return inherited


def validate(path: Path) -> list[Finding]:
    ext = path.suffix.lstrip(".")
    if ext == "eos":
        return []  # dead boards aren't validated

    text = path.read_text(errors="replace")
    fields = parse_assignments(text)
    # Layer fields the child inherits via `source ${SRC}/config/boards/<...>`
    # behind its own — child's explicit value wins, parent fills the gaps.
    for k, v in collect_inherited_assignments(path).items():
        fields.setdefault(k, v)

    findings: list[Finding] = []
    fname = str(path)

    def err(field: str, msg: str) -> None:
        # .wip demotes everything except BOARD_NAME to warning
        sev = "error" if (ext != "wip" or field == "BOARD_NAME") else "warning"
        findings.append(Finding(sev, fname, field, msg))

    def warn(field: str, msg: str) -> None:
        findings.append(Finding("warning", fname, field, msg))

    # Required fields (errors except in .wip)
    if not fields.get("BOARD_NAME"):
        err("BOARD_NAME", "required, must be non-empty")

    if not fields.get("BOARD_VENDOR"):
        err("BOARD_VENDOR", "required, must be non-empty")

    if not fields.get("BOARDFAMILY"):
        err("BOARDFAMILY", "required, must match a family under config/sources/families/")

    if not fields.get("KERNEL_TARGET"):
        err("KERNEL_TARGET", "required, must be non-empty")

    # Recommended fields (warnings)
    if not fields.get("BOARD_MAINTAINER"):
        warn("BOARD_MAINTAINER", "recommended, github username — orphan boards rot")

    if not fields.get("INTRODUCED"):
        warn("INTRODUCED", "recommended, year the board first shipped (e.g. 2023)")

    if not fields.get("KERNEL_TEST_TARGET"):
        warn("KERNEL_TEST_TARGET", "recommended, comma-separated list of branches to test (e.g. current,edge)")

    return findings


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="+", help="board config files to validate")
    ap.add_argument(
        "--github",
        action="store_true",
        help="emit GitHub Actions ::error / ::warning workflow commands",
    )
    args = ap.parse_args()

    all_findings: list[Finding] = []
    for f in args.files:
        path = Path(f)
        if not path.is_file():
            print(f"WARNING: {f}: not a file, skipping", file=sys.stderr)
            continue
        if path.suffix.lstrip(".") not in {"conf", "csc", "tvb", "wip", "eos"}:
            print(f"WARNING: {f}: unknown extension, skipping", file=sys.stderr)
            continue
        all_findings.extend(validate(path))

    errors = [f for f in all_findings if f.severity == "error"]
    warnings = [f for f in all_findings if f.severity == "warning"]

    for finding in all_findings:
        print(finding.render(args.github))

    print(
        f"\n{len(errors)} error(s), {len(warnings)} warning(s) "
        f"across {len(args.files)} file(s)",
        file=sys.stderr,
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
