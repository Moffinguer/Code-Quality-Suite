"""Repository policies kept in the rules file next to the tool rules.

  encoding  charset every text file must use (default UTF-8), BOM policy, overrides, mojibake
  commit    commit-message policy: allowed characters, Conventional Commits types, length
  branches  branch model: <version>/<ot>/<detail>... with '/', parent branches '<folder>/ORIGINAL'

The engine enforces `encoding`; `commit` and `branches` are enforced by the host hooks,
which read them from <state>/policy.env (written here; Git Bash has no JSON parser).
"""

import codecs
import contextlib
import copy
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

import semver

from registry import LEVELS

# level 2 of a branch name: the OT (work order), ASCII letters and digits ('188858', 'ABC123');
# no '-' or '_', so it never collides with the leaf names of the branch model
OT_RX = r"^[A-Za-z0-9]+$"

# ------------------------------------------------------------ special branches table

# Allowed values per property of a `branches.special.<TYPE>` entry; a tuple is an enumeration,
# a string names a kind checked by _special_value_error.
SPECIAL_PROPS = {
    "at": ("version", "node", "task"),  # where the branch may live
    "children": "bool",  # may become '<X>/ORIGINAL' with children
    "suffix": ("none", "n", "task"),  # 'ATTEMPT-<n>', 'REVIEW-<task>'
    "integrates": ("squash", "never", "choose", "apply"),  # how `git integra` treats it
    "order": ("any", "first", "last", "alone"),
    "rebase": "bool",  # False: regenerated, never rebased (FORMAT)
    "types": "types",  # Conventional Commits types; ["*"] = all, [] = no own commits
    "paths": "paths",  # allowed globs and @tokens; [] = any
    "level": "level",  # gate level of the branch, or None
    "push": ("normal", "never"),
    "push_checks": ("default", "full"),  # 'full': full build and tests on push
    "trailers": "trailers",  # trailers every own commit must carry
    "locks": "bool",  # while it exists no other branch of the version may be created
    "on_release": ("required", "optional", "delete", "set_aside"),
    "changelog": ("none", "changed", "task"),
}
# (type, property) pairs a project cannot change: validate refuses any other value
SPECIAL_FIXED = {
    ("FORMAT", "rebase"): False,
    ("ATTEMPT", "integrates"): "choose",
    ("CHECKPOINT", "push"): "never",
}
# standard files of `git repo-files` except VERSION (it changes only with the version commit)
REPO_FILES_GLOBS = (
    "README.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "CODE_OF_CONDUCT.md",
    "SECURITY.md",
    "SUPPORT.md",
    "CONTRIBUTORS.md",
    "MAINTAINERS.md",
    "ROADMAP.md",
    "FAQ.md",
    "INSTALL.md",
    "ARCHITECTURE.md",
    "API.md",
    "DEVELOPMENT.md",
    "AUTHORS",
    "LICENSE",
    "CODEOWNERS",
    "CITATION.cff",
)
# @tokens usable in `paths`; expand_paths turns them into globs
PATH_TOKENS = {
    "@repo-files": REPO_FILES_GLOBS,
    "@docs": ("*.md", "**/*.md", "docs/**", *REPO_FILES_GLOBS),
    "@tests": (
        "src/test/**",
        "**/test/**",
        "**/tests/**",
        "**/*_test.*",
        "**/test_*.py",
        "**/*.spec.*",
        "**/*.test.*",
    ),
}
_SP_BASE = {
    "at": "node",
    "children": True,
    "suffix": "none",
    "integrates": "squash",
    "order": "any",
    "rebase": True,
    "types": ["*"],
    "paths": [],
    "level": None,
    "push": "normal",
    "push_checks": "default",
    "trailers": [],
    "locks": False,
    "on_release": "set_aside",
    "changelog": "none",
}


def _sp(**over):
    """Build one default entry of the special table: the base properties plus overrides.

    Args:
        **over: the properties that differ from _SP_BASE.

    Returns:
        dict: a new entry (lists are copied), keys in SPECIAL_PROPS order.
    """
    return copy.deepcopy({**_SP_BASE, **over})


# 6.0.0 default table; the order of the entries is the order of QS_SP_NAMES and `git ayuda`.
# TESTING (branches.testing_leaf, 5.0.0-RC1) is not in the table: it is not configurable here.
SPECIAL_DEFAULTS = {
    "MIGRATION": _sp(
        at="version",
        order="first",
        types=["build", "fix", "refactor", "perf", "test", "docs", "chore", "ci", "style"],
        push_checks="full",
        locks=True,
        on_release="required",
        changelog="changed",
    ),
    "DOCS": _sp(
        at="version",
        children=False,
        order="last",
        types=["docs", "chore"],
        paths=["@docs"],
        on_release="required",
    ),
    "REFACTOR": _sp(
        order="last",
        types=["refactor", "style", "perf", "test", "docs", "chore"],
        level="strict",
    ),
    "FORMAT": _sp(children=False, order="alone", rebase=False, types=["style"]),
    "TESTS": _sp(types=["test", "chore"], paths=["@tests"]),
    "SPIKE": _sp(integrates="apply", on_release="delete"),
    "ATTEMPT": _sp(
        at="task", suffix="n", integrates="choose", on_release="delete", changelog="task"
    ),
    "REVIEW": _sp(at="task", suffix="task", integrates="apply", on_release="delete"),
    "QUARANTINE": _sp(
        at="task",
        suffix="task",
        integrates="apply",
        trailers=["Generated-by"],
        level="strict",
        on_release="delete",
        changelog="task",
    ),
    "CHECKPOINT": _sp(
        at="task",
        children=False,
        suffix="task",
        integrates="never",
        level="format",
        push="never",
        on_release="delete",
    ),
}

