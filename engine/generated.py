"""Generated-file marks: files flagged in .gitattributes are exempt from size and style checks.

Set the git attribute `qs-generated` (or `linguist-generated`) on a path to mark it. Secret
scanning still covers generated files; only size, formatting and linting skip them.
"""

import functools
import os
import re
import subprocess

ATTRIBUTES = ("qs-generated", "linguist-generated")


def _state(value):
    """Map a check-attr value to True (set), False (unset) or None (unspecified/other)."""
    if value in ("set", "true"):
        return True
    if value in ("unset", "false"):
        return False
    return None


def _decide(states):
    """Combine per-attribute states: an explicit `qs-generated` wins over `linguist-generated`.

    Args:
        states: dict attribute name -> True, False or None.
    Returns:
        True when the file is generated, False otherwise.
    """
    for name in ATTRIBUTES:
        if states.get(name) is not None:
            return states[name]
    return False


def _git_says(root, rel):
    """Ask git for the marks of a file.

    Args:
        root: repository root used as working directory.
        rel: path of the file relative to root.
    Returns:
        True or False when git answered, None when it could not (no git, not a usable
        repository, as inside a container that sees a worktree's .git file).
    """
    cmd = ["git", "check-attr", *ATTRIBUTES, "--", rel]
    try:
        p = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=20, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    if p.returncode != 0:
        return None
    states = {}
    for line in p.stdout.splitlines():
        parts = line.split(": ")
        if len(parts) >= 3:
            states[parts[-2].strip()] = _state(parts[-1].strip())
    return _decide(states)


def _regex(pattern):
    """Translate a gitattributes glob into a regex source.

    Args:
        pattern: glob without a leading slash.
    Returns:
        Regex text where `*` and `?` do not cross `/` and `**` does, or None when the glob
        is malformed (unclosed bracket).
    """
    out, i = [], 0
    while i < len(pattern):
        c = pattern[i]
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif c == "[":
            j = pattern.find("]", i + 2)
            if j < 0:
                return None
            body = pattern[i + 1 : j]
            out.append("[" + ("^" + body[1:] if body[:1] == "!" else body) + "]")
            i = j + 1
        else:
            out.append("[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c))
            i += 1
    return "".join(out)


def _matches(pattern, rel):
    """Match a .gitattributes pattern against a relative path with gitattributes semantics.

    A pattern without `/` matches the basename at any depth. A pattern with `/` is anchored
    to the repository root; `*` does not cross `/`, `**` does. Unsupported forms (quoted
    patterns, macros `[attr]`, negated `!` patterns) never match, so they fail closed.

    Args:
        pattern: the first field of a .gitattributes line.
        rel: path relative to the root, with forward slashes.
    Returns:
        True when the pattern matches.
    """
    if pattern[0] in '"!' or pattern.startswith("[attr]"):
        return False
    rx = _regex(pattern.lstrip("/"))
    if rx is None:
        return False
    target = rel if "/" in pattern else os.path.basename(rel)
    try:
        return re.fullmatch(rx, target) is not None
    except re.error:
        return False


def _file_says(root, rel):
    """Read the root .gitattributes when git cannot answer.

    Only the root file is read: subdirectory .gitattributes files, macros and quoted
    patterns are unsupported and fail closed (the file is not exempt).

    Args:
        root: repository root.
        rel: path of the file relative to root, with forward slashes.
    Returns:
        True when the effective state is set. The last matching line wins per attribute and
        an explicit `-qs-generated` wins over `linguist-generated`.
    """
    states = {}
    try:
        with open(os.path.join(root, ".gitattributes"), encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return False
    for raw in lines:
        parts = raw.split()
        if len(parts) < 2 or parts[0].startswith("#") or not _matches(parts[0], rel):
            continue
        for attr in parts[1:]:
            name = attr.lstrip("-!").split("=", 1)[0]
            if name not in ATTRIBUTES:
                continue
            if attr.startswith("-"):
                states[name] = False
            elif attr.startswith("!"):
                states[name] = None
            else:
                states[name] = attr.partition("=")[2] not in ("false", "unset")
    return _decide(states)


@functools.lru_cache(maxsize=4096)
def _cached(root, rel):
    """Cached lookup for one (root, rel) pair; see is_generated."""
    said = _git_says(root, rel)
    return _file_says(root, rel) if said is None else said


def is_generated(root, rel):
    """Tell whether a file is marked as generated in .gitattributes.

    Args:
        root: repository root used as working directory.
        rel: path of the file relative to root.
    Returns:
        True when the attribute `qs-generated` or `linguist-generated` is set for the file.
        Git is asked first; if it cannot answer, the root .gitattributes is read directly.
        False when nothing marks the file. An explicit `-qs-generated` wins over
        `linguist-generated`. Results are cached per (root, rel) for the life of the
        process (one run); call `clear_cache()` after editing .gitattributes.
    """
    return _cached(root, rel.replace(os.sep, "/"))


def clear_cache():
    """Forget cached results; call after .gitattributes changes within one process."""
    _cached.cache_clear()
