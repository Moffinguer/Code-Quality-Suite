"""Language version resolution.

Precedence: rules file `languages.<lang>.version` (unless "auto")
            > legacy env var (e.g. PMD_JAVA_VERSION) > manifest detection > registry default.
"""
import os
import re


def _read(path, limit=262144):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read(limit)
    except OSError:
        return ""


def detect(spec, root):
    """Return (value, source) from the language's `version.detect` list, or (None, None)."""
    for d in spec.get("detect", []):
        candidates = [d["file"]] if "*" not in d["file"] else _glob_root(root, d["file"])
        for rel in candidates:
            text = _read(os.path.join(root, rel))
            if not text:
                continue
            m = re.search(d["re"], text, re.M | re.S)
            if m:
                val = next((g for g in m.groups() if g), m.group(0)).strip()
                val = d.get("map", {}).get(val, val)
                return val, rel
    return None, None


def _glob_root(root, pattern):
    import fnmatch
    try:
        return sorted(f for f in os.listdir(root) if fnmatch.fnmatch(f, pattern))[:5]
    except OSError:
        return []


def resolve(lang, rules_lang, root):
    """Return (version, source)."""
    spec = lang.get("version")
    if not spec:
        return None, None
    pinned = (rules_lang or {}).get("version", "auto")
    if pinned and pinned != "auto":
        return str(pinned), "rules"
    env = spec.get("env")
    if env and os.environ.get(env):
        return os.environ[env], f"env:{env}"
    val, src = detect(spec, root)
    if val:
        return val, src
    return spec.get("default"), "default"


def fmt(template, version):
    """Expand {v}, {v_nodot}, {v_major}, {v_minor} in a template string."""
    v = str(version or "")
    parts = re.findall(r"\d+", v)
    return (template.replace("{v_nodot}", "".join(parts[:2]))
            .replace("{v_major}", parts[0] if parts else "")
            .replace("{v_minor}", parts[1] if len(parts) > 1 else "0")
            .replace("{v}", v))