DEFAULTS = {
    "encoding": {
        "enabled": True,
        "charset": "utf-8",
        "bom": "forbid",  # forbid | allow | require
        "by_language": {"powershell": {"bom": "allow"}},
        "by_glob": {},  # {"legacy/**/*.properties": "iso-8859-1"}
        "mojibake": "block",  # block | warn | off: text damaged by a wrong-encoding save
        "mojibake_ignore": [],  # globs never checked for mojibake (encoding test fixtures)
    },
    "commit": {
        "charset": "ascii",  # ascii | utf-8 | any
        "types": [
            "feat",
            "fix",
            "docs",
            "style",
            "refactor",
            "perf",
            "test",
            "build",
            "ci",
            "chore",
            "revert",
        ],
        "subject_max": 50,
        "conventional": True,
        "files": "block",  # block | warn | off: the 'Files:' block in every commit message
    },
    "branches": {
        "enforce": "block",  # block | warn | off
        "parent_leaf": "ORIGINAL",
        "mainline": "develop",
        "protected": ["main", "master", "develop"],
        # level 1: the version, Semantic Versioning without build metadata (https://semver.org);
        # level 2: the OT (OT_RX)
        "levels": [
            r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
            r"(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?$",
            OT_RX,
        ],
        "segment": r"^[A-Za-z0-9][A-Za-z0-9_-]*$",
        "allow": [],
        "model": 6,  # marker of the one-time migration to the 6.x branch model (migrate)
        "flow": "squash",  # squash (5.x) | merge (4.x, deprecated)
        "ot_ref": "refs/ot/{version}/{ot}",  # hidden ref at the OT release; empty = none
        "testing_leaf": "TESTING",  # reserved leaf of the TESTING sandbox '<level>/TESTING'
        "leaf_merge": "merge",  # merge (--no-ff) | squash; only used with flow = merge
        "require_children_merged": True,
        "tag": "{version}",
        "tag_level": 1,  # tag when a level-N ORIGINAL is integrated (0 = never); flow = merge only
        "release_leaf": "RELEASE",  # git release: '<version>/ORIGINAL' becomes '<version>/RELEASE'
        "archive_prefix": "unmerged",  # git release: branches not integrated -> 'unmerged/<name>'
        "version_file": "VERSION",  # committed on '<version>/ORIGINAL' when the tree is created
        "changelog_file": "CHANGELOG.md",  # git changelog --write: Common Changelog release notes
        "readme_file": "README.md",  # git release: version badge
        "pom_version": "update",  # update | snapshot | check | off: pom.xml follows the version
        "tag_url": "",  # changelog links: '' = from origin, '-' = none, or '...{tag}'
        "commit_url": "",  # changelog references: '' = from origin, '-' = none, '...{commit}'
        "build_cmd": "",  # full build of a push_checks: full type ('' = QUALITY_HEAVY_CMD)
        "publish_on_create": True,  # every branch a command creates is pushed to origin
        "special": SPECIAL_DEFAULTS,  # table of special branches (see SPECIAL_PROPS)
    },
}
SECTIONS = tuple(DEFAULTS)
BOM_UTF8 = codecs.BOM_UTF8
MODEL = DEFAULTS["branches"]["model"]
OLD_OT_RX = r"^[0-9]+$"  # level 2 default before 4.2.1 (numeric OTs only)
FLOW_NOTICE = (
    "existing rules file: `branches.flow` set to `merge` to keep the 4.x behaviour; "
    "set `branches.flow` to `squash` in .quality-rules.json to adopt the 5.x flow"
)


DOCS_NOTICE = (
    "6.0 kept the 5.x changelog writer (OT RELEASE). To make DOCS write it, finish the open "
    "version trees and set `branches.special.DOCS.on_release` to `required`, see "
    "docs/UPDATING.md"
)


def migrate(data):
    """One-time migration of a rules file to the current branch model. Run before populate.

    Step 5 (`branches.model` missing or below 5): `branches.levels[1]` equal to the old default
    `^[0-9]+$` becomes OT_RX (any other value is kept), `branches.flow` is added as `merge`
    (4.x behaviour kept; new files get `squash` from populate) and the model is set to 5.
    Step 6 (model below 6): `branches.special.DOCS.on_release` is added as `optional`, so the
    5.x changelog writer (OT RELEASE) keeps working until the project switches to `required`
    (never written over an existing value or over `"DOCS": false`); the model is set to 6.
    A 4.x file goes through both steps. A second run changes nothing. Never weakens a rule.

    Args:
        data: the parsed rules file (dict), changed in place.

    Returns:
        list[str]: one message per change (the log lines); the notices are FLOW_NOTICE and
        DOCS_NOTICE inside their messages.
    """
    br = data.get("branches") if isinstance(data, dict) else None
    if not isinstance(br, dict):
        return []
    model = br.get("model")
    if not isinstance(model, int) or isinstance(model, bool):
        model = 0
    if model >= MODEL:
        return []
    msgs = []
    if model < 5:
        levels = br.get("levels")
        if isinstance(levels, list) and len(levels) > 1 and levels[1] == OLD_OT_RX:
            levels[1] = OT_RX
            msgs.append(f"migrated branches.levels[1]: {OLD_OT_RX} -> {OT_RX}")
        if "flow" not in br:
            br["flow"] = "merge"
            msgs.append(f"migrated branches.flow: merge ({FLOW_NOTICE})")
        msgs.append("migrated branches.model: 5")
    msgs += _migrate_special(br)
    msgs += _migrate_ot_ref(br)
    br["model"] = MODEL
    msgs.append(f"migrated branches.model: {MODEL}")
    return msgs


def _migrate_ot_ref(br):
    """Rename `branches.ot_tag` to `branches.ot_ref` and map `ot/...` to `refs/ot/...`.

    Tags are version numbers only; the OT release writes a hidden ref instead. An existing
    `ot_ref` is never overwritten (the old key is then just dropped).

    Args:
        br: the branches section (dict), changed in place.

    Returns:
        list[str]: one message when the key was renamed, else an empty list.
    """
    if "ot_tag" not in br:
        return []
    old = br.pop("ot_tag")
    if "ot_ref" in br:
        return []
    if isinstance(old, str) and old.startswith("ot/"):
        old = "refs/" + old
    br["ot_ref"] = old
    return [f"migrated branches.ot_tag -> branches.ot_ref: {old!r}"]


def _migrate_special(br):
    """Step 6 of migrate: keep the 5.x changelog writer by setting DOCS.on_release to optional.

    Args:
        br: the `branches` section of the rules file (dict), changed in place.

    Returns:
        list[str]: the one message of the change, empty when nothing was set.
    """
    special = br.setdefault("special", {})
    if not isinstance(special, dict):
        return []
    docs = special.get("DOCS")
    if docs is None:
        special["DOCS"] = docs = {}
    if not isinstance(docs, dict) or "on_release" in docs:
        return []
    docs["on_release"] = "optional"
    return [f"migrated branches.special.DOCS.on_release: optional ({DOCS_NOTICE})"]


def populate(data):
    """Add missing policy sections/keys with defaults. Never overwrites a value.

    Args:
        data: the parsed rules file (dict), changed in place.

    Returns:
        list[str]: the paths added ('section' or 'section.key').
    """
    added = []
    for sec, defaults in DEFAULTS.items():
        cur = data.get(sec)
        if not isinstance(cur, dict):
            if cur is None:
                data[sec] = copy.deepcopy(defaults)
                added.append(sec)
            continue
        for k, v in defaults.items():
            if k not in cur:
                cur[k] = copy.deepcopy(v)
                added.append(f"{sec}.{k}")
    return added


def get(data, sec):
    """Effective policy section: the defaults overridden by the keys set in data.

    Args:
        data: the parsed rules file (dict), or None.
        sec: name of the section, a key of DEFAULTS.

    Returns:
        dict: a new dict; the defaults are never modified.

    Raises:
        KeyError: sec is not a known section.
    """
    out = copy.deepcopy(DEFAULTS[sec])
    cur = (data or {}).get(sec)
    if isinstance(cur, dict):
        out.update(cur)
        if sec == "branches":
            out["special"] = _merge_special(cur.get("special"))
    return out


def _merge_special(over):
    """Merge a project's `branches.special` over the default table, one property at a time.

    Args:
        over: the project's value (dict), or anything else when absent or malformed.

    Returns:
        dict: a new table. A type set to a dict keeps the defaults of the properties it does not
        mention; a type set to anything else (False) or unknown is kept as written so that
        validate and special_table can see it. A non-dict `over` gives the defaults.
    """
    out = copy.deepcopy(SPECIAL_DEFAULTS)
    if not isinstance(over, dict):
        return out
    for name, val in over.items():
        if isinstance(val, dict) and isinstance(out.get(name), dict):
            out[name].update(copy.deepcopy(val))
        elif val is not True or name not in out:
            # a type set to true keeps its defaults
            out[name] = copy.deepcopy(val)
    return out


