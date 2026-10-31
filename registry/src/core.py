"""Authoring helpers for the tool/language catalog.

The catalog is plain data; these helpers only keep it short. tools/gen.py imports
every family module, validates cross references and writes registry/registry.json.

Tool fields (consumed by engine/runner.py):
  role      syntax | marker | format | lint | deep   (one formatter per file type)
  cmd       {"fix": [...], "check": [...] | "diff", "stdout": [...], "builtin": name}
            tokens: {files} {file} {args} {config} {config_dir} {root} {tmp} {group}
                    {found_dir} {v} {v_nodot} {v_major} {v_minor} {var:NAME}
            a nested list is an optional group, dropped if a placeholder is empty
            {"all": [cmd, cmd]} runs commands in order
  bin       executables that must exist (availability check)
  config    {"file", "format", "base", "inherit"} native config generated per run
  defaults  base rules copied into .quality-rules.json when the language appears
  rule_args render rules as CLI flags (tools without a config file)
  version_rules  {"dotted.key": template} injected into rules unless the user set it
  install   list of channels: apt / pip / npm / github / url / script
  needs     runtimes installed first (node, java, go, rust, dotnet, ...)
"""
import copy

TOOLS = {}
LANGS = []
RUNTIMES = {}
GLOBAL_TOOLS = []

# dpkg arch -> vendor arch spellings
A_GO = {"amd64": "amd64", "arm64": "arm64"}
A_X86 = {"amd64": "x86_64", "arm64": "aarch64"}
A_X86ARM = {"amd64": "x86_64", "arm64": "arm64"}
A_X64 = {"amd64": "x64", "arm64": "arm64"}
A_AMDONLY = {"amd64": "amd64"}

# ------------------------------------------------------------------ install channels

def apt(*pkgs):
    return {"apt": list(pkgs)}


def pip(spec, *bins, extra=(), python=None):
    """Isolated venv per tool (pipx-like): /opt/qs/venv/<tool>; bins linked into /opt/qs/bin."""
    d = {"pip": {"pkg": spec, "bins": list(bins)}}
    if extra:
        d["pip"]["extra"] = list(extra)
    if python:
        d["pip"]["python"] = python
    return d


def npm(*specs):
    """Shared Node prefix /opt/npm (one node_modules so configs and plugins resolve together)."""
    return {"npm": list(specs)}


def gh(repo, tag, asset, bins, arch=A_X86, verified=True, sha256=None):
    """GitHub release asset. asset may use {tag} {ver} (tag without 'v') {arch}."""
    d = {"github": {"repo": repo, "tag": tag, "asset": asset, "bins": list(bins), "arch": arch}}
    if not verified:
        d["github"]["verified"] = False
    if sha256:
        d["github"]["sha256"] = sha256
    return d


def url(u, bins, arch=A_X86, dest=None, strip=0, verified=True):
    d = {"url": {"url": u, "bins": list(bins), "arch": arch, "strip": strip}}
    if dest:
        d["url"]["dest"] = dest
    if not verified:
        d["url"]["verified"] = False
    return d


def jar(u, bin_name, java_opts=(), main=None):
    """A Java jar plus a wrapper script /opt/qs/bin/<bin_name>."""
    d = {"jar": {"url": u, "bin": bin_name, "java_opts": list(java_opts)}}
    if main:
        d["jar"]["main"] = main
    return d


def phar(u, bin_name):
    return {"phar": {"url": u, "bin": bin_name}}


def script(code):
    """Shell (bash) run as root during the image build, network allowed. Must be idempotent."""
    return {"script": code}


# ------------------------------------------------------------------ definitions

def runtime(rid, name, install, path=(), env=None):
    RUNTIMES[rid] = {"id": rid, "name": name, "install": install, "path": list(path), "env": env or {}}
    return rid


def tool(tid, role, name, cmd, *, bin=None, install=(), needs=(), config=None, defaults=None,
         homepage="", license="", **kw):
    assert tid not in TOOLS, f"duplicate tool {tid}"
    t = {"id": tid, "role": role, "name": name, "cmd": cmd}
    if bin is not None:
        t["bin"] = [bin] if isinstance(bin, str) else list(bin)
    if install:
        t["install"] = list(install)
    if needs:
        t["needs"] = list(needs)
    if config:
        t["config"] = config
    t["defaults"] = copy.deepcopy(defaults or {})
    if homepage:
        t["homepage"] = homepage
    if license:
        t["license"] = license
    t.update(kw)
    TOOLS[tid] = t
    return tid


