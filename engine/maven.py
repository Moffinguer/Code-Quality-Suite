"""Project version in build files: VERSION, Maven pom.xml (multi-module), package.json.

The pom.xml files are edited in place, text only: the version text is replaced and nothing
else changes (formatting, comments and attribute order stay as they are).

  set_versions(root, version)  VERSION + the root pom's <version> + every in-repository module
                               that shares it (own <version> and <parent><version>) + package.json
  read_versions(root)          {"VERSION": ..., "pom.xml": ..., "package.json": ...}
"""
import json
import os
import re

SKIP_DIRS = {".git", "target", "node_modules", "build", "out", "dist", ".idea", ".settings", ".vscode", ".mvn"}
TOKEN = re.compile(r"<!--.*?-->|<!\[CDATA\[.*?\]\]>|<\?.*?\?>|<!DOCTYPE[^>]*>|"
                   r"<(/?)([A-Za-z_][\w.:-]*)((?:[^>\"']|\"[^\"]*\"|'[^']*')*?)(/?)>", re.S)


def scan(text):
    """{element path: (start, end)} of the text of every element, first occurrence of each path.
    Paths look like 'project/parent/version'."""
    stack, out = [], {}
    for m in TOKEN.finditer(text):
        if m.group(2) is None:
            continue                                   # comment, CDATA, declaration
        close, name, selfclose = m.group(1), m.group(2).split(":")[-1], m.group(4)
        if close:
            if stack and stack[-1][0] == name:
                n, start = stack.pop()
                out.setdefault("/".join([s[0] for s in stack] + [n]), (start, m.start()))
        elif not selfclose:
            stack.append((name, m.end()))
    return out


def pom_info(text):
    spans = scan(text)

    def val(path):
        sp = spans.get(path)
        return text[sp[0]:sp[1]].strip() if sp else None
    info = {k: val(p) for k, p in (("group", "project/groupId"), ("artifact", "project/artifactId"),
                                   ("version", "project/version"), ("pgroup", "project/parent/groupId"),
                                   ("partifact", "project/parent/artifactId"),
                                   ("pversion", "project/parent/version"),
                                   ("revision", "project/properties/revision"))}
    info["group"] = info["group"] or info["pgroup"]
    info["spans"] = spans
    return info


def _replace(text, span, value):
    a, b = span
    inner = text[a:b]
    lead = inner[:len(inner) - len(inner.lstrip())]
    trail = inner[len(inner.rstrip()):]
    return text[:a] + lead + value + trail + text[b:]


def find_poms(root):
    out = []
    for dp, dn, fn in os.walk(root):
        dn[:] = sorted(d for d in dn if d not in SKIP_DIRS and not d.startswith("."))
        if "pom.xml" in fn:
            out.append(os.path.relpath(os.path.join(dp, "pom.xml"), root).replace(os.sep, "/"))
    return out


def _read(path):
    with open(path, encoding="utf-8", newline="") as fh:
        return fh.read()


def _write(path, text):
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)


def set_poms(root, version):
    """Set the project version in every pom.xml of the repository that shares the root pom's
    version. Returns ([changed files], [notes])."""
    poms = find_poms(root)
    if "pom.xml" not in poms:
        return [], []
    infos = {}
    for p in poms:
        try:
            infos[p] = pom_info(_read(os.path.join(root, p)))
        except (OSError, UnicodeDecodeError) as e:
            return [], [f"{p}: cannot read it ({e})"]
    rootv = infos["pom.xml"]["version"] or infos["pom.xml"]["pversion"]
    ours = {(i["group"], i["artifact"]) for i in infos.values() if i["artifact"]}
    changed, notes = [], []
    for p, info in infos.items():
        path = os.path.join(root, p)
        text = _read(path)
        new = text
        v = info["version"]
        if v and v.startswith("${"):
            if p == "pom.xml" and v == "${revision}" and info["revision"] is not None:
                if info["revision"] != version:
                    new = _replace(new, scan(new)["project/properties/revision"], version)
            elif p == "pom.xml":
                notes.append(f"{p}: <version>{v}</version> is a property; set it yourself")
        elif v is not None and (p == "pom.xml" or v == rootv) and v != version:
            new = _replace(new, scan(new)["project/version"], version)
        pv = info["pversion"]
        if pv and not pv.startswith("${") and (info["pgroup"], info["partifact"]) in ours and pv != version:
            new = _replace(new, scan(new)["project/parent/version"], version)
        if new != text:
            _write(path, new)
            changed.append(p)
    return changed, notes


