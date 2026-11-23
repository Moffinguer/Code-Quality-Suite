#!/usr/bin/env python3
"""Duplication and doc-comment metrics for the suite (stdlib only, deterministic).

Usage: tools/codemetrics.py dup|doc [--json] [--enforce] [paths...]

* dup: finds clones of WINDOW (6) or more normalized lines inside each area and reports the
  file:line pairs plus the duplicated share per area. Blank lines, comments, docstrings and
  block closers are ignored before comparing.
* doc: lists functions without a doc comment. Shell: a comment line directly above the
  function line (or a comment on the same line). Python: ast.get_docstring.

Areas and thresholds come from .codemetrics.json at the repository root. Without paths the
areas of that file are scanned; with paths they are scanned as one area named "paths".
Report mode (default) always exits 0; --enforce exits 1 when a threshold is exceeded.
"""

import ast
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, ".codemetrics.json")
DEFAULT_WINDOW = 6
SKIP_DIRS = {"__pycache__", ".git", "node_modules"}
SH_CLOSERS = {"fi", "done", "esac", "}", ";;", ")", "fi;", "done;"}
PY_CLOSERS = {")", "]", "}", "),", "],", "},"}
SH_FUNC = re.compile(
    r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_:.-]*)\s*\(\)\s*\{?|^\s*function\s+([A-Za-z_][A-Za-z0-9_:.-]*)"
)


def load_config(path=CONFIG):
    """Read the metrics configuration.

    Args:
        path: JSON file with window, areas and thresholds.
    Returns:
        The parsed dict, or a config with no areas when the file is missing.
    Raises:
        ValueError: when the file exists but is not valid JSON.
    """
    if not os.path.isfile(path):
        return {"window": DEFAULT_WINDOW, "areas": {}, "thresholds": {}}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def kind_of(path):
    """Classify a source file.

    Args:
        path: file path.
    Returns:
        "py", "sh" or None for files the tool does not measure.
    """
    if path.endswith(".py"):
        return "py"
    if path.endswith(".sh"):
        return "sh"
    try:
        with open(path, encoding="utf-8") as handle:
            first = handle.readline()
    except (OSError, UnicodeDecodeError):
        return None
    if first.startswith("#!"):
        if "python" in first:
            return "py"
        if re.search(r"\b(ba)?sh\b", first):
            return "sh"
    return None


def collect(paths):
    """Expand files and directories into a sorted list of measurable files.

    Args:
        paths: files or directories (relative to the repository root or absolute).
    Returns:
        Sorted list of file paths (relative to ROOT when inside it) of kind py or sh.
    """
    found = set()
    for item in paths:
        full = item if os.path.isabs(item) else os.path.join(ROOT, item)
        if os.path.isfile(full):
            candidates = [full]
        else:
            candidates = []
            for base, dirs, files in os.walk(full):
                dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
                candidates.extend(os.path.join(base, name) for name in sorted(files))
        for cand in candidates:
            if kind_of(cand):
                found.add(os.path.relpath(cand, ROOT).replace(os.sep, "/"))
    return sorted(found)


def read_lines(rel):
    """Read a file as a list of lines.

    Args:
        rel: path relative to ROOT.
    Returns:
        List of lines without line terminators ([] when unreadable).
    """
    try:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            return handle.read().splitlines()
    except (OSError, UnicodeDecodeError):
        return []


def docstring_lines(lines):
    """Find the 1-based line numbers occupied by Python docstrings.

    Args:
        lines: source lines of a Python file.
    Returns:
        Set of line numbers; empty when the source does not parse.
    """
    try:
        tree = ast.parse("\n".join(lines))
    except SyntaxError:
        return set()
    result = set()
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        body = node.body
        if (
            body
            and isinstance(body[0], ast.Expr)
            and isinstance(getattr(body[0], "value", None), ast.Constant)
            and isinstance(body[0].value.value, str)
        ):
            result.update(range(body[0].lineno, body[0].end_lineno + 1))
    return result


def normalized(rel):
    """Normalize a file for clone detection.

    Args:
        rel: path relative to ROOT.
    Returns:
        List of (line_number, text) keeping only code lines: blanks, comments, docstrings and
        block closers are dropped and inner whitespace is collapsed.
    """
    lines = read_lines(rel)
    kind = kind_of(os.path.join(ROOT, rel))
    skip = docstring_lines(lines) if kind == "py" else set()
    closers = PY_CLOSERS if kind == "py" else SH_CLOSERS
    out = []
    for number, raw in enumerate(lines, 1):
        text = " ".join(raw.split())
        if not text or text.startswith("#") or number in skip or text in closers:
            continue
        out.append((number, text))
    return out


