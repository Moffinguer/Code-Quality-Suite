"""Tool/language registry loading and file classification.

Classification order (first decisive signal wins):
  exclusions -> path globs (most specific) -> modeline -> exact file name -> extension
  (+content probes when ambiguous) -> shebang -> file(1) magic.
file(1) is also the binary guard: binary files are never handed to text tools.
"""
import fnmatch
import json
import os
import re
import subprocess

ROLE_CATEGORY = {"marker": "formatting", "syntax": "syntax", "format": "formatting",
                 "lint": "analysis", "deep": "analysis"}
LEVELS = ["off", "syntax", "format", "standard", "strict"]
ROLE_LEVEL = {"syntax": "syntax", "marker": "format", "format": "format",
              "lint": "standard", "deep": "strict"}
MODELINE = re.compile(r"-\*-.*?\bmode:\s*([\w+#.-]+).*?-\*-|-\*-\s*([\w+#.-]+)\s*-\*-|"
                      r"\bvim?:\s*(?:set\s+)?(?:ft|filetype)=([\w+#.-]+)", re.I)


def level_rank(name):
    return LEVELS.index(name) if name in LEVELS else LEVELS.index("standard")


class Registry:
    def __init__(self, path):
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        self.version = data.get("version", "")
        self.tools = data["tools"]
        self.languages = {l["id"]: l for l in data["languages"]}
        self.global_tools = data.get("global_tools", [])
        self.default_excludes = data.get("default_excludes", [])
        self._index()

    def _index(self):
        self.by_ext, self.by_name, self.globs, self.modelines = {}, {}, [], {}
        self.shebangs, self.magic = [], []
        for lang in self.languages.values():
            m = lang.get("match", {})
            for e in m.get("ext", []):
                ids = self.by_ext.setdefault(e.lower(), [])
                if lang["id"] not in ids:
                    ids.append(lang["id"])
            for n in m.get("names", []):
                ids = self.by_name.setdefault(n, [])
                if lang["id"] not in ids:
                    ids.append(lang["id"])
            for g in m.get("globs", []):
                self.globs.append((g, lang["id"]))
            for ml in m.get("modeline", []):
                self.modelines[ml.lower()] = lang["id"]
            for sb in m.get("shebang", []):
                self.shebangs.append((re.compile(sb), lang["id"]))
            for mg in m.get("magic", []):
                self.magic.append((re.compile(mg, re.I), lang["id"]))
        # most specific glob first (longest pattern)
        self.globs.sort(key=lambda t: -len(t[0]))

    def tools_for(self, lang_id, subtypes=()):
        """Tool ids that apply to a file of this language with these subtypes."""
        lang = self.languages[lang_id]
        tids = list(lang.get("tools", []))
        for st in lang.get("subtypes", []):
            if st["id"] in subtypes:
                excl_roles = set(st.get("exclude_roles", []))
                excl = set(st.get("exclude_tools", []))
                tids = [t for t in tids if t not in excl and self.tools.get(t, {}).get("role") not in excl_roles]
                tids += [t for t in st.get("tools", []) if t not in tids]
        return tids

    def section_tools(self, lang_id):
        """Every tool id a language section can configure (base + subtypes + fallbacks)."""
        lang = self.languages[lang_id]
        tids = list(lang.get("tools", []))
        for st in lang.get("subtypes", []):
            tids += [t for t in st.get("tools", []) if t not in tids]
        # why: an opt-in tool (off by default) leaves the gap to the built-in fallback
        roles = {self.tools[t]["role"] for t in tids if t in self.tools
                 and self.tools[t].get("default_enabled", True)}
        if "syntax" not in roles:
            tids.append("qs-basic-syntax")
        if "format" not in roles and not lang.get("basic", {}).get("no_format"):
            tids.append("qs-basic-format")
        return tids


def file_magic(paths):
    """Return {path: (mime, charset, description)} using file(1), batched."""
    out = {}
    if not paths:
        return out
    try:
        res = subprocess.run(["file", "-N", "-0", "--mime-type", "--mime-encoding", "--", *paths],
                             capture_output=True, text=True, timeout=120)
        res2 = subprocess.run(["file", "-N", "-0", "--", *paths],
                              capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError):
        return out
    desc = {}
    for line in res2.stdout.splitlines():
        if "\0" in line:
            p, d = line.split("\0", 1)
            desc[p] = d.lstrip(": ").strip()
    for line in res.stdout.splitlines():
        if "\0" not in line:
            continue
        p, info = line.split("\0", 1)
        info = info.lstrip(": ").strip()
        mime, _, cs = info.partition(";")
        charset = cs.strip().replace("charset=", "") if cs else ""
        out[p] = (mime.strip(), charset, desc.get(p, ""))
    return out


def _head(path, size=8192):
    try:
        with open(path, "rb") as fh:
            return fh.read(size).decode("utf-8", "replace")
    except OSError:
        return ""


