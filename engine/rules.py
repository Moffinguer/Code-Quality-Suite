"""Universal rules file (.quality-rules.json): load, validate, populate, diff.

Layout:
  { "$schema": ..., "version": 1, "level": "standard", "exclude": [..],
    "encoding":  { charset, bom, by_language, by_glob },        (policy.py)
    "commit":    { charset, types, subject_max, conventional },  (policy.py, host hooks)
    "branches":  { parent_leaf, levels, segment, ... },          (policy.py, host hooks)
    "global":    { <tool>: {enabled, args, rules} },
    "languages": { <lang>: { enabled, level, version, detected_version,
                             syntax|formatting|analysis: { <tool>: {enabled, args, rules} } } },
    "tests":     { "commands": [..], "autodetect": false } }
Starts as a skeleton; a language section is added (with the image's base rules) the
first time that language is detected. Values you edit are never overwritten.
"""
import copy
import json
import os

import policy as P
from registry import LEVELS, ROLE_CATEGORY

CATEGORIES = ("syntax", "formatting", "analysis")
_REG = None  # set by qs.App so settings fall back to registry defaults when a block is absent


def bind(reg):
    global _REG
    _REG = reg
SCHEMA_VERSION = 1


def skeleton(schema_ref):
    data = {"$schema": schema_ref, "version": SCHEMA_VERSION, "level": "standard", "exclude": []}
    P.populate(data)
    data.update({"global": {}, "languages": {}, "tests": {"commands": [], "autodetect": False}})
    return data


