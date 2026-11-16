#!/usr/bin/env python3
"""Merge the suite's Claude Code settings into a project's own settings.json.

Usage: settings-merge.py TEMPLATE DEST OWNED

TEMPLATE is the suite template (placeholders already replaced), DEST the project's
.claude/settings.json (may be missing), OWNED a JSON file listing the rows the suite installed
last time (updated here). The result keeps the user's own keys and permission rows, adds or
refreshes the suite rows, and drops rows the suite owned before but no longer ships.
Exit status: 0 on success, 1 when TEMPLATE or DEST is not valid JSON.
"""

import json
import sys
from pathlib import Path

HOOK_MARK = "qs-run.sh"


def load(path: Path) -> dict:
    """Return the JSON object stored in path, or {} when the file is missing or empty."""
    if not path.is_file() or not path.read_text(encoding="utf-8").strip():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def merge_rows(current: list, shipped: list, owned: list) -> list:
    """Keep the user's rows, drop retired suite rows, add the shipped ones, no duplicates."""
    rows = [r for r in current if r not in owned or r in shipped]
    rows += [r for r in shipped if r not in rows]
    return rows


def merge_hooks(current: dict, shipped: dict) -> dict:
    """Replace the suite's hook entries (commands naming qs-run.sh) by the shipped ones."""
    out = dict(current)
    for event, entries in shipped.items():
        keep = [e for e in out.get(event, []) if HOOK_MARK not in json.dumps(e)]
        out[event] = keep + entries
    return out


def main(argv: list) -> int:
    """Merge TEMPLATE into DEST and rewrite OWNED; return the exit status."""
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 1
    tpl_p, dst_p, own_p = (Path(a) for a in argv[1:])
    try:
        tpl, dst, own = load(tpl_p), load(dst_p), load(own_p)
    except json.JSONDecodeError as exc:
        print(f"[settings-merge] invalid JSON: {exc}", file=sys.stderr)
        return 1
    result = dict(dst)
    for key, val in tpl.items():
        if key == "permissions":
            continue
        if key == "hooks":
            result[key] = merge_hooks(dst.get(key, {}), val)
        elif key not in result:
            result[key] = val
    perms = dict(dst.get("permissions", {}))
    shipped = tpl.get("permissions", {})
    owned = own.get("permissions", {})
    for kind in sorted(set(shipped) | set(owned)):
        rows = merge_rows(perms.get(kind, []), shipped.get(kind, []), owned.get(kind, []))
        if rows:
            perms[kind] = rows
        else:
            perms.pop(kind, None)
    if perms:
        result["permissions"] = perms
    dst_p.parent.mkdir(parents=True, exist_ok=True)
    dst_p.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    own_p.write_text(json.dumps({"permissions": shipped}, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