def special_table(data):
    """The effective table of special branches: enabled known types only.

    Args:
        data: the parsed rules file (dict), or None.

    Returns:
        dict[str, dict]: {TYPE: properties} in table order. A type set to `false` is absent (not
        reserved); `true` or `{}` means the defaults; properties not overridden keep their
        default; entries that are not objects are dropped.
    """
    table = get(data, "branches")["special"]
    return {n: p for n, p in table.items() if n in SPECIAL_DEFAULTS and isinstance(p, dict)}


def special_names(data):
    """Names of the enabled special types, in table order.

    Args:
        data: the parsed rules file (dict), or None.

    Returns:
        list[str]: e.g. ['MIGRATION', 'DOCS', ...]; the `QS_SP_NAMES` of the shell export.
    """
    return list(special_table(data))


def expand_paths(paths):
    """Expand the @tokens of a `paths` list into globs.

    Args:
        paths: list of globs and @tokens (`@repo-files`, `@docs`, `@tests`).

    Returns:
        list[str]: the globs, in order, without duplicates; an unknown @token is kept as is.
    """
    out = []
    for p in paths:
        for g in PATH_TOKENS.get(p, (p,)):
            if g not in out:
                out.append(g)
    return out


def _charset_ok(name):
    """Whether Python knows a charset name.

    Args:
        name: the charset name as written in the rules file.

    Returns:
        bool: True when codecs.lookup accepts the name (or it is 'ascii' in any case).
    """
    try:
        codecs.lookup(name)
        return True
    except LookupError:
        return name.lower() == "ascii"


def validate(data):
    """Check the policy sections of a rules file.

    Args:
        data: the parsed rules file (dict).

    Returns:
        list[str]: one message per problem, empty when the policy is valid.
    """
    errors = []
    for sec in SECTIONS:
        cur = data.get(sec)
        if cur is not None and not isinstance(cur, dict):
            errors.append(f"{sec}: must be an object")
    errors += _validate_encoding(get(data, "encoding"))
    errors += _validate_commit(get(data, "commit"))
    errors += _validate_branches(get(data, "branches"))
    raw = data.get("branches")
    errors += _validate_special(raw.get("special") if isinstance(raw, dict) else None)
    errors += _validate_special_names(get(data, "branches"))
    return errors


def _special_value_error(kind, val):
    """Check one value of a special-table property against its kind.

    Args:
        kind: a tuple of allowed values or one of 'bool', 'types', 'paths', 'level', 'trailers'.
        val: the value found in the rules file.

    Returns:
        str: what is wrong ('' when the value is valid).
    """
    if isinstance(kind, tuple):
        ok = isinstance(val, str) and val in kind
        return "" if ok else "must be one of " + ", ".join(kind)
    if kind == "bool":
        return "" if isinstance(val, bool) else "must be true or false"
    if kind == "level":
        return "" if val is None or val in LEVELS else "must be null or " + ", ".join(LEVELS)
    if not isinstance(val, list) or not all(isinstance(x, str) for x in val):
        return "must be a list of strings"
    return _special_list_error(kind, val)


