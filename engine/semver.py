"""Semantic Versioning 2.0.0 (https://semver.org): parsing, precedence and bumps.

Versions are written without a 'v' prefix (the tag may have one: v1.2.3).
"""

import re

# the regular expression published by semver.org (numbered groups)
SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
)
# the same without build metadata, for branch names (POSIX ERE: the shell scripts use it too)
BRANCH_RX = (
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?$"
)


def valid(v):
    """Whether a text is a Semantic Version.

    Args:
        v: the text.

    Returns:
        bool: True when it matches.
    """
    return bool(SEMVER.match(v or ""))


def strip_v(tag):
    """'v1.2.3' -> '1.2.3' (other text unchanged)."""
    return tag[1:] if tag[:1] in ("v", "V") and valid(tag[1:]) else tag


def key(v):
    """Sort key following semver precedence (build metadata ignored). Invalid -> None."""
    m = SEMVER.match(v or "")
    if not m:
        return None
    core = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    pre = m.group(4)
    if pre is None:
        return core + ((1,),)  # a release outranks its prereleases
    ids = []
    for p in pre.split("."):
        # numeric identifiers rank below alphanumeric ones and compare as numbers
        ids.append((0, int(p), "") if p.isdigit() else (1, 0, p))
    return core + ((0, tuple(ids)),)


def compare(a, b):
    """Compare two versions by Semantic Versioning precedence.

    Args:
        a: the first version.
        b: the second version.

    Returns:
        int: -1, 0 or 1.
    """
    ka, kb = key(a), key(b)
    return (ka > kb) - (ka < kb)


def is_release(v):
    """Whether a version is a final release (no pre-release part).

    Args:
        v: the version text.

    Returns:
        bool: True for a valid version without pre-release.
    """
    m = SEMVER.match(v or "")
    return bool(m) and m.group(4) is None


def bump(v, part):
    """Next version: part = major | minor | patch. A prerelease becomes its release first."""
    m = SEMVER.match(v)
    if not m:
        raise ValueError(f"not a semantic version: {v!r}")
    ma, mi, pa = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if m.group(4) is not None and part == "patch":
        return f"{ma}.{mi}.{pa}"
    if part == "major":
        return f"{ma + 1}.0.0" if (m.group(4) is None or mi or pa) else f"{ma}.0.0"
    if part == "minor":
        return f"{ma}.{mi + 1}.0" if (m.group(4) is None or pa) else f"{ma}.{mi}.0"
    if part == "patch":
        return f"{ma}.{mi}.{pa + 1}"
    raise ValueError(f"unknown part {part!r} (major, minor or patch)")


def needed_bump(previous, current, breaking, features):
    """Warning text when 'current' does not follow semver given the changes since 'previous'."""
    kp, kc = key(previous), key(current)
    if kp is None or kc is None:
        return None
    if kc <= kp:
        return f"{current} is not newer than the previous release {previous}"
    pm, cm = kp[:3], kc[:3]
    if breaking and cm[0] == pm[0] and pm[0] > 0:
        return (
            f"breaking changes since {previous} need a MAJOR version ({bump(previous, 'major')}), "
            f"not {current}"
        )
    if (features or (breaking and pm[0] == 0)) and cm[:2] == pm[:2]:
        what = "new features" if features else "breaking changes"
        return f"{what} since {previous} need at least a MINOR version ({bump(previous, 'minor')}), not {current}"  # noqa: E501 - legacy code, kept as is in the 7.1.1 cleanup
    return None