def _window_table(per_file, window):
    """Index every window of consecutive normalized lines.

    Args:
        per_file: mapping file -> list of (line_number, text).
        window: window size.
    Returns:
        Dict window-tuple -> list of (file, index) occurrences.
    """
    table = {}
    for rel, rows in per_file.items():
        for index in range(len(rows) - window + 1):
            key = tuple(text for _, text in rows[index : index + window])
            table.setdefault(key, []).append((rel, index))
    return table


def _mark_duplicates(per_file, table, window):
    """Flag the windows and lines that belong to a clone.

    Args:
        per_file: mapping file -> list of (line_number, text).
        table: result of _window_table.
        window: window size.
    Returns:
        (win_flags, line_flags): per file, one bool per window start and one per normalized line.
    """
    win_flags = {rel: [False] * len(rows) for rel, rows in per_file.items()}
    line_flags = {rel: [False] * len(rows) for rel, rows in per_file.items()}
    for spots in table.values():
        if len(spots) < 2:
            continue
        for rel, index in spots:
            win_flags[rel][index] = True
            for offset in range(window):
                line_flags[rel][index + offset] = True
    return win_flags, line_flags


def _clone_runs(per_file, table, win_flags, window):
    """Merge overlapping duplicate windows into clone runs.

    Args:
        per_file: mapping file -> list of (line_number, text).
        table: result of _window_table.
        win_flags: window flags from _mark_duplicates.
        window: window size.
    Returns:
        List of dicts with "lines" (run length) and "locations" (sorted "file:line" strings),
        one per clone group, ordered by first location.
    """
    clones = []
    for rel in sorted(per_file):
        rows = per_file[rel]
        flags = win_flags[rel]
        for index, flag in enumerate(flags):
            if not flag or (index > 0 and flags[index - 1]):
                continue
            spots = table[tuple(text for _, text in rows[index : index + window])]
            if min(spots) != (rel, index):
                continue
            end = index
            while end + 1 < len(flags) and flags[end + 1]:
                end += 1
            locations = sorted(f"{r}:{per_file[r][i][0]}" for r, i in spots)
            clones.append({"lines": end - index + window, "locations": locations})
    return clones


def find_clones(files, window):
    """Detect windows of identical normalized lines.

    Args:
        files: relative paths forming one area (clones are matched inside it only).
        window: number of consecutive normalized lines that makes a clone.
    Returns:
        (clones, dup_lines, total_lines): clones is a list of dicts with "lines" (run length)
        and "locations" (sorted "file:line" strings); dup_lines counts the normalized lines
        covered by a clone; total_lines counts all normalized lines.
    """
    per_file = {rel: normalized(rel) for rel in files}
    table = _window_table(per_file, window)
    win_flags, line_flags = _mark_duplicates(per_file, table, window)
    total = sum(len(rows) for rows in per_file.values())
    dup = sum(flag for flags in line_flags.values() for flag in flags)
    return _clone_runs(per_file, table, win_flags, window), dup, total


def run_dup(areas, window):
    """Run the duplication report on every area.

    Args:
        areas: mapping area name -> list of files.
        window: clone window size.
    Returns:
        Dict area -> {"files", "lines", "dup_lines", "share", "clones"}; share is a percentage
        rounded to 2 decimals.
    """
    result = {}
    for name, files in areas.items():
        clones, dup, total = find_clones(files, window)
        share = round(100.0 * dup / total, 2) if total else 0.0
        result[name] = {
            "files": len(files),
            "lines": total,
            "dup_lines": dup,
            "share": share,
            "clones": clones,
        }
    return result


def sh_missing(rel):
    """List shell functions without a doc comment.

    Args:
        rel: path relative to ROOT.
    Returns:
        List of (line_number, name) for functions with no comment line directly above and no
        comment on the same line.
    """
    lines = read_lines(rel)
    missing = []
    for number, raw in enumerate(lines, 1):
        match = SH_FUNC.match(raw)
        if not match:
            continue
        name = match.group(1) or match.group(2)
        if name in {"if", "while", "for", "until", "case"}:
            continue
        if re.search(r"\s#\s", raw):
            continue
        above = lines[number - 2].strip() if number > 1 else ""
        if above.startswith("#") and not above.startswith("#!"):
            continue
        missing.append((number, name))
    return missing