def _special_list_error(kind, val):
    """Check a list-valued property of the special table (its items are already strings).

    Args:
        kind: 'types', 'paths' or 'trailers'.
        val: the list.

    Returns:
        str: what is wrong ('' when the list is valid).
    """
    if kind == "types":
        word = re.compile(r"[a-z][a-z0-9-]*")
        if val == ["*"] or all(word.fullmatch(x) for x in val):
            return ""
        return "must be ['*'] (all) or a list of lowercase Conventional Commits types"
    if kind == "trailers":
        ok = all(re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*", x) for x in val)
        return "" if ok else "must be a list of trailer names (letters, digits, '-')"
    for p in val:
        if p.startswith("@"):
            if p not in PATH_TOKENS:
                return f"unknown token {p!r} (known: {', '.join(PATH_TOKENS)})"
        elif not p or p.startswith("/") or ".." in p.split("/") or "\\" in p or "|" in p:
            return f"{p!r} is not a glob inside the repository"
    return ""


def _validate_special(special):
    """Check `branches.special` as written in the rules file.

    Args:
        special: the raw value (None when absent).

    Returns:
        list[str]: one message per problem: not an object, unknown type (HOTFIX), type neither an
        object nor a boolean, unknown property, bad value, change of a non-configurable property
        (SPECIAL_FIXED).
    """
    if special is None:
        return []
    if not isinstance(special, dict):
        return ["branches.special: must be an object"]
    errors = []
    for name, val in special.items():
        base = f"branches.special.{name}"
        if name not in SPECIAL_DEFAULTS:
            errors.append(f"{base}: unknown type (known: {', '.join(SPECIAL_DEFAULTS)})")
        elif isinstance(val, bool):
            continue
        elif not isinstance(val, dict):
            errors.append(f"{base}: must be an object, true or false")
        else:
            errors += _validate_special_entry(name, val)
    return errors


def _validate_special_entry(name, entry):
    """Check the properties of one type of the special table.

    Args:
        name: the type, a key of SPECIAL_DEFAULTS.
        entry: the properties set by the project (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    for prop, val in entry.items():
        path = f"branches.special.{name}.{prop}"
        if prop not in SPECIAL_PROPS:
            errors.append(f"{path}: unknown property (known: {', '.join(SPECIAL_PROPS)})")
            continue
        err = _special_value_error(SPECIAL_PROPS[prop], val)
        if err:
            errors.append(f"{path}: {err}")
        elif (name, prop) in SPECIAL_FIXED and val != SPECIAL_FIXED[(name, prop)]:
            errors.append(f"{path}: not configurable (always {SPECIAL_FIXED[(name, prop)]!r})")
    return errors


def _validate_special_names(br):
    """Check that no enabled special type is named like a reserved leaf of the branch model.

    Args:
        br: the 'branches' section merged with its defaults (dict).

    Returns:
        list[str]: one message per clash with parent_leaf, release_leaf or testing_leaf,
        ignoring case (refs are case-insensitive on Windows).
    """
    leaves = {
        key: str(br.get(key, "")).lower() for key in ("parent_leaf", "release_leaf", "testing_leaf")
    }
    errors = []
    for name, props in br["special"].items():
        if name not in SPECIAL_DEFAULTS or not isinstance(props, dict):
            continue
        for key, leaf in leaves.items():
            if name.lower() == leaf:
                errors.append(f"branches.{key}: must differ from the special type {name}")
    return errors


def _validate_encoding(enc):
    """Check the 'encoding' section.

    Args:
        enc: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    if not _charset_ok(str(enc.get("charset"))):
        errors.append(f"encoding.charset: unknown charset '{enc.get('charset')}'")
    if enc.get("bom") not in ("forbid", "allow", "require"):
        errors.append("encoding.bom: must be forbid, allow or require")
    for key in ("by_language", "by_glob"):
        val = enc.get(key)
        if not isinstance(val, dict):
            errors.append(f"encoding.{key}: must be an object")
            continue
        for k, v in val.items():
            cs = (
                v
                if isinstance(v, str)
                else (v or {}).get("charset")
                if isinstance(v, dict)
                else None
            )
            if not isinstance(v, (str, dict)):
                errors.append(f"encoding.{key}.{k}: must be a charset name or {{charset, bom}}")
            elif cs and not _charset_ok(cs):
                errors.append(f"encoding.{key}.{k}: unknown charset '{cs}'")
    if enc.get("mojibake") not in ("block", "warn", "off"):
        errors.append("encoding.mojibake: must be block, warn or off")
    if not (
        isinstance(enc.get("mojibake_ignore"), list)
        and all(isinstance(x, str) for x in enc["mojibake_ignore"])
    ):
        errors.append("encoding.mojibake_ignore: must be a list of globs")
    return errors


def _validate_commit(com):
    """Check the 'commit' section.

    Args:
        com: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    if com.get("charset") not in ("ascii", "utf-8", "any"):
        errors.append("commit.charset: must be ascii, utf-8 or any")
    if com.get("files") not in ("block", "warn", "off"):
        errors.append("commit.files: must be block, warn or off")
    if not (
        isinstance(com.get("types"), list)
        and all(isinstance(t, str) and re.fullmatch(r"[a-z][a-z0-9-]*", t) for t in com["types"])
    ):
        errors.append("commit.types: must be a list of lowercase words")
    if not isinstance(com.get("subject_max"), int) or com["subject_max"] < 10:
        errors.append("commit.subject_max: must be an integer >= 10")
    return errors


def _validate_branches(br):
    """Check the 'branches' section.

    Args:
        br: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    if br.get("enforce") not in ("block", "warn", "off"):
        errors.append("branches.enforce: must be block, warn or off")
    if br.get("leaf_merge") not in ("merge", "squash"):
        errors.append("branches.leaf_merge: must be merge or squash")
    if br.get("flow") not in ("squash", "merge"):
        errors.append("branches.flow: must be squash or merge")
    ot_ref = br.get("ot_ref")
    bad = ot_ref != "" and ("{ot}" not in ot_ref or not ot_ref.startswith("refs/ot/"))
    if not isinstance(ot_ref, str) or bad:
        errors.append("branches.ot_ref: must be '' or start with refs/ot/ and contain {ot}")
    if not isinstance(br.get("model"), int) or isinstance(br.get("model"), bool):
        errors.append("branches.model: must be an integer")
    for key in ("parent_leaf", "release_leaf", "archive_prefix", "testing_leaf"):
        if not re.fullmatch(r"[A-Za-z0-9_-]+", str(br.get(key, ""))):
            errors.append(f"branches.{key}: letters, digits, '-' or '_' only")
    if len({br.get("parent_leaf"), br.get("release_leaf")}) < 2:
        errors.append("branches.release_leaf: must differ from parent_leaf")
    if br.get("testing_leaf") in (br.get("parent_leaf"), br.get("release_leaf")):
        errors.append("branches.testing_leaf: must differ from parent_leaf and release_leaf")
    if br.get("pom_version") not in ("update", "snapshot", "check", "off"):
        errors.append("branches.pom_version: must be update, snapshot, check or off")
    errors += _validate_branch_paths(br)
    errors += _validate_branch_patterns(br)
    if not isinstance(br.get("tag_level"), int) or br["tag_level"] < 0:
        errors.append("branches.tag_level: must be an integer >= 0")
    return errors


def _validate_branch_paths(br):
    """Check the URL templates and file paths of the 'branches' section.

    Args:
        br: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    for key, ph in (("tag_url", "{tag}"), ("commit_url", "{commit}")):
        v = br.get(key)
        if not isinstance(v, str) or (v not in ("", "-") and ph not in v):
            errors.append(f"branches.{key}: '' (from origin), '-' (none) or a URL with {ph}")
    if not isinstance(br.get("build_cmd"), str):
        errors.append("branches.build_cmd: a shell command ('' = the heavy stage command)")
    for key in ("version_file", "changelog_file", "readme_file"):
        v = br.get(key)
        if not isinstance(v, str) or v.startswith(("/", "-")) or ".." in v.split("/") or "\\" in v:
            errors.append(f"branches.{key}: a path inside the repository ('' = off)")
    if not isinstance(br.get("publish_on_create"), bool):
        errors.append("branches.publish_on_create: must be true or false")
    return errors


def _validate_branch_patterns(br):
    """Check the name lists and regular expressions of the 'branches' section.

    Args:
        br: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    for key in ("levels", "allow", "protected"):
        if not (isinstance(br.get(key), list) and all(isinstance(x, str) for x in br[key])):
            errors.append(f"branches.{key}: must be a list of strings")
    patterns = list(br.get("levels") or []) + list(br.get("allow") or [])
    for rx in [*patterns, br.get("segment", "")]:
        try:
            re.compile(rx)
        except (re.error, TypeError):
            errors.append(f"branches: invalid regular expression {rx!r}")
    return errors


# ---------------------------------------------------------------- host export


def _sh(v):
    """Quote a value as one POSIX shell word (single quotes, embedded quotes escaped).

    Args:
        v: the value; converted with str().

    Returns:
        str: the quoted word, safe to assign in KEY='value' lines.
    """
    return "'" + str(v).replace("'", "'\\''") + "'"


def shell_env(data):
    """KEY='value' lines for the host hooks (commit-msg, pre-push, git aliases)."""
    com, br = get(data, "commit"), get(data, "branches")
    lines = {
        "QS_COMMIT_CHARSET": com["charset"],
        "QS_COMMIT_TYPES": "|".join(com["types"]),
        "QS_COMMIT_SUBJECT_MAX": com["subject_max"],
        "QS_COMMIT_CONVENTIONAL": "1" if com.get("conventional", True) else "0",
        "QS_COMMIT_FILES": com["files"],
        "QS_BR_ENFORCE": br["enforce"],
        "QS_BR_LEAF": br["parent_leaf"],
        "QS_BR_MAINLINE": br["mainline"],
        "QS_BR_PROTECTED": " ".join(br["protected"]),
        "QS_BR_SEGMENT": br["segment"],
        "QS_BR_LEAF_MERGE": br["leaf_merge"],
        "QS_BR_FLOW": br["flow"],
        "QS_BR_OT_REF": br["ot_ref"],
        "QS_BR_PUBLISH": "1" if br.get("publish_on_create", True) is not False else "0",
        "QS_BR_TESTING": br["testing_leaf"],
        "QS_BR_REQUIRE_CHILDREN": "1" if br.get("require_children_merged", True) else "0",
        "QS_BR_TAG": br["tag"],
        "QS_BR_TAG_LEVEL": br["tag_level"],
        "QS_BR_RELEASE_LEAF": br["release_leaf"],
        "QS_BR_ARCHIVE": br["archive_prefix"],
        "QS_BR_VERSION_FILE": br["version_file"],
        "QS_BR_CHANGELOG": br["changelog_file"],
        "QS_BR_README": br["readme_file"],
        "QS_BR_POM": br["pom_version"],
        "QS_BR_TAG_URL": br["tag_url"],
        "QS_BR_COMMIT_URL": br["commit_url"],
        "QS_BR_BUILD_CMD": br["build_cmd"],
        "QS_BR_LEVELS": len(br["levels"]),
        "QS_BR_ALLOW": len(br["allow"]),
    }
    for i, rx in enumerate(br["levels"], 1):
        lines[f"QS_BR_LEVEL_{i}"] = rx
    for i, rx in enumerate(br["allow"], 1):
        lines[f"QS_BR_ALLOW_{i}"] = rx
    lines.update(special_env(data))
    return "".join(f"{k}={_sh(v)}\n" for k, v in lines.items())


def _sp_value(val):
    """Encode one property of the special table as a shell string.

    Args:
        val: the property value: bool, None, str or list of str.

    Returns:
        str: '1'/'0' for a bool, '' for None, the items joined with '|' for a list (a list
        never has '|' in an item that validate accepts), otherwise str(val).
    """
    if isinstance(val, bool):
        return "1" if val else "0"
    if val is None:
        return ""
    if isinstance(val, list):
        return "|".join(val)
    return str(val)


def special_env(data):
    """The special table as shell variables: the query helper of the hooks and scripts.

    `QS_SP_NAMES` lists the enabled types separated by spaces; every enabled type has one
    `QS_SP_<TYPE>_<PROP>` per property (PROP upper case: AT, CHILDREN, SUFFIX, INTEGRATES, ORDER,
    REBASE, TYPES, PATHS, GLOBS, LEVEL, PUSH, PUSH_CHECKS, TRAILERS, LOCKS, ON_RELEASE, CHANGELOG).
    Booleans are 1/0, a null level is '', lists are joined with '|' (`types` ['*'] = all
    types, `paths` keep their @tokens; `GLOBS` is `paths` with the @tokens expanded, for the
    hooks).

    Args:
        data: the parsed rules file (dict), or None.

    Returns:
        dict[str, str]: variable name -> value, in table order. Disabled types are absent.
    """
    table = special_table(data)
    env = {"QS_SP_NAMES": " ".join(table)}
    for name, props in table.items():
        for prop in SPECIAL_PROPS:
            env[f"QS_SP_{name}_{prop.upper()}"] = _sp_value(props[prop])
        # why: the hooks match these globs; expanding the @tokens here keeps one copy of them
        env[f"QS_SP_{name}_GLOBS"] = _sp_value(expand_paths(props["paths"]))
    return env


# ---------------------------------------------------------------- encoding


def _norm(cs):
    """Canonical lower-case name of a charset (aliases such as cp1252 or latin1 mapped).

    Args:
        cs: the charset name from the rules file; empty means utf-8.

    Returns:
        str: the canonical name, e.g. 'windows-1252' for 'cp1252'.
    """
    cs = (cs or "utf-8").lower().replace("_", "-")
    return {
        "utf8": "utf-8",
        "latin1": "iso-8859-1",
        "latin-1": "iso-8859-1",
        "cp1252": "windows-1252",
        "us-ascii": "ascii",
    }.get(cs, cs)


def expected(enc, rel, lang_id):
    """(charset, bom) expected for a file: by_glob (first match) > by_language > global."""
    cs, bom = enc.get("charset", "utf-8"), enc.get("bom", "forbid")
    lv = (enc.get("by_language") or {}).get(lang_id or "")
    if isinstance(lv, str):
        cs = lv
    elif isinstance(lv, dict):
        cs, bom = lv.get("charset", cs), lv.get("bom", bom)
    for pat, gv in (enc.get("by_glob") or {}).items():
        if glob_match(rel, pat):
            if isinstance(gv, str):
                cs = gv
            elif isinstance(gv, dict):
                cs, bom = gv.get("charset", cs), gv.get("bom", bom)
            break
    return _norm(cs), bom


def glob_match(rel, pat):
    """fnmatch for repository paths: 'x/**/y' also matches 'x/y'; a bare name matches any folder."""
    return (
        fnmatch.fnmatch(rel, pat)
        or ("/" not in pat and fnmatch.fnmatch(os.path.basename(rel), pat))
        or (pat.startswith("**/") and fnmatch.fnmatch(rel, pat[3:]))
        or ("/**/" in pat and fnmatch.fnmatch(rel, pat.replace("/**/", "/")))
    )


def _line_col(raw, pos):
    """Line and column of a byte offset in a file.

    Args:
        raw: the file bytes.
        pos: byte offset into raw.

    Returns:
        tuple: (line, column), both 1-based; the column counts bytes.
    """
    line = raw.count(b"\n", 0, pos) + 1
    col = pos - (raw.rfind(b"\n", 0, pos) + 1) + 1
    return line, col


def _guess(raw):
    """Best-effort name of the encoding a non-UTF-8 file probably uses."""
    if raw.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)) or raw[1:200:2].count(0) > 20:
        return "UTF-16"
    if any(0x80 <= b <= 0x9F for b in raw):
        return "Windows-1252"
    return "ISO-8859-1 / Windows-1252"