def _json_version_span(text):
    """(start, end) of the string value of the top-level "version" key of a JSON object."""
    depth, i, n = 0, 0, len(text)
    key_rx = re.compile(r'"version"\s*:\s*"((?:[^"\\]|\\.)*)"')
    while i < n:
        c = text[i]
        if c == '"':
            if depth == 1:
                m = key_rx.match(text, i)
                if m:
                    return m.start(1), m.end(1)
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            i = j + 1
            continue
        if c in "{[":
            depth += 1
        elif c in "}]":
            depth -= 1
        i += 1
    return None


def set_package_json(root, version):
    path = os.path.join(root, "package.json")
    if not os.path.isfile(path):
        return []
    text = _read(path)
    sp = _json_version_span(text)
    if not sp or text[sp[0]:sp[1]] == version:
        return []
    _write(path, text[:sp[0]] + version + text[sp[1]:])
    return ["package.json"]


def set_versions(root, version, version_file="VERSION", pom=True):
    """Write the version everywhere it is declared. Returns ([changed files], [notes])."""
    changed, notes = [], []
    if version_file:
        path = os.path.join(root, version_file)
        old = _read(path) if os.path.isfile(path) else None
        if old != version + "\n":
            os.makedirs(os.path.dirname(path) or root, exist_ok=True)
            _write(path, version + "\n")
            changed.append(version_file)
    if pom:
        c, n = set_poms(root, version)
        changed += c
        notes += n
    changed += set_package_json(root, version)
    return changed, notes


def read_versions(root, version_file="VERSION"):
    out = {}
    p = os.path.join(root, version_file) if version_file else None
    if p and os.path.isfile(p):
        out[version_file] = _read(p).strip()
    if os.path.isfile(os.path.join(root, "pom.xml")):
        info = pom_info(_read(os.path.join(root, "pom.xml")))
        v = info["version"] or info["pversion"]
        if v == "${revision}" and info["revision"]:
            v = info["revision"]
        out["pom.xml"] = v
    if os.path.isfile(os.path.join(root, "package.json")):
        try:
            out["package.json"] = json.loads(_read(os.path.join(root, "package.json"))).get("version")
        except (ValueError, AttributeError):
            pass
    return out


def align(winner_text, texts, kind="pom"):
    """The texts with their version set to the winner's (pom: project and parent version;
    package.json: top-level "version"). For a 3-way merge where only the version differs."""
    out = []
    if kind == "json":
        sp = _json_version_span(winner_text)
        want = winner_text[sp[0]:sp[1]] if sp else None
        for t in texts:
            s2 = _json_version_span(t) if want is not None else None
            out.append(t[:s2[0]] + want + t[s2[1]:] if s2 else t)
        return out
    w = pom_info(winner_text)
    for t in texts:
        info = pom_info(t)
        new = t
        if w["version"] is not None and info["version"] is not None and info["version"] != w["version"]:
            new = _replace(new, scan(new)["project/version"], w["version"])
        if w["pversion"] is not None and info["pversion"] is not None and info["pversion"] != w["pversion"] \
                and (info["pgroup"], info["partifact"]) == (w["pgroup"], w["partifact"]):
            new = _replace(new, scan(new)["project/parent/version"], w["pversion"])
        out.append(new)
    return out