def py_missing(rel):
    """List Python functions and methods without a docstring.

    Args:
        rel: path relative to ROOT.
    Returns:
        List of (line_number, name); empty when the file does not parse.
    """
    try:
        tree = ast.parse("\n".join(read_lines(rel)))
    except SyntaxError:
        return []
    found = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and not ast.get_docstring(
            node
        ):
            found.append((node.lineno, node.name))
    return sorted(found)


def run_doc(areas):
    """Run the doc-comment report on every area.

    Args:
        areas: mapping area name -> list of files.
    Returns:
        Dict area -> {"shell", "python", "missing": [{"location", "name"}]} where shell and
        python are the missing counts.
    """
    result = {}
    for name, files in areas.items():
        entries = []
        counts = {"sh": 0, "py": 0}
        for rel in files:
            kind = kind_of(os.path.join(ROOT, rel))
            for number, func in sh_missing(rel) if kind == "sh" else py_missing(rel):
                counts[kind] += 1
                entries.append({"location": f"{rel}:{number}", "name": func})
        result[name] = {"shell": counts["sh"], "python": counts["py"], "missing": entries}
    return result


def breaches(mode, report, thresholds):
    """Compare a report with the configured thresholds.

    Args:
        mode: "dup" or "doc".
        report: result of run_dup or run_doc.
        thresholds: the "thresholds" object of the configuration.
    Returns:
        List of human-readable breach messages (empty when everything is within limits).
    """
    out = []
    if mode == "dup":
        for area, data in report.items():
            limit = thresholds.get("dup_share_max", {}).get(area)
            if limit is not None and data["share"] > limit:
                out.append(f"{area}: duplicated share {data['share']}% > {limit}%")
    else:
        for area, data in report.items():
            limit = thresholds.get("missing_docs_max", {}).get(area)
            total = data["shell"] + data["python"]
            if limit is not None and total > limit:
                out.append(f"{area}: {total} functions without doc > {limit}")
    return out


def format_text(mode, report):
    """Render a report as text.

    Args:
        mode: "dup" or "doc".
        report: result of run_dup or run_doc.
    Returns:
        The text, one line per clone or missing doc plus a summary line per area.
    """
    out = []
    for area, data in report.items():
        if mode == "dup":
            for clone in data["clones"]:
                joined = " <-> ".join(clone["locations"])
                out.append(f"clone {clone['lines']} lines: {joined}")
            out.append(
                f"[{area}] files={data['files']} lines={data['lines']} "
                f"dup_lines={data['dup_lines']} share={data['share']}%"
            )
        else:
            for item in data["missing"]:
                out.append(f"missing doc: {item['location']} {item['name']}")
            out.append(f"[{area}] shell={data['shell']} python={data['python']}")
    return "\n".join(out)


def main(argv):
    """Entry point.

    Args:
        argv: arguments after the program name: mode, flags, paths.
    Returns:
        Exit status: 0 (report mode), 1 when --enforce finds a breach, 2 on usage errors.
    """
    args = [a for a in argv if not a.startswith("--")]
    flags = {a for a in argv if a.startswith("--")}
    if not args or args[0] not in ("dup", "doc") or flags - {"--json", "--enforce"}:
        print("usage: codemetrics.py dup|doc [--json] [--enforce] [paths...]", file=sys.stderr)
        return 2
    mode, paths = args[0], args[1:]
    try:
        config = load_config()
    except ValueError as err:
        print(f"codemetrics: bad .codemetrics.json: {err}", file=sys.stderr)
        return 2
    if paths:
        areas = {"paths": collect(paths)}
    else:
        areas = {name: collect(dirs) for name, dirs in config.get("areas", {}).items()}
    window = int(config.get("window", DEFAULT_WINDOW))
    report = run_dup(areas, window) if mode == "dup" else run_doc(areas)
    if "--json" in flags:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(format_text(mode, report))
    problems = breaches(mode, report, config.get("thresholds", {}))
    for problem in problems:
        print("threshold: " + problem, file=sys.stderr)
    return 1 if problems and "--enforce" in flags else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
