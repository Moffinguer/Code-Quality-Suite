#!/usr/bin/env python3
"""Generate registry/registry.json, schema/quality-rules.schema.json and docs/LANGUAGES.md
from the catalog in registry/src. Validates cross references; exits 1 on errors.

  python3 tools/gen.py [--check]     --check: fail if generated files are stale
"""
import json
import os
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "registry", "src"))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import core  # noqa: E402
import base  # noqa: E402,F401
import fam_web  # noqa: E402,F401
import fam_jvm  # noqa: E402,F401
import fam_script  # noqa: E402,F401
import fam_systems  # noqa: E402,F401
import fam_data  # noqa: E402,F401
import fam_docs  # noqa: E402,F401
import fam_more  # noqa: E402,F401  (2.1 additions; extends languages defined above)
import writers  # noqa: E402

ROLES = {"syntax", "marker", "format", "lint", "deep"}
LEVELS = ["off", "syntax", "format", "standard", "strict"]
VERSION = open(os.path.join(ROOT, "VERSION")).read().strip()
DEFAULT_EXCLUDES = ["**/node_modules/**", "**/vendor/**", "**/.git/**", "**/__pycache__/**", "**/.venv/**",
                    "**/venv/**", "*.min.js", "*.min.css", "*.map", "**/.mypy_cache/**", "**/.ruff_cache/**",
                    "**/.gradle/**", "**/target/**", "**/.terraform/**", "**/.dart_tool/**",
                    ".quality-rules.json"]


# ------------------------------------------------------------------ base config -> default rules

def checkstyle_defaults(text):
    import re
    root = ET.fromstring(re.sub(r"<!DOCTYPE[^>]*>", "", text))
    out, seen = {}, {}
    for m in root.iter("module"):
        name = m.get("name")
        if name in ("Checker", "TreeWalker"):
            continue
        seen[name] = seen.get(name, 0) + 1
        props = {p.get("name"): p.get("value") for p in m.findall("property")}
        out[name] = props or True
    return {k: v for k, v in out.items() if seen[k] == 1}  # why: repeated modules stay in the base only


def pmd_defaults(text):
    ns = "{http://pmd.sourceforge.net/ruleset/2.0.0}"
    root = ET.fromstring(text)
    out = {}
    for r in root.findall(f"{ns}rule"):
        ref = r.get("ref")
        out[ref] = True
        for ex in r.findall(f"{ns}exclude"):
            out[f"{ref}/{ex.get('name')}"] = False
    return out


def base_defaults(tool):
    cfg = tool.get("config") or {}
    rel = cfg.get("base")
    if not rel or rel.startswith("{"):
        return None
    path = os.path.join(ROOT, "config", rel)
    if not os.path.exists(path):
        raise SystemExit(f"tool {tool['id']}: base config not found: config/{rel}")
    text = open(path, encoding="utf-8").read()
    fmt = cfg["format"]
    if fmt == "checkstyle":
        return checkstyle_defaults(text)
    if fmt == "pmd":
        return pmd_defaults(text)
    if fmt in writers.MERGEABLE:
        return writers.parse(fmt, text)
    return None


# ------------------------------------------------------------------ validation

def validate(tools, langs, runtimes):
    errs, warns = [], []
    for t in tools.values():
        if t["role"] not in ROLES:
            errs.append(f"tool {t['id']}: bad role {t['role']}")
        for n in t.get("needs", []):
            if n not in runtimes:
                errs.append(f"tool {t['id']}: unknown runtime {n}")
        inh = (t.get("config") or {}).get("inherit")
        if inh and inh not in tools:
            errs.append(f"tool {t['id']}: inherits unknown tool {inh}")
        if not t.get("install") and "builtin" not in t["cmd"] and not t.get("needs") and t.get("bin") and \
                not set(t["bin"]) <= {"bash", "dash", "git", "gcc", "node"}:
            warns.append(f"tool {t['id']}: no install channel (must come from a runtime)")
        if t.get("level") and t["level"] not in LEVELS:
            errs.append(f"tool {t['id']}: bad level {t['level']}")
    exts = {}
    for l in langs:
        for tid in l["tools"]:
            if tid not in tools:
                errs.append(f"lang {l['id']}: unknown tool {tid}")
        for st in l.get("subtypes", []):
            for tid in st.get("tools", []) + st.get("exclude_tools", []):
                if tid not in tools:
                    errs.append(f"lang {l['id']}.{st['id']}: unknown tool {tid}")
        for tid in (l.get("tool_defaults") or {}):
            if tid not in tools:
                errs.append(f"lang {l['id']}: tool_defaults for unknown tool {tid}")
        uses_marker = "qs-marker" in l["tools"]
        if uses_marker and not l.get("marker"):
            errs.append(f"lang {l['id']}: qs-marker without a marker spec")
        if l.get("marker") and not uses_marker:
            l["tools"].insert(0, "qs-marker")
        for e in l["match"].get("ext", []):
            exts.setdefault(e.lower(), set()).add(l["id"])
        for t in [x for x in l["tools"] if x in tools]:
            tv = tools[t].get("version_rules") or any("{v" in str(x) for x in json.dumps(tools[t]["cmd"]).split('"'))
            if tv and not l.get("version") and "{var:" not in json.dumps(tools[t]["cmd"]):
                warns.append(f"lang {l['id']}: tool {t} uses the version but the language has none")
    for e, ids in sorted(exts.items()):
        if len(ids) > 1:
            probes = [i for i in ids if next(x for x in langs if x["id"] == i)["match"].get("probe")]
            defaults = [i for i in ids if next(x for x in langs if x["id"] == i)["match"].get("default_for_ambiguous")]
            if not probes:
                errs.append(f"extension {e} shared by {sorted(ids)} without content probes")
            if len(defaults) > 1:
                errs.append(f"extension {e}: several default_for_ambiguous {sorted(defaults)}")
    return errs, warns


