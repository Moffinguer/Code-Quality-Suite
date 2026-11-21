#!/usr/bin/env python3
"""Merge the suite's Claude Code settings into a project's own settings.json.

Usage: settings-merge.py TEMPLATE DEST OWNED

TEMPLATE is the suite template (placeholders already replaced), DEST the project's
.claude/settings.json (may be missing), OWNED a JSON file listing the rows the suite added to
that project (updated here). The result keeps the user's own keys and permission rows, adds or
refreshes the suite rows, and drops rows the suite added before but no longer ships (never a
deny row). A row the user already had when the suite first shipped it is the user's, not owned.
DEST may start with a UTF-8 BOM (kept on write) and contain // and /* */ comments (dropped).
Exit status: 0 on success, and also when DEST cannot be read (a warning is printed and the file
is left untouched); 1 on a bad command line or an invalid TEMPLATE.
"""

import json
import sys
from pathlib import Path

HOOK_MARK = "qs-run.sh"
BOM = "﻿"


def strip_comments(text: str) -> str:
    """Return text without // and /* */ comments found outside JSON strings."""
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        ch, two = text[i], text[i : i + 2]
        if in_str:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
            out.append(ch)
        elif two == "//":
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif two == "/*":
            end = text.find("*/", i + 2)
            i = n if end < 0 else end + 1
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def load(path: Path) -> tuple:
    """Return (object, had_bom) of the JSON file at path; ({}, False) when missing or empty.

    Raises json.JSONDecodeError when the content is not valid JSON.
    """
    if not path.is_file():
        return {}, False
    text = path.read_text(encoding="utf-8")
    bom = text.startswith(BOM)
    text = strip_comments(text.lstrip(BOM))
    return (json.loads(text) if text.strip() else {}), bom


def dedupe(rows: list) -> list:
    """Return rows without repeated entries, keeping the first occurrence and the order."""
    seen, out = [], []
    for row in rows:
        if row not in seen:
            seen.append(row)
            out.append(row)
    return out


def merge_rows(kind: str, current: list, shipped: list, owned: list) -> tuple:
    """Return (rows, newly_owned) for one permission list.

    Retired suite rows (owned, no longer shipped) go away except in deny. A shipped row the user
    already had and the suite never added stays the user's: it is not recorded as owned.
    """
    keep = [r for r in current if r in shipped or r not in owned or kind == "deny"]
    rows = dedupe(keep + [r for r in shipped if r not in keep])
    mine = [r for r in shipped if r in owned or r not in current]
    return rows, mine


def merge_hooks(current: dict, shipped: dict) -> dict:
    """Replace the suite's hook entries (commands naming qs-run.sh) by the shipped ones."""
    out = dict(current)
    for event, entries in shipped.items():
        keep = [e for e in out.get(event, []) if HOOK_MARK not in json.dumps(e)]
        out[event] = keep + entries
    return out


def merge(tpl: dict, dst: dict, own: dict) -> tuple:
    """Return (merged settings, new owned rows) for the loaded template, project file, owned."""
    result = dict(dst)
    for key, val in tpl.items():
        if key == "hooks":
            result[key] = merge_hooks(dst.get(key, {}), val)
        elif key != "permissions" and key not in result:
            result[key] = val
    perms = dict(dst.get("permissions", {}))
    shipped, owned, mine = tpl.get("permissions", {}), own.get("permissions", {}), {}
    for kind in sorted(set(shipped) | set(owned) | set(perms)):
        rows, mine[kind] = merge_rows(
            kind, perms.get(kind, []), shipped.get(kind, []), owned.get(kind, [])
        )
        if rows:
            perms[kind] = rows
        else:
            perms.pop(kind, None)
    if perms:
        result["permissions"] = perms
    return result, {"permissions": {k: v for k, v in mine.items() if v}}


def main(argv: list) -> int:
    """Merge TEMPLATE into DEST and rewrite OWNED; return the exit status."""
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 1
    tpl_p, dst_p, own_p = (Path(a) for a in argv[1:])
    try:
        tpl, _ = load(tpl_p)
    except json.JSONDecodeError as exc:
        print(f"[settings-merge] invalid template: {exc}", file=sys.stderr)
        return 1
    try:
        dst, bom = load(dst_p)
        own, _ = load(own_p)
    except json.JSONDecodeError as exc:
        print(
            f"[settings-merge] WARN {dst_p}: invalid JSON ({exc}); suite rows not merged",
            file=sys.stderr,
        )
        return 0
    result, mine = merge(tpl, dst, own)
    dst_p.parent.mkdir(parents=True, exist_ok=True)
    dst_p.write_text((BOM if bom else "") + json.dumps(result, indent=2) + "\n", encoding="utf-8")
    own_p.parent.mkdir(parents=True, exist_ok=True)
    own_p.write_text(json.dumps(mine, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