def load(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if not text.strip():
        return None
    return json.loads(text)


def save(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)


def tool_defaults(tool, lang=None):
    """Base rules for a tool in a language: tool defaults + language-specific overrides."""
    base = copy.deepcopy(tool.get("defaults", {}))
    if tool.get("id") == "qs-marker":
        base = copy.deepcopy((lang or {}).get("marker") or {})
    over = ((lang or {}).get("tool_defaults") or {}).get(tool["id"])
    if over:
        base.update(copy.deepcopy(over))
    return base


def tool_block(tool, lang=None):
    block = {"enabled": tool.get("default_enabled", True), "args": []}
    block["rules"] = tool_defaults(tool, lang)
    return block


def populate_language(data, reg, lang_id, version_info=None, env_version=None):
    """Add a language section with base rules. Returns True if added."""
    langs = data.setdefault("languages", {})
    if lang_id in langs:
        return False
    lang = reg.languages[lang_id]
    sec = {"enabled": True}
    if lang.get("version"):
        sec["version"] = env_version or "auto"
        if version_info and version_info[0]:
            sec["detected_version"] = f"{version_info[0]} ({version_info[1]})"
    for tid in reg.section_tools(lang_id):
        tool = reg.tools.get(tid)
        if not tool or tool.get("internal"):
            continue
        cat = ROLE_CATEGORY[tool["role"]]
        sec.setdefault(cat, {})[tid] = tool_block(tool, lang)
    langs[lang_id] = sec
    return True


def populate_global(data, reg):
    g = data.setdefault("global", {})
    added = False
    for tid in reg.global_tools:
        if tid not in g and tid in reg.tools:
            g[tid] = tool_block(reg.tools[tid])
            added = True
    return added


def validate(data, reg):
    """Return (errors, warnings)."""
    errors, warnings = [], []
    if not isinstance(data, dict):
        return ["root must be a JSON object"], []
    errors += P.validate(data)
    for k in data:
        if k not in ("$schema", "$comment", "version", "level", "exclude", "global", "languages", "tests") + P.SECTIONS:
            warnings.append(f"{k}: unknown top-level key (ignored)")
    if data.get("level", "standard") not in LEVELS:
        errors.append(f"level: must be one of {LEVELS}")
    if not isinstance(data.get("exclude", []), list):
        errors.append("exclude: must be a list of globs")
    for tid, blk in (data.get("global") if isinstance(data.get("global"), dict) else {}).items():
        errors += _check_block(f"global.{tid}", blk)
        if tid not in reg.tools:
            warnings.append(f"global.{tid}: unknown tool (ignored)")
    for lid, sec in (data.get("languages") if isinstance(data.get("languages"), dict) else {}).items():
        p = f"languages.{lid}"
        if lid not in reg.languages:
            warnings.append(f"{p}: unknown language (ignored)")
            continue
        if not isinstance(sec, dict):
            errors.append(f"{p}: must be an object")
            continue
        if sec.get("level", "standard") not in LEVELS + ["inherit"]:
            errors.append(f"{p}.level: must be one of {LEVELS}")
        for cat in CATEGORIES:
            for tid, blk in (sec.get(cat) or {}).items():
                errors += _check_block(f"{p}.{cat}.{tid}", blk)
                if tid not in reg.tools:
                    warnings.append(f"{p}.{cat}.{tid}: unknown tool (ignored)")
        for k in sec:
            if k not in ("enabled", "level", "version", "detected_version", "extensions", "$comment") + CATEGORIES:
                warnings.append(f"{p}.{k}: unknown key (ignored)")
    t = data.get("tests") or {}
    if not isinstance(t, dict):
        errors.append("tests: must be an object like {\"commands\": [...], \"autodetect\": false}")
    elif not isinstance(t.get("commands", []), list):
        errors.append("tests.commands: must be a list of strings")
    for key in ("global", "languages"):
        if not isinstance(data.get(key, {}), dict):
            errors.append(f"{key}: must be an object")
    return errors, warnings


def _check_block(path, blk):
    errs = []
    if not isinstance(blk, dict):
        return [f"{path}: must be an object"]
    if "enabled" in blk and not isinstance(blk["enabled"], bool):
        errs.append(f"{path}.enabled: must be true/false")
    if "args" in blk and not (isinstance(blk["args"], list) and all(isinstance(a, str) for a in blk["args"])):
        errs.append(f"{path}.args: must be a list of strings")
    if "rules" in blk and not isinstance(blk["rules"], dict):
        errs.append(f"{path}.rules: must be an object")
    if "level" in blk and blk["level"] not in LEVELS:
        errs.append(f"{path}.level: must be one of {LEVELS}")
    return errs


def tool_settings(data, lang_id, tool_id, role):
    """Effective {enabled, args, rules, level} for a tool, from the rules file."""
    if lang_id == "_global":
        blk = (data.get("global") or {}).get(tool_id, {})
    else:
        sec = (data.get("languages") or {}).get(lang_id, {})
        blk = (sec.get(ROLE_CATEGORY[role]) or {}).get(tool_id, {})
    tool = (_REG.tools.get(tool_id) if _REG else None) or {}
    lang = (_REG.languages.get(lang_id) if _REG else None) or {}
    fallback = tool_defaults(tool, lang) if tool and not blk else {}
    return {"enabled": blk.get("enabled", tool.get("default_enabled", True)), "args": blk.get("args", []),
            "rules": blk.get("rules", fallback), "level": blk.get("level"),
            "autofix": blk.get("autofix", tool.get("autofix", False))}


def lang_level(data, lang_id, env_level=None):
    sec = (data.get("languages") or {}).get(lang_id, {})
    if sec.get("enabled") is False:
        return "off"
    lv = sec.get("level")
    if lv and lv != "inherit":
        return lv
    return env_level or data.get("level", "standard")


def diff(old, new, path=""):
    """Path-level differences: list of (path, old, new)."""
    out = []
    if isinstance(old, dict) and isinstance(new, dict):
        for k in old:
            if k not in new:
                out.append((f"{path}.{k}".lstrip("."), old[k], None))
        for k in new:
            p = f"{path}.{k}".lstrip(".")
            if k not in old:
                out.append((p, None, new[k]))
            else:
                out += diff(old[k], new[k], p)
    elif old != new:
        out.append((path, old, new))
    return out


def short(v, limit=80):
    s = json.dumps(v, ensure_ascii=False) if not isinstance(v, str) else v
    return s if len(s) <= limit else s[: limit - 3] + "..."