# ------------------------------------------------------------------ schema

def policy_schema():
    """encoding / commit / branches sections (engine/policy.py holds the defaults)."""
    sys.path.insert(0, os.path.join(ROOT, "engine"))
    import policy as P
    d = P.DEFAULTS
    cs = {"type": "string", "examples": ["utf-8", "iso-8859-1", "windows-1252", "ascii"]}
    bom = {"enum": ["forbid", "allow", "require"]}
    per = {"oneOf": [cs, {"type": "object", "properties": {"charset": cs, "bom": bom}, "additionalProperties": False}]}
    return {
        "encoding": {"type": "object", "description": "charset every shared text file must use; a file in another "
                     "encoding (or converted) blocks the commit", "additionalProperties": False, "properties": {
            "enabled": {"type": "boolean", "default": True},
            "charset": dict(cs, default=d["encoding"]["charset"]),
            "bom": dict(bom, default=d["encoding"]["bom"]),
            "by_language": {"type": "object", "additionalProperties": per, "default": d["encoding"]["by_language"],
                            "description": "language id -> charset or {charset, bom}"},
            "by_glob": {"type": "object", "additionalProperties": per,
                        "description": "path glob -> charset or {charset, bom}; first match wins"},
            "mojibake": {"enum": ["block", "warn", "off"], "default": d["encoding"]["mojibake"],
                         "description": "text damaged by a save in the wrong encoding (double-encoded accents, "
                                        "U+FFFD, accents turned into '?'): block the commit, warn, or ignore"},
            "mojibake_ignore": {"type": "array", "items": {"type": "string"}, "default": [],
                                "description": "path globs never checked for mojibake (encoding test fixtures)"}}},
        "commit": {"type": "object", "additionalProperties": False, "properties": {
            "charset": {"enum": ["ascii", "utf-8", "any"], "default": d["commit"]["charset"],
                        "description": "ascii: no accents, n-tilde or diaeresis in commit messages"},
            "types": {"type": "array", "items": {"type": "string", "pattern": "^[a-z][a-z0-9-]*$"},
                      "default": d["commit"]["types"]},
            "subject_max": {"type": "integer", "minimum": 10, "default": d["commit"]["subject_max"]},
            "conventional": {"type": "boolean", "default": True}}},
        "branches": {"type": "object", "additionalProperties": False, "properties": {
            "enforce": {"enum": ["block", "warn", "off"], "default": "block"},
            "parent_leaf": {"type": "string", "default": d["branches"]["parent_leaf"],
                            "description": "last segment of a branch that has children"},
            "mainline": {"type": "string", "default": "develop"},
            "protected": {"type": "array", "items": {"type": "string"}, "default": d["branches"]["protected"]},
            "levels": {"type": "array", "items": {"type": "string"}, "default": d["branches"]["levels"],
                       "description": "regex per segment: [0] version, [1] OT, ..."},
            "segment": {"type": "string", "default": d["branches"]["segment"],
                        "description": "regex for deeper segments"},
            "allow": {"type": "array", "items": {"type": "string"}, "description": "extra allowed branch regexes"},
            "leaf_merge": {"enum": ["merge", "squash"], "default": "merge"},
            "require_children_merged": {"type": "boolean", "default": True},
            "tag": {"type": "string", "default": "{version}", "description": "{version} {ot} {date}"},
            "tag_level": {"type": "integer", "minimum": 0, "default": 1},
            "release_leaf": {"type": "string", "pattern": "^[A-Za-z0-9_-]+$", "default": d["branches"]["release_leaf"],
                             "description": "git release: '<version>/ORIGINAL' is renamed to '<version>/<release_leaf>'"},
            "archive_prefix": {"type": "string", "pattern": "^[A-Za-z0-9_-]+$",
                               "default": d["branches"]["archive_prefix"],
                               "description": "git release: branches never integrated become '<archive_prefix>/<name>'"},
            "version_file": {"type": "string", "default": d["branches"]["version_file"],
                             "description": "file holding the version, committed on '<version>/ORIGINAL' when the "
                                            "tree is created ('' = off)"},
            "changelog_file": {"type": "string", "default": d["branches"]["changelog_file"],
                               "description": "git release: release notes in Common Changelog format ('' = off)"},
            "readme_file": {"type": "string", "default": d["branches"]["readme_file"],
                            "description": "git release: version badge updated here ('' = off)"},
            "pom_version": {"enum": ["update", "snapshot", "check", "off"], "default": d["branches"]["pom_version"],
                            "description": "pom.xml <version> follows the version tree: update (= version), "
                                           "snapshot (version-SNAPSHOT until git release), check (only verify), off"},
            "tag_url": {"type": "string", "default": "",
                        "description": "changelog link of a release: '' = derived from origin, '-' = none, "
                                       "or a URL with {tag}"},
            "commit_url": {"type": "string", "default": "",
                           "description": "changelog reference of a commit: '' = derived from origin, '-' = none, "
                                          "or a URL with {commit}"}}},
    }


