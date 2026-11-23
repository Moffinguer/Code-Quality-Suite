#!/usr/bin/env python3
"""ci-rules-drift - G8: the tracked CI rules file never weakens a default without a reason.

  python3 tools/ci-rules-drift.py [<file>]      (default: .github/quality-rules.json)

A key weakens a default when it lowers a gate level, disables a check or relaxes a policy value
below the default of engine/policy.py (read-only). Every weakening needs a sibling key `why`
(or `<key>_why`) holding a non-empty text. One finding per line: `<file>: <path>: <message>`.
With QS_CI_FORMAT=github the lines are GitHub annotations (`::error file=...,line=...::`).

Exit codes: 0 no finding, 1 findings, 2 unreadable file.
"""

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402

LEVELS = policy.LEVELS
DEFAULT_FILE = ".github/quality-rules.json"
# strictness order of the keys with an enumeration, strictest first
ORDERS = {
    "branches.enforce": ["block", "warn", "off"],
    "commit.files": ["block", "warn", "off"],
    "encoding.mojibake": ["block", "warn", "off"],
    "commit.charset": ["ascii", "utf-8", "any"],
    "branches.pom_version": ["update", "check", "snapshot", "off"],
}
# boolean keys whose default True is the strict value
STRICT_TRUE = ("encoding.enabled", "commit.conventional", "branches.require_children_merged")


def default_at(path):
    """Look a dotted key path up in the policy defaults.

    Args:
        path: dotted key path such as 'commit.subject_max'.

    Returns:
        The default value, or None when the path is not a default.
    """
    cur = policy.DEFAULTS
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def weakening(path, value):
    """Say whether a value is weaker than the default of its key.

    Args:
        path: dotted key path of the value.
        value: the value found in the CI rules file.

    Returns:
        str: a short description of the weakening, or '' when the value is not weaker.
    """
    last = path.rsplit(".", 1)[-1]
    default = default_at(path)
    if last == "level" and value in LEVELS:
        base = default if default in LEVELS else "standard"
        if LEVELS.index(value) < LEVELS.index(base):
            return f"gate level lowered to '{value}' (default '{base}')"
    if last == "enabled" and value is False and default is not False:
        return "check disabled"
    if path in STRICT_TRUE and value is False:
        return "check disabled"
    order = ORDERS.get(path)
    if order and value in order and default in order and order.index(value) > order.index(default):
        return f"'{value}' is weaker than the default '{default}'"
    if (
        path == "commit.subject_max"
        and isinstance(value, int)
        and isinstance(default, int)
        and value > default
    ):
        return f"subject limit raised to {value} (default {default})"
    return ""


def has_why(node, key):
    """Say whether an object justifies a key with a sibling `why` or `<key>_why`.

    Args:
        node: the object that holds the key (dict).
        key: the key name.

    Returns:
        bool: True when a non-empty text justifies the key.
    """
    for name in ("why", f"{key}_why"):
        text = node.get(name)
        if isinstance(text, str) and text.strip():
            return True
    return False


def walk(node, prefix, out):
    """Collect the weakening keys of an object tree.

    Args:
        node: the object to scan (dict); other types are ignored.
        prefix: dotted path of `node` ('' for the root).
        out: list that receives (path, description) pairs.

    Returns:
        None; `out` is extended.
    """
    if not isinstance(node, dict):
        return
    for key, value in node.items():
        path = f"{prefix}.{key}" if prefix else key
        if key == "why" or key.endswith("_why"):
            continue
        desc = weakening(path, value)
        if desc and not has_why(node, key):
            out.append((path, desc))
        walk(value, path, out)


def find_line(raw, path):
    """Find the line of the last key of a path in the raw JSON text (best effort).

    Args:
        raw: the file text.
        path: dotted key path.

    Returns:
        int: the 1-based line number, 1 when the key is not found.
    """
    needle = f'"{path.rsplit(".", 1)[-1]}"'
    for number, line in enumerate(raw.splitlines(), 1):
        if needle in line:
            return number
    return 1


def check_file(path):
    """Check one CI rules file.

    Args:
        path: path of the JSON file.

    Returns:
        list[tuple[str, str, int]]: (key path, message, line) per finding.

    Raises:
        OSError: the file cannot be read.
        ValueError: the file is not valid JSON or not an object.
    """
    with open(path, encoding="utf-8") as fh:
        raw = fh.read()
    data = json.loads(raw)
    if not isinstance(data, dict):
        raise ValueError("the rules file must be a JSON object")
    found = []
    walk(data, "", found)
    return [(p, f"{d}; add a sibling 'why' explaining it", find_line(raw, p)) for p, d in found]


def main(argv):
    """Run the check and print the findings.

    Args:
        argv: command line arguments without the program name: an optional file path.

    Returns:
        int: exit code, 0 clean, 1 findings, 2 unreadable file.
    """
    path = argv[0] if argv else DEFAULT_FILE
    try:
        findings = check_file(path)
    except (OSError, ValueError) as exc:
        print(f"ci-rules-drift: {path}: {exc}", file=sys.stderr)
        return 2
    github = os.environ.get("QS_CI_FORMAT") == "github"
    for key, msg, line in findings:
        if github:
            print(f"::error file={path},line={line}::{key}: {msg}")
        else:
            print(f"{path}: {key}: {msg}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
