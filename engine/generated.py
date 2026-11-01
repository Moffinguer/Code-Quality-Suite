"""Generated-file marks: files flagged in .gitattributes are exempt from size and style checks.

Set the git attribute `qs-generated` (or `linguist-generated`) on a path to mark it. Secret
scanning still covers generated files; only size, formatting and linting skip them.
"""

import subprocess


def is_generated(root, rel):
    """Tell whether a file is marked as generated in .gitattributes.

    Args:
        root: repository root used as working directory.
        rel: path of the file relative to root.
    Returns:
        True when the attribute `qs-generated` or `linguist-generated` is set for
        the file; False otherwise, also when the lookup fails.
    """
    cmd = ["git", "check-attr", "qs-generated", "linguist-generated", "--", rel]
    try:
        out = subprocess.run(
            cmd, cwd=root, capture_output=True, text=True, timeout=20, check=False
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return any(line.rsplit(": ", 1)[-1].strip() in ("set", "true") for line in out.splitlines())