def block_schema(tool, defaults):
    rules = {"type": "object", "description": tool.get("notes", tool["name"])}
    if defaults:
        rules["default"] = defaults
    return {"type": "object", "title": tool["name"], "additionalProperties": False, "properties": {
        "enabled": {"type": "boolean", "default": tool.get("default_enabled", True)},
        "level": {"enum": LEVELS, "description": "minimum quality level at which this tool runs"},
        "args": {"type": "array", "items": {"type": "string"}, "description": "extra command-line arguments"},
        "autofix": {"type": "boolean", "description": "lint tools: apply safe fixes during the commit"},
        "rules": rules}}


def make_schema(tools, langs):
    lang_props = {}
    for l in langs:
        cats = {"syntax": {}, "formatting": {}, "analysis": {}}
        cat_of = {"syntax": "syntax", "marker": "formatting", "format": "formatting", "lint": "analysis",
                  "deep": "analysis"}
        ids = list(l["tools"]) + [t for st in l.get("subtypes", []) for t in st.get("tools", [])]
        roles = {tools[t]["role"] for t in ids if tools[t].get("default_enabled", True)}
        if "syntax" not in roles:
            ids.append("qs-basic-syntax")
        if "format" not in roles and not (l.get("basic") or {}).get("no_format"):
            ids.append("qs-basic-format")
        for tid in dict.fromkeys(ids):
            t = tools[tid]
            over = (l.get("tool_defaults") or {}).get(tid)
            if over:
                d = dict(t.get("defaults") or {})
                d.update(over)
                cats[cat_of[t["role"]]][tid] = block_schema(t, d)
            else:
                cats[cat_of[t["role"]]][tid] = {"$ref": f"#/$defs/{tid}"}
        props = {"enabled": {"type": "boolean", "default": True},
                 "level": {"enum": LEVELS + ["inherit"], "default": "inherit"},
                 "extensions": {"type": "array", "items": {"type": "string"},
                                "description": "extra extensions mapped to this language"},
                 "$comment": {"type": "string"}}
        if l.get("version"):
            v = l["version"]
            vs = {"type": "string", "default": "auto",
                  "description": (v.get("label") or "version") + "; 'auto' = detect from the project"
                                 + (f" (legacy env {v['env']})" if v.get("env") else "")}
            if v.get("choices"):
                vs["examples"] = ["auto"] + v["choices"]
            props["version"] = vs
            props["detected_version"] = {"type": "string", "description": "written by the suite (read-only)"}
        for c, tp in cats.items():
            if tp:
                props[c] = {"type": "object", "properties": tp, "additionalProperties": False}
        lang_props[l["id"]] = {"type": "object", "title": l["name"], "properties": props,
                               "additionalProperties": False}
    glob = {tid: {"$ref": f"#/$defs/{tid}"} for tid in core.GLOBAL_TOOLS}
    defs = {tid: block_schema(t, t.get("defaults")) for tid, t in tools.items()}
    return {
        "$defs": defs,
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://code-quality-suite.local/quality-rules.schema.json",
        "title": "code-quality-suite rules (.quality-rules.json)",
        "type": "object",
        "properties": {
            "$schema": {"type": "string"},
            "version": {"const": 1},
            "level": {"enum": LEVELS, "default": "standard",
                      "description": "off < syntax < format < standard < strict (cumulative)"},
            "exclude": {"type": "array", "items": {"type": "string"}, "description": "globs never analysed"},
            **policy_schema(),
            "global": {"type": "object", "properties": glob, "additionalProperties": False},
            "languages": {"type": "object", "properties": lang_props, "additionalProperties": False},
            "tests": {"type": "object", "properties": {
                "commands": {"type": "array", "items": {"type": "string"}},
                "autodetect": {"type": "boolean"}}},
        },
        "additionalProperties": False,
    }