def lang(lid, name, *, kind="programming", ext=(), names=(), globs=(), shebang=(), modeline=(), magic=(),
         probe=(), default_for_ambiguous=False, tools=(), basic=None, marker=None, version=None,
         subtypes=(), notes="", candidates=(), tool_defaults=None):
    assert all(l["id"] != lid for l in LANGS), f"duplicate language {lid}"
    m = {}
    for k, v in (("ext", ext), ("names", names), ("globs", globs), ("shebang", shebang),
                 ("modeline", modeline), ("magic", magic), ("probe", probe)):
        if v:
            m[k] = list(v)
    if default_for_ambiguous:
        m["default_for_ambiguous"] = True
    d = {"id": lid, "name": name, "kind": kind, "match": m, "tools": list(tools)}
    if basic is not None:
        d["basic"] = basic
    if marker:
        d["marker"] = marker
    if version:
        d["version"] = version
    if subtypes:
        d["subtypes"] = list(subtypes)
    if notes:
        d["notes"] = notes
    if candidates:
        d["candidates"] = list(candidates)
    if tool_defaults:
        d["tool_defaults"] = tool_defaults
    LANGS.append(d)
    return lid


def subtype(sid, name, *, globs=(), content=(), names=(), tools=(), exclude_roles=(), exclude_tools=()):
    m = {}
    if globs:
        m["globs"] = list(globs)
    if content:
        m["content"] = list(content)
    if names:
        m["names"] = list(names)
    d = {"id": sid, "name": name, "match": m, "tools": list(tools)}
    if exclude_roles:
        d["exclude_roles"] = list(exclude_roles)
    if exclude_tools:
        d["exclude_tools"] = list(exclude_tools)
    return d


def version(default, *, env=None, detect=(), label=None, ask=True, choices=None):
    """Language version knob. detect: [{file, re, map}] (first match wins; file may be a root glob)."""
    d = {"default": default, "detect": list(detect)}
    if env:
        d["env"] = env
    if label:
        d["label"] = label
    if not ask:
        d["ask"] = False
    if choices:
        d["choices"] = list(choices)
    return d


def det(file, regex, mapping=None):
    d = {"file": file, "re": regex}
    if mapping:
        d["map"] = mapping
    return d


def shebang_marker(line, always=False):
    d = {"shebang": line}
    if always:
        d["always"] = True
    return d


def probe(regex, weight=1):
    return {"re": regex, "weight": weight}


# ------------------------------------------------------------------ lexer presets (built-in checks)

def lex(line=(), block=(), strings=('"', "'"), raw=(), escape="\\", nested=False, brackets="()[]{}", **kw):
    d = {"line_comment": list(line), "block_comment": [list(b) for b in block], "strings": list(strings),
         "raw_strings": [list(r) for r in raw], "escape": escape, "brackets": brackets}
    if nested:
        d["nested_block"] = True
    d.update(kw)
    return d


C_LIKE = lex(["//"], [("/*", "*/")])
HASH = lex(["#"])
SQL_LIKE = lex(["--"], [("/*", "*/")], strings=("'", '"'), escape="")
LISP = lex([";"], [("#|", "|#")], strings=('"',), char_prefix="#\\", nested=True)
ML = lex([], [("(*", "*)")], strings=('"',), nested=True)
PLAIN = lex([], [], strings=(), brackets="")
WS_SIGNIFICANT = dict(PLAIN, ws_significant=True)


def fmt_tool(tid, name, fix, check="diff", **kw):
    return tool(tid, "format", name, {"fix": fix, "check": check}, **kw)


def lint_tool(tid, name, check, fix=None, **kw):
    cmd = {"check": check}
    if fix:
        cmd["fix"] = fix
    return tool(tid, "lint", name, cmd, **kw)


def syntax_tool(tid, name, check, **kw):
    return tool(tid, "syntax", name, {"check": check}, **kw)


def extend(lid, tools=(), *, replace=None, subtypes=(), notes=None, candidates=None, tool_defaults=None):
    """Add tools (and subtypes) to a language defined in another family file.

    replace: {old_tool_id: new_tool_id or None} swaps or drops an existing tool.
    """
    lang = next(l for l in LANGS if l["id"] == lid)
    for old, new in (replace or {}).items():
        lang["tools"] = [new if t == old else t for t in lang["tools"] if not (t == old and new is None)]
    lang["tools"] += [t for t in tools if t not in lang["tools"]]
    if subtypes:
        lang.setdefault("subtypes", []).extend(subtypes)
    if notes is not None:
        lang["notes"] = notes
    if candidates is not None:
        if candidates:
            lang["candidates"] = list(candidates)
        else:
            lang.pop("candidates", None)
    if tool_defaults:
        lang.setdefault("tool_defaults", {}).update(tool_defaults)
    return lid


def deep_tool(tid, name, check, **kw):
    return tool(tid, "deep", name, {"check": check}, **kw)