def check(raw, cs, bom):
    """Problems (list of str) for file bytes against the expected charset and BOM policy.

    why: a file whose encoding changed (UTF-8 saved as ANSI, or converted the other way)
    silently corrupts accents for every other developer and tool, so it must not land.

    Args:
        raw: the file bytes.
        cs: the expected charset, normalized (see expected()).
        bom: the BOM policy: forbid, allow or require.

    Returns:
        list[str]: at most one problem; empty when the bytes match.
    """
    if cs in ("utf-16", "utf-16-le", "utf-16-be", "utf-32"):
        return _check_wide(raw, cs)
    if raw.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE, codecs.BOM_UTF32_LE)):
        return [f"file is UTF-16/32 but must be {cs.upper()}; re-save it as {cs.upper()}"]
    if cs == "utf-8":
        return _check_utf8(raw, bom)
    if raw.startswith(BOM_UTF8):
        return [f"starts with a UTF-8 BOM but must be {cs.upper()}"]
    if cs == "ascii":
        return _check_ascii(raw)
    return _check_legacy(raw, cs)


def _check_wide(raw, cs):
    """check() for UTF-16 and UTF-32 charsets.

    Args:
        raw: the file bytes.
        cs: the expected charset.

    Returns:
        list[str]: the decoding problem, or empty.
    """
    try:
        raw.decode(cs)
        return []
    except UnicodeDecodeError as e:
        return [f"not valid {cs.upper()} at byte {e.start}"]


def _check_utf8(raw, bom):
    """check() for UTF-8: valid bytes and the BOM policy.

    Args:
        raw: the file bytes.
        bom: the BOM policy: forbid, allow or require.

    Returns:
        list[str]: the problem found, or empty.
    """
    has_bom = raw.startswith(BOM_UTF8)
    body = raw[3:] if has_bom else raw
    try:
        body.decode("utf-8")
    except UnicodeDecodeError as e:
        return _utf8_damage(body, e)
    if has_bom and bom == "forbid":
        return [
            "starts with a UTF-8 BOM (EF BB BF), which is forbidden here; "
            "save it as 'UTF-8' without BOM"
        ]
    if not has_bom and bom == "require" and any(b >= 0x80 for b in body):
        return ["must start with a UTF-8 BOM (encoding.bom = require)"]
    return []


