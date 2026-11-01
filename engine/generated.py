"""Generated-file marks: files flagged in .gitattributes are exempt from size and style checks.

Set the git attribute `qs-generated` (or `linguist-generated`) on a path to mark it. Secret
scanning still covers generated files; only size, formatting and linting skip them.
"""

import fnmatch
import os
import subprocess

ATTRIBUTES = ("qs-generated", "linguist-generated")


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
    return any(
        line.rsplit(": ", 1)[-1].strip() in ("set", "true") for line in p.stdout.splitlines()
    )


def _matches(pattern, rel):
    """Match a .gitattributes pattern (simple globs; no negation) against a relative path."""
    pattern = pattern.lstrip("/") if pattern.startswith("/") else pattern
    if "/" not in pattern:
        return fnmatch.fnmatch(os.path.basename(rel), pattern)
    return fnmatch.fnmatch(rel, pattern)


def _file_says(root, rel):
    """Read the root .gitattributes when git cannot answer.

    Args:
        root: repository root.
        rel: path of the file relative to root, with forward slashes.
    Returns:
        True when the last matching line sets a generated attribute (and does not unset it).
    """
    marked = False
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
            if name in ATTRIBUTES:
                marked = not attr.startswith(("-", "!")) and attr.partition("=")[2] != "false"
    return marked


def is_generated(root, rel):
    """Tell whether a file is marked as generated in .gitattributes.

    Args:
        root: repository root used as working directory.
        rel: path of the file relative to root.
    Returns:
        True when the attribute `qs-generated` or `linguist-generated` is set for the file.
        Git is asked first; if it cannot answer, the root .gitattributes is read directly.
        False when nothing marks the file.
    """
    rel = rel.replace(os.sep, "/")
    said = _git_says(root, rel)
    return _file_says(root, rel) if said is None else said