def _match_glob(rel, pattern):
    """fnmatch where '*' may cross directories; a relative pattern with '/' matches at any depth."""
    rel = rel.replace(os.sep, "/")
    if "/" not in pattern:
        return fnmatch.fnmatch(os.path.basename(rel), pattern) or fnmatch.fnmatch(rel, pattern)
    pat = pattern.replace("**/", "*/") if pattern.startswith("**/") else pattern
    return (fnmatch.fnmatch(rel, pat) or fnmatch.fnmatch("/" + rel, pat)
            or (not pat.startswith(("/", "*")) and fnmatch.fnmatch(rel, "*/" + pat)))


class Classification:
    __slots__ = ("path", "lang", "subtypes", "skip", "reason", "confident", "charset", "binary")

    def __init__(self, path):
        self.path, self.lang, self.subtypes = path, None, []
        self.skip, self.reason, self.confident = False, "", True
        self.charset, self.binary = "", False


def _probe(reg, candidates, head):
    """Pick a language among candidates using content probes. Returns (lang, confident)."""
    scores = {}
    for lid in candidates:
        for pr in reg.languages[lid].get("match", {}).get("probe", []):
            if re.search(pr["re"], head, re.M):
                scores[lid] = scores.get(lid, 0) + pr.get("weight", 1)
    if not scores:
        default = [l for l in candidates if reg.languages[l].get("match", {}).get("default_for_ambiguous")]
        return (default[0] if default else candidates[0]), False
    ranked = sorted(scores.items(), key=lambda kv: -kv[1])
    confident = len(ranked) == 1 or ranked[0][1] > ranked[1][1]
    return ranked[0][0], confident


def classify(reg, root, rels, excludes, extra_ext=None):
    """Classify repo-relative paths. Returns list[Classification]."""
    abspaths = [os.path.join(root, r) for r in rels]
    magic = file_magic([p for p in abspaths if os.path.isfile(p)])
    extra_ext = extra_ext or {}
    results = []
    for rel, ap in zip(rels, abspaths):
        c = Classification(rel)
        results.append(c)
        if not os.path.isfile(ap):
            c.skip, c.reason = True, "not a regular file"
            continue
        mime, charset, desc = magic.get(ap, ("", "", ""))
        c.charset = charset
        if charset == "binary" or (mime and not mime.startswith(("text/", "application/json", "application/xml",
                                                                    "application/javascript", "image/svg",
                                                                    "application/x-", "inode/x-empty",
                                                                    "application/octet-stream"))):
            if charset == "binary":
                c.skip, c.binary, c.reason = True, True, f"binary ({mime})"
                continue
        if any(_match_glob(rel, ex) for ex in excludes):
            c.skip, c.reason = True, "excluded"
            continue
        base = os.path.basename(rel)
        head = _head(ap)
        for pattern, lid in reg.globs:
            if _match_glob(rel, pattern):
                c.lang = lid
                break
        if not c.lang:
            first = "\n".join(head.splitlines()[:2] + head.splitlines()[-3:])
            mm = MODELINE.search(first)
            if mm:
                mode = next(g for g in mm.groups() if g).lower()
                if mode in reg.modelines:
                    c.lang = reg.modelines[mode]
        if not c.lang and base in reg.by_name:
            # why: an exact file name (CMakeLists.txt, meson_options.txt) beats its extension
            c.lang = reg.by_name[base][0]
        if not c.lang:
            low = base.lower()
            cands = []
            for k, v in extra_ext.items():
                if low.endswith(k.lower()):
                    cands = [v]
                    break
            if not cands:
                exts = sorted((e for e in reg.by_ext if low.endswith(e)), key=len, reverse=True)
                if exts:
                    cands = reg.by_ext[exts[0]]
            if len(cands) == 1:
                c.lang = cands[0]
            elif len(cands) > 1:
                c.lang, c.confident = _probe(reg, cands, head)
        if not c.lang and base in reg.by_name:
            c.lang = reg.by_name[base][0]
        if not c.lang and head.startswith("#!"):
            line = head.splitlines()[0]
            for rx, lid in reg.shebangs:
                if rx.search(line):
                    c.lang = lid
                    break
        if not c.lang and desc:
            for rx, lid in reg.magic:
                if rx.search(desc):
                    c.lang = lid
                    break
        if not c.lang:
            c.skip, c.reason = True, f"no language matched ({desc or mime or 'unknown'})"
            continue
        lang = reg.languages[c.lang]
        for st in lang.get("subtypes", []):
            # why: every criterion given must hold (e.g. issue forms = path glob AND a body: key)
            m = st.get("match", {})
            checks = []
            if m.get("globs"):
                checks.append(any(_match_glob(rel, g) for g in m["globs"]))
            if m.get("content"):
                checks.append(all(re.search(rx, head, re.M) for rx in m["content"]))
            if m.get("names"):
                checks.append(base in m["names"])
            if checks and all(checks):
                c.subtypes.append(st["id"])
    return results