def _utf8_damage(body, e):
    """Explain why bytes that must be UTF-8 do not decode.

    Args:
        body: the file bytes without BOM.
        e: the UnicodeDecodeError of the UTF-8 decode.

    Returns:
        list[str]: one message with position, likely cause, sample words and the repair.
    """
    if _guess(body) == "UTF-16":
        return ["file looks like UTF-16 without a BOM; save it as 'UTF-8'"]
    line, col = _line_col(body, e.start)
    _, spots, utf8_chars = decode_mixed(body)
    what = (
        f"mixed encodings: {len(spots)} character(s) in Windows-1252 next to "
        f"{utf8_chars} in UTF-8 "
        f"(the editor opened it with the wrong encoding and saved new text in Windows-1252)"
        if utf8_chars
        else f"saved as Windows-1252/ISO-8859-1 (ANSI) instead of UTF-8: {len(spots)} character(s)"
    )
    where = "; ".join(f'line {ln}: "{_show(w)}"' for ln, w in _spot_words(body, spots)[:3])
    more = f" (+{len(spots) - 3} more)" if len(spots) > 3 else ""
    return [
        f"not valid UTF-8 at line {line}, column {col} (byte 0x{body[e.start]:02X}): "
        f"{what}; {where}{more}. Repair: git encoding --fix FILE"
    ]


def _check_ascii(raw):
    """check() for ASCII: the first byte >= 0x80.

    Args:
        raw: the file bytes.

    Returns:
        list[str]: the first non-ASCII byte with its position, or empty.
    """
    for i, b in enumerate(raw):
        if b >= 0x80:
            line, col = _line_col(raw, i)
            return [f"non-ASCII byte 0x{b:02X} at line {line}, column {col} (encoding is ascii)"]
    return []


def _check_legacy(raw, cs):
    """check() for single-byte charsets (ISO-8859-1, Windows-1252, ...).

    Args:
        raw: the file bytes (no BOM).
        cs: the expected charset.

    Returns:
        list[str]: an undecodable byte, or a file that looks converted to UTF-8, or empty.
    """
    try:
        raw.decode(cs)
    except (UnicodeDecodeError, LookupError) as e:
        pos = getattr(e, "start", 0)
        line, col = _line_col(raw, pos)
        return [f"byte 0x{raw[pos]:02X} at line {line}, column {col} is not valid {cs.upper()}"]
    if any(b >= 0x80 for b in raw):
        try:
            text = raw.decode("utf-8")
            if any(ord(ch) >= 0x80 for ch in text):
                return [
                    f"looks like UTF-8 but must be {cs.upper()} (the file was converted?); "
                    f"convert it back: iconv -f UTF-8 -t {cs.upper()} FILE > tmp && mv tmp FILE"
                ]
        except UnicodeDecodeError:
            pass
    return []


def needs_protection(raw, cs):
    """True when tools that assume UTF-8 could corrupt this file.

    Args:
        raw: the file bytes.
        cs: the expected charset.

    Returns:
        bool: the charset is neither UTF-8 nor ASCII and the file has non-ASCII bytes.
    """
    return cs not in ("utf-8", "ascii") and any(b >= 0x80 for b in raw)


# ---------------------------------------------------------------- mojibake
#
# Mojibake is text whose bytes were read with one encoding and written back with another. In a
# UTF-8 file it shows up in three ways, all produced by an editor that guessed the wrong encoding
# (VS Code with files.autoGuessEncoding, or files.encoding set to windows1252):
#   double encoding   UTF-8 bytes read as Windows-1252 and saved as UTF-8: "o" acute (C3 B3)
#                     becomes the two characters U+00C3 U+00B3
#   replacement char  a Windows-1252 file read as UTF-8 and saved: each accent becomes U+FFFD
#   question marks    saved in a charset without those letters: each accent becomes "?"
# The first is found in the text alone; the last two need the previous version of the file.


def _cp1252_bytes():
    """Map the characters Windows-1252 shows for bytes 0x80-0xFF back to the bytes.

    ISO-8859-1 fills the holes of Windows-1252.

    Returns:
        dict[str, int]: {character: byte}.
    """
    out = {}
    for b in range(0x80, 0x100):
        out[chr(b)] = b
        with contextlib.suppress(UnicodeDecodeError):
            out[bytes([b]).decode("cp1252")] = b
    return out


BYTE_OF = _cp1252_bytes()


def _cls(lo, hi):
    """Body of a regex character class with the Windows-1252 characters of a byte range.

    Args:
        lo: first byte value, inclusive.
        hi: last byte value, inclusive.

    Returns:
        str: the regex-escaped characters whose cp1252 byte is in [lo, hi], no brackets.
    """
    return "".join(re.escape(ch) for ch, b in sorted(BYTE_OF.items()) if lo <= b <= hi)


_CONT = "[" + _cls(0x80, 0xBF) + "]"
# one UTF-8 multi-byte sequence as it looks after a Windows-1252 decode: lead byte + continuations
MOJIBAKE_RX = re.compile(
    f"[{_cls(0xC2, 0xDF)}]{_CONT}|[{_cls(0xE0, 0xEF)}]{_CONT}{{2}}|[{_cls(0xF0, 0xF4)}]{_CONT}{{3}}"
)
ALLOW_MARK = "qs-allow-mojibake"  # a line containing this text is never reported;
# '...-begin' / '...-end' lines exempt everything between them (documentation examples)


# why: a 2-byte sequence can also be a legitimate pair of Latin-1 characters (a code page table
# in a minified script); only Latin letters and symbols count alone, other scripts (Greek,
# Cyrillic, Hebrew, Arabic) only as two or more letters in a row, like a real word
_LATIN = (0x80, 0x24F)
_SCRIPTS_2 = ((0x370, 0x3FF), (0x400, 0x4FF), (0x5D0, 0x5EA), (0x600, 0x6FF))


def _undo_once(text):
    """Text with every double-encoded sequence decoded back (one level). Returns (text, count)."""
    found = []
    for m in MOJIBAKE_RX.finditer(text):
        try:
            ch = bytes(BYTE_OF[c] for c in m.group()).decode("utf-8")
        except UnicodeDecodeError:
            continue  # why: not a real UTF-8 sequence (overlong, surrogate): leave it
        o = ord(ch)
        kind = (
            "ok"
            if (o >= 0x800 or _LATIN[0] <= o <= _LATIN[1])
            else "word"
            if any(a <= o <= b for a, b in _SCRIPTS_2)
            else None
        )
        if kind:
            found.append([m.start(), m.end(), ch, kind])
    keep = []
    for i, f in enumerate(found):
        if f[3] == "word":
            near = (i > 0 and found[i - 1][1] == f[0] and found[i - 1][3] == "word") or (
                i + 1 < len(found) and found[i + 1][0] == f[1] and found[i + 1][3] == "word"
            )
            if not near:
                continue
        keep.append(f)
    if not keep:
        return text, 0
    out, pos = [], 0
    for a, b, ch, _ in keep:
        out.append(text[pos:a])
        out.append(ch)
        pos = b
    out.append(text[pos:])
    return "".join(out), len(keep)


def undo_double_encoding(text):
    """Repairs text encoded twice or three times. Returns (text, sequences repaired)."""
    total = 0
    for _ in range(3):
        text, n = _undo_once(text)
        total += n
        if not n:
            break
    return text, total