# ------------------------------------------------------------------ docs matrix

def make_matrix(tools, langs):
    def label(t):
        return tools[t]["name"] + ("" if tools[t].get("default_enabled", True) else " (opt-in)")

    def names(l, role):
        ids = [t for t in l["tools"] if tools[t]["role"] == role]
        return ", ".join(label(t) for t in ids) or ""
    rows = ["| Language | Syntax | Format | Lint (standard) | Deep (strict) | Version knob |",
            "| --- | --- | --- | --- | --- | --- |"]
    for l in sorted(langs, key=lambda x: x["name"].lower()):
        roles = {tools[t]["role"] for t in l["tools"]}
        on = lambda r: any(tools[t]["role"] == r and tools[t].get("default_enabled", True) for t in l["tools"])
        syn = names(l, "syntax") + ("" if on("syntax") else (" + " if names(l, "syntax") else "") + "built-in")
        dflt = "— (whitespace is significant)" if (l.get("basic") or {}).get("no_format") else "built-in safe"
        fmt = names(l, "format") + ("" if on("format") else (" / " if names(l, "format") else "") + dflt)
        lint = names(l, "lint")
        sub = [f"{st['name']}: {', '.join(label(t) for t in st.get('tools', []))}"
               for st in l.get("subtypes", []) if st.get("tools")]
        if sub:
            lint = (lint + "; " if lint else "") + "; ".join(sub)
        deep = names(l, "deep")
        ver = ""
        if l.get("version"):
            v = l["version"]
            ver = f"`{v.get('env') or 'version'}` (default {v['default']})"
        rows.append(f"| {l['name']} | {syn} | {fmt} | {lint or '—'} | {deep or '—'} | {ver or '—'} |")
    cands = [f"- **{l['name']}**: {'; '.join(l['candidates'])}" for l in sorted(langs, key=lambda x: x['name'].lower())
             if l.get("candidates")]
    return rows, cands


def main(argv):
    tools, langs, runtimes = core.TOOLS, core.LANGS, core.RUNTIMES
    errs, warns = validate(tools, langs, runtimes)
    for w in warns:
        print("WARN", w)
    if errs:
        for e in errs:
            print("ERROR", e)
        return 1
    for t in tools.values():
        b = base_defaults(t)
        if b is not None:
            t["defaults"] = writers.deep_merge(b, t.get("defaults") or {})
    reg = {"version": VERSION, "tools": tools, "languages": langs, "runtimes": runtimes,
           "global_tools": list(core.GLOBAL_TOOLS), "default_excludes": DEFAULT_EXCLUDES}
    out = {
        os.path.join(ROOT, "registry", "registry.json"): json.dumps(reg, indent=1, ensure_ascii=False) + "\n",
        os.path.join(ROOT, "schema", "quality-rules.schema.json"):
            json.dumps(make_schema(tools, langs), indent=1, ensure_ascii=False) + "\n",
    }
    rows, cands = make_matrix(tools, langs)
    md = open(os.path.join(ROOT, "docs", "LANGUAGES.md.in"), encoding="utf-8").read()
    md = md.replace("@MATRIX@", "\n".join(rows)).replace("@CANDIDATES@", "\n".join(cands))
    md = md.replace("@COUNTS@", f"{len(langs)} languages, {len(tools)} tool entries")
    out[os.path.join(ROOT, "docs", "LANGUAGES.md")] = md
    stale = []
    for path, text in out.items():
        cur = open(path, encoding="utf-8").read() if os.path.exists(path) else None
        if cur != text:
            stale.append(os.path.relpath(path, ROOT))
            if "--check" not in argv:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(text)
    print(f"{len(langs)} languages, {len(tools)} tools, {len(runtimes)} runtimes"
          + (f"; {'stale' if '--check' in argv else 'written'}: {', '.join(stale)}" if stale else "; up to date"))
    return 1 if stale and "--check" in argv else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