def _show(s):
    """Snippet for a console line: control characters escaped, long text cut."""
    s = "".join(
        ch if (ch >= " " and not "\x7f" <= ch <= "\x9f") else f"\\x{ord(ch):02x}" for ch in s
    )
    return s if len(s) <= 60 else s[:57] + "..."


def _word_at(line, start, end):
    """The word around line[start:end] (up to the nearest blank or quote)."""
    stop = " \t\"'<>()[]{}=,;"
    a, b = start, end
    while a > 0 and line[a - 1] not in stop and start - a < 30:
        a -= 1
    while b < len(line) and line[b] not in stop and b - end < 30:
        b += 1
    return line[a:b]


def decode_mixed(body):
    """Decodes bytes that are UTF-8 except for some Windows-1252 bytes (an editor that saved new
    text in ANSI inside a UTF-8 file). Returns (text, byte offsets decoded as Windows-1252,
    number of genuine multi-byte UTF-8 characters)."""
    spots = []

    def handler(e):
        """Error handler for one undecodable UTF-8 byte: decode it as Windows-1252.

        Args:
            e: the UnicodeDecodeError raised by the decoder.

        Returns:
            tuple: (replacement text, next byte offset). The offset is also recorded in
            the enclosing 'spots' list. Bytes Windows-1252 leaves undefined become chr(byte).
        """
        b = e.object[e.start]
        spots.append(e.start)
        try:
            return bytes([b]).decode("cp1252"), e.start + 1
        except UnicodeDecodeError:
            return chr(b), e.start + 1

    name = f"qs-cp1252-{id(spots)}"
    codecs.register_error(name, handler)
    text = body.decode("utf-8", errors=name)
    utf8_chars = sum(1 for ch in text if ord(ch) >= 0x80) - len(spots)
    return text, spots, utf8_chars


def _spot_words(body, spots):
    """[(line, word)] for byte offsets of a non-UTF-8 file, the word decoded as Windows-1252."""
    out, seen = [], set()
    for pos in spots:
        line, _ = _line_col(body, pos)
        if line in seen:
            continue
        seen.add(line)
        a = body.rfind(b"\n", 0, pos) + 1
        z = body.find(b"\n", pos)
        raw_line = body[a : z if z >= 0 else len(body)]
        text = raw_line.decode("cp1252", errors="replace")
        out.append((line, _word_at(text, pos - a, pos - a + 1)))
    return out


def _lossy(line):
    """The ways an editor writes a line it could not encode.

    Args:
        line: a line of the previous version.

    Returns:
        tuple[str, ...]: the line with '?' and with U+FFFD for each non-ASCII character;
        empty when the line is ASCII.
    """
    if all(ord(c) < 0x80 for c in line):
        return ()
    return (
        "".join(c if ord(c) < 0x80 else "?" for c in line),
        "".join(c if ord(c) < 0x80 else "\ufffd" for c in line),
    )


def decode_any(raw):
    """Text of a previous version whatever its encoding (UTF-8, else Windows-1252)."""
    if raw is None:
        return None
    body = raw[3:] if raw.startswith(BOM_UTF8) else raw
    try:
        return body.decode("utf-8")
    except UnicodeDecodeError:
        return decode_mixed(body)[0]


def mojibake(text, old_text=None):
    """(errors, warnings) for UTF-8 text that holds encoding damage. Findings on lines that are
    identical in old_text (the previous version) are only warnings: they were already there.

    Each finding is a dict: line, col, kind (double|replacement|lost), found, fixed (or None).
    """
    errors, warnings = [], []
    old_lines = set(old_text.splitlines()) if old_text else set()
    lossy = {}
    if old_text:
        for ol in old_text.splitlines():
            for v in _lossy(ol):
                lossy.setdefault(v, ol)
    allowed = False
    for n, line in enumerate(text.splitlines(), 1):
        if ALLOW_MARK in line:
            allowed = (allowed or line.find(ALLOW_MARK + "-begin") >= 0) and line.find(
                ALLOW_MARK + "-end"
            ) < 0
            continue
        if allowed or (all(ord(c) < 0x80 for c in line) and "?" not in line):
            continue
        found = []
        if line in lossy and line not in old_lines:
            kind = "replacement" if "\ufffd" in line else "lost"
            col = (
                next(i for i, (a, b) in enumerate(zip(line, lossy[line], strict=True)) if a != b)
                + 1
            )
            found.append(
                {
                    "line": n,
                    "col": col,
                    "kind": kind,
                    "found": line.strip(),
                    "fixed": lossy[line].strip(),
                }
            )
        else:
            for m in MOJIBAKE_RX.finditer(line):
                fixed, k = undo_double_encoding(m.group())
                if not k:
                    continue
                word = _word_at(line, m.start(), m.end())
                if found and found[-1]["kind"] == "double" and found[-1]["found"] == word:
                    continue
                found.append(
                    {
                        "line": n,
                        "col": m.start() + 1,
                        "kind": "double",
                        "found": word,
                        "fixed": undo_double_encoding(word)[0],
                    }
                )
            i = line.find("\ufffd")
            if i >= 0:
                found.append(
                    {
                        "line": n,
                        "col": i + 1,
                        "kind": "replacement",
                        "found": _word_at(line, i, i + 1),
                        "fixed": None,
                    }
                )
        (warnings if line in old_lines else errors).extend(found)
    return errors, warnings


MOJIBAKE_WHY = {
    "double": "UTF-8 text read as Windows-1252 and saved again",
    "replacement": "characters lost: a Windows-1252 file was opened as UTF-8 and saved",
    "lost": "accents replaced by '?': saved in a charset without them",
}


def describe(f):
    """One line for a mojibake finding."""
    head = f'line {f["line"]}, column {f["col"]}: "{_show(f["found"])}"'
    if f["fixed"]:
        head += f' should be "{_show(f["fixed"])}"'
    return f"{head} ({MOJIBAKE_WHY[f['kind']]})"


def repair(raw, old_raw=None):
    """Repaired bytes of a file that must be UTF-8, and notes on what changed.

    Windows-1252 bytes become UTF-8, double-encoded sequences are decoded back, and lines whose
    accents became '?' or U+FFFD take the accents of the previous version (old_raw) back.
    Returns (bytes, [notes], [problems left]).
    """
    bom = raw.startswith(BOM_UTF8)
    body = raw[3:] if bom else raw
    notes = []
    text, spots, _ = decode_mixed(body)
    if spots:
        notes.append(f"{len(spots)} Windows-1252 character(s) converted to UTF-8")
    text, n = undo_double_encoding(text)
    if n:
        notes.append(f"{n} double-encoded character(s) decoded back")
    old_text = decode_any(old_raw)
    if old_text:
        lossy = {}
        for ol in old_text.splitlines():
            for v in _lossy(ol):
                lossy.setdefault(v, ol)
        old_lines = set(old_text.splitlines())
        restored = 0
        lines = text.split("\n")
        for i, ln in enumerate(lines):
            core = ln[:-1] if ln.endswith("\r") else ln
            if core in lossy and core not in old_lines:
                lines[i] = lossy[core] + ("\r" if ln.endswith("\r") else "")
                restored += 1
        if restored:
            text = "\n".join(lines)
            notes.append(f"{restored} line(s) took their accents back from the previous version")
    left = [describe(f) for f in mojibake(text)[0]]
    return (BOM_UTF8 if bom else b"") + text.encode("utf-8"), notes, left


def _migrate_file(path):
    """Migrate a rules file on disk (host-side, no engine image needed).

    The new text goes to a uniquely named temporary file (`mkstemp`) in the same directory;
    the permission bits of the original are copied to it and it is then moved over the
    original (`os.replace`). Its line endings (LF or CRLF) are kept. If the write or the
    replace fails, the temporary file is removed and the OSError propagates; the original is
    left unchanged. A file with a BOM or that is not UTF-8 is skipped with a warning.

    Args:
        path: the rules file; a missing, empty or unreadable file is left alone.

    Returns:
        int: 0 (also when nothing changed or the file is not usable).

    Raises:
        OSError: when the temporary file cannot be written, copied or moved over the file.
    """
    name = os.path.basename(path)
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError:
        return 0
    if raw.startswith(BOM_UTF8):
        print(f"[quality-suite] WARN {name}: UTF-8 BOM, not migrated", file=sys.stderr)
        return 0
    try:
        data = json.loads(raw.decode("utf-8"))
    except UnicodeDecodeError:
        print(f"[quality-suite] WARN {name}: not UTF-8, not migrated", file=sys.stderr)
        return 0
    except ValueError:
        return 0
    msgs = migrate(data)
    if msgs:
        eol = "\r\n" if b"\r\n" in raw else "\n"
        text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
        directory = os.path.dirname(os.path.abspath(path))
        fd, tmp = tempfile.mkstemp(dir=directory, prefix=name + ".", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline=eol) as fh:
                fh.write(text)
            shutil.copymode(path, tmp)
            os.replace(tmp, path)
        finally:
            # after a successful replace the temp name is gone; otherwise drop the leftover
            with contextlib.suppress(OSError):
                os.remove(tmp)
        for m in msgs:
            print(f"[quality-suite] {name}: {m}")
    return 0


RULES_NAME = ".quality-rules.json"
NO_RULES_MSG = "no rules file (created on the first commit)"


def upgrade(data):
    """Bring a parsed rules file to the current suite version: migrate, then populate.

    `migrate` applies the one-time `branches.model` steps (a 4.x file keeps `flow: merge`);
    `populate` then adds the missing sections and `section.key` defaults. Nothing is ever
    overwritten, nothing is written inside an existing `branches.special.<TYPE>` entry nor over
    `"FORMAT": false` (`get` merges nested defaults at run time). A second call changes nothing.

    Args:
        data: the parsed rules file (dict), changed in place.

    Returns:
        list[str]: `migrated <path>: <old> -> <new>` / `added <path>` lines, empty when the file
        was already up to date.
    """
    changes = list(migrate(data))
    changes += [f"added {path}" for path in populate(data)]
    return changes


def suite_version():
    """The version of this suite folder (its VERSION file).

    Returns:
        str: the version, or '' when the file is missing or unreadable.
    """
    path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "VERSION")
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def stamp_path(repo):
    """The stamp file of a repository: one per clone, shared by every worktree (git common dir).

    Args:
        repo: the repository (or worktree) folder.

    Returns:
        str: the path of `<common dir>/quality-suite/suite-version`, or '' outside a git repository.
    """
    try:
        out = subprocess.run(
            ["git", "-C", repo, "rev-parse", "--git-common-dir"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""
    return os.path.join(os.path.abspath(os.path.join(repo, out)), "quality-suite", "suite-version")


def _write_rules(path, raw, data):
    """Write the upgraded rules file next to itself, then move it over the original.

    Args:
        path: the rules file.
        raw: the original bytes (their line ending, LF or CRLF, is kept).
        data: the upgraded rules (dict).

    Raises:
        OSError: the temporary file cannot be written or moved over the file.
    """
    eol = "\r\n" if b"\r\n" in raw else "\n"
    text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    name = os.path.basename(path)
    fd, tmp = tempfile.mkstemp(
        dir=os.path.dirname(os.path.abspath(path)), prefix=name + ".", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline=eol) as fh:
            fh.write(text)
        shutil.copymode(path, tmp)
        os.replace(tmp, path)
    finally:
        with contextlib.suppress(OSError):
            os.remove(tmp)


def _write_stamp(repo, version):
    """Record the suite version a repository was upgraded to.

    Args:
        repo: the repository folder.
        version: the suite version.

    Raises:
        OSError: the stamp cannot be written.
    """
    path = stamp_path(repo)
    if not path or not version:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(version + "\n")


def _stamp_is_newer(repo, version):
    """Whether the stamp of a repository is newer than the suite version (a downgrade).

    Args:
        repo: the repository folder.
        version: the suite version.

    Returns:
        bool: True when the stamp holds a valid version greater than `version`.
    """
    path = stamp_path(repo)
    try:
        with open(path, encoding="utf-8") as fh:
            stamp = fh.read().strip()
    except OSError:
        return False
    return semver.valid(stamp) and semver.valid(version) and semver.compare(stamp, version) > 0


def rules_upgrade(repo):
    """`rules-upgrade <repo>`: upgrade the rules file of a repository and write the stamp.

    The file is rewritten only when something changed (2-space indent, key order kept, new keys
    appended, UTF-8 without BOM, final newline). Without a rules file only the stamp is written.
    A stamp newer than the suite is a warning: nothing is written (downgrade is out of scope).

    Args:
        repo: the repository folder.

    Returns:
        int: 0 on success (the change lines or a note go to stdout); 1 when the file is not valid
        JSON, has a BOM or cannot be written (message on stderr; file and stamp untouched).
    """
    version = suite_version()
    if _stamp_is_newer(repo, version):
        print(
            f"[quality-suite] WARN: rules stamp is newer than the suite {version}; not upgraded",
            file=sys.stderr,
        )
        return 0
    path = os.path.join(repo, RULES_NAME)
    changes = []
    if not os.path.isfile(path):
        print(NO_RULES_MSG)
    else:
        try:
            with open(path, "rb") as fh:
                raw = fh.read()
            if raw.startswith(BOM_UTF8):
                raise ValueError("UTF-8 BOM")
            data = json.loads(raw.decode("utf-8"))
            if not isinstance(data, dict):
                raise ValueError("not a JSON object")
            changes = upgrade(data)
            if changes:
                _write_rules(path, raw, data)
        except (OSError, ValueError) as err:
            print(f"[quality-suite] ERROR {RULES_NAME}: {err}; not upgraded", file=sys.stderr)
            return 1
    try:
        _write_stamp(repo, version)
    except OSError as err:
        print(f"[quality-suite] ERROR cannot write the suite stamp: {err}", file=sys.stderr)
        return 1
    for line in changes:
        print(line)
    return 0


def _main(argv):
    """Command line: `migrate <file>` or `rules-upgrade <repo>`.

    Args:
        argv: the arguments after the program name.

    Returns:
        int: the exit status; 2 for a wrong command line.
    """
    if len(argv) == 2 and argv[0] == "migrate":
        return _migrate_file(argv[1])
    if len(argv) == 2 and argv[0] == "rules-upgrade":
        return rules_upgrade(argv[1])
    return 2


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
