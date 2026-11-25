"""Authoring helpers for the tool/language catalog.

The catalog is plain data; these helpers only keep it short. tools/gen.py imports
every family module, validates cross references and writes registry/registry.json.

Tool fields (consumed by engine/runner.py):
  role      syntax | marker | format | lint | deep   (one formatter per file type)
  cmd       {"fix": [...], "check": [...] | "diff" | {"pipe": [cmd, ...]}, "stdout": [...],
            "builtin": name}  (pipe: a format check feeding the real file on stdin)
            tokens: {files} {file} {args} {config} {config_dir} {root} {repo} {tmp} {group}
                    ({root} is the temp copy in a format check, {repo} always the repository)
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
from typing import Any

TOOLS: dict[str, dict[str, Any]] = {}
LANGS: list[dict[str, Any]] = []
RUNTIMES: dict[str, dict[str, Any]] = {}
GLOBAL_TOOLS: list[Any] = []

# why noqa PLR0913/PLR0917 below: these helpers are the authoring API of every family file;
# their keyword-rich signatures are the catalog's schema, a parameter object would hide it

# dpkg arch -> vendor arch spellings
A_GO = {"amd64": "amd64", "arm64": "arm64"}
A_X86 = {"amd64": "x86_64", "arm64": "aarch64"}
A_X86ARM = {"amd64": "x86_64", "arm64": "arm64"}
A_X64 = {"amd64": "x64", "arm64": "arm64"}
A_AMDONLY = {"amd64": "amd64"}

# ------------------------------------------------------------------ install channels


def apt(*pkgs):
    """Build an apt install channel.

    Args:
        *pkgs: Debian package names to install with apt-get.

    Returns:
        dict: The channel entry ``{"apt": [...]}``.

    Raises:
        None.
    """
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


def gh(repo, tag, asset, bins, arch=A_X86, verified=True, sha256=None):  # noqa: PLR0913, PLR0917
    """GitHub release asset. asset may use {tag} {ver} (tag without 'v') {arch}."""
    d = {"github": {"repo": repo, "tag": tag, "asset": asset, "bins": list(bins), "arch": arch}}
    if not verified:
        d["github"]["verified"] = False
    if sha256:
        d["github"]["sha256"] = sha256
    return d


def url(u, bins, arch=A_X86, dest=None, strip=0, verified=True):  # noqa: PLR0913, PLR0917
    """Build a plain URL download channel (archive or single file).

    Args:
        u: Download URL; may contain the arch placeholders of the install step.
        bins: Executables that the download provides.
        arch: Mapping from dpkg arch to the vendor spelling used in the URL.
        dest: Optional target directory of the extraction.
        strip: Number of leading path components to strip when extracting.
        verified: False when the download has no checksum or signature to check.

    Returns:
        dict: The channel entry ``{"url": {...}}``.

    Raises:
        None.
    """
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
    """Build a PHP phar install channel.

    Args:
        u: URL of the phar archive.
        bin_name: Name of the executable linked into /opt/qs/bin.

    Returns:
        dict: The channel entry ``{"phar": {...}}``.

    Raises:
        None.
    """
    return {"phar": {"url": u, "bin": bin_name}}


def script(code):
    """Shell (bash) run as root during the image build, network allowed. Must be idempotent."""
    return {"script": code}


# ------------------------------------------------------------------ definitions


def runtime(rid, name, install, path=(), env=None):
    """Register a language runtime (node, java, go, ...) in RUNTIMES.

    Args:
        rid: Runtime id, used as the key in RUNTIMES and in tool ``needs``.
        name: Human-readable runtime name.
        install: List of install channels, as built by the channel helpers.
        path: Directories to prepend to PATH when the runtime is used.
        env: Environment variables to export when the runtime is used.

    Returns:
        str: The runtime id ``rid``.

    Raises:
        None.
    """
    RUNTIMES[rid] = {
        "id": rid,
        "name": name,
        "install": install,
        "path": list(path),
        "env": env or {},
    }
    return rid


def tool(  # noqa: PLR0913
    tid,
    role,
    name,
    cmd,
    *,
    bin=None,
    install=(),
    needs=(),
    config=None,
    defaults=None,
    homepage="",
    license="",
    **kw,
):
    """Register a tool in TOOLS.

    Args:
        tid: Unique tool id.
        role: One of syntax, marker, format, lint or deep.
        name: Human-readable tool name.
        cmd: Command spec consumed by engine/runner.py.
        bin: Executable name, or list of names, that must exist.
        install: Install channels, as built by the channel helpers.
        needs: Runtime ids installed before the tool.
        config: Native config generated per run, or None.
        defaults: Base rules copied into .quality-rules.json.
        homepage: Project URL.
        license: SPDX license id of the tool.
        **kw: Extra tool fields stored as given (e.g. rule_args, version_rules).

    Returns:
        str: The tool id ``tid``.

    Raises:
        AssertionError: If a tool with the same id is already registered.
    """
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


def lang(  # noqa: PLR0913
    lid,
    name,
    *,
    kind="programming",
    ext=(),
    names=(),
    globs=(),
    shebang=(),
    modeline=(),
    magic=(),
    probe=(),
    default_for_ambiguous=False,
    tools=(),
    basic=None,
    marker=None,
    version=None,
    subtypes=(),
    notes="",
    candidates=(),
    tool_defaults=None,
):
    """Register a language in LANGS.

    Args:
        lid: Unique language id.
        name: Human-readable language name.
        kind: Language kind, "programming" by default.
        ext: File extensions that select the language.
        names: Exact file names that select the language.
        globs: Glob patterns that select the language.
        shebang: Interpreter names found in a shebang line.
        modeline: Editor modeline patterns.
        magic: Magic byte patterns of the file content.
        probe: Content probes, as built by probe().
        default_for_ambiguous: True to pick this language when a match is ambiguous.
        tools: Tool ids that check files of this language.
        basic: Built-in lexer preset, as built by lex(), or None.
        marker: Marker definition, or None.
        version: Version knob, as built by version(), or None.
        subtypes: Subtypes, as built by subtype().
        notes: Free-text notes shown in the docs.
        candidates: Candidate tools offered to the user.
        tool_defaults: Per-tool default rules.

    Returns:
        str: The language id ``lid``.

    Raises:
        AssertionError: If a language with the same id is already registered.
    """
    assert all(x["id"] != lid for x in LANGS), f"duplicate language {lid}"
    m = {}
    for k, v in (
        ("ext", ext),
        ("names", names),
        ("globs", globs),
        ("shebang", shebang),
        ("modeline", modeline),
        ("magic", magic),
        ("probe", probe),
    ):
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


def subtype(  # noqa: PLR0913
    sid, name, *, globs=(), content=(), names=(), tools=(), exclude_roles=(), exclude_tools=()
):
    """Build a language subtype (a narrower match inside a language).

    Args:
        sid: Subtype id.
        name: Human-readable subtype name.
        globs: Glob patterns that select the subtype.
        content: Content patterns that select the subtype.
        names: Exact file names that select the subtype.
        tools: Tool ids that apply to the subtype.
        exclude_roles: Tool roles removed for the subtype.
        exclude_tools: Tool ids removed for the subtype.

    Returns:
        dict: The subtype entry.

    Raises:
        None.
    """
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


def version(default, *, env=None, detect=(), label=None, ask=True, choices=None):  # noqa: PLR0913
    """Language version knob.

    detect: [{file, re, map}] (first match wins; file may be a root glob).
    """
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
    """Build one version detection rule (file, regex, optional value map).

    Args:
        file: File to read, or a root glob.
        regex: Regular expression whose first group gives the version.
        mapping: Optional dict that maps the captured text to a version value.

    Returns:
        dict: The detection rule ``{"file": ..., "re": ...}``.

    Raises:
        None.
    """
    d = {"file": file, "re": regex}
    if mapping:
        d["map"] = mapping
    return d


def shebang_marker(line, always=False):
    """Build a marker that matches a shebang line.

    Args:
        line: Shebang line text to match.
        always: True to apply the marker even when the file has no shebang.

    Returns:
        dict: The marker entry ``{"shebang": ...}``.

    Raises:
        None.
    """
    d = {"shebang": line}
    if always:
        d["always"] = True
    return d


def probe(regex, weight=1):
    """Build a content probe used to detect a language from file content.

    Args:
        regex: Regular expression searched in the file content.
        weight: Score added when the regex matches.

    Returns:
        dict: The probe entry ``{"re": ..., "weight": ...}``.

    Raises:
        None.
    """
    return {"re": regex, "weight": weight}


# ------------------------------------------------------------------ lexer presets (built-in checks)


def lex(  # noqa: PLR0913, PLR0917
    line=(),
    block=(),
    strings=('"', "'"),
    raw=(),
    escape="\\",
    nested=False,
    brackets="()[]{}",
    **kw,
):
    """Build a lexer preset describing comments and strings of a language.

    Args:
        line: Line comment openers, e.g. ``["//"]``.
        block: Pairs ``(open, close)`` of block comment delimiters.
        strings: Quote characters that open a string.
        raw: Pairs ``(open, close)`` of raw string delimiters.
        escape: Escape character inside strings ("" when none).
        nested: True when block comments nest.
        brackets: Bracket characters that the lexer tracks.
        **kw: Extra lexer fields stored as given (e.g. char_prefix).

    Returns:
        dict: The lexer preset.

    Raises:
        None.
    """
    d = {
        "line_comment": list(line),
        "block_comment": [list(b) for b in block],
        "strings": list(strings),
        "raw_strings": [list(r) for r in raw],
        "escape": escape,
        "brackets": brackets,
    }
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
    """Register a format-role tool (fix command plus check command).

    Args:
        tid: Unique tool id.
        name: Human-readable tool name.
        fix: Command that formats files in place.
        check: Command that checks formatting, "diff" by default.
        **kw: Extra arguments passed to tool().

    Returns:
        str: The tool id ``tid``.

    Raises:
        AssertionError: If a tool with the same id is already registered.
    """
    return tool(tid, "format", name, {"fix": fix, "check": check}, **kw)


def lint_tool(tid, name, check, fix=None, **kw):
    """Register a lint-role tool (check command, optional fix command).

    Args:
        tid: Unique tool id.
        name: Human-readable tool name.
        check: Command that lints files.
        fix: Optional command that fixes the reported findings.
        **kw: Extra arguments passed to tool().

    Returns:
        str: The tool id ``tid``.

    Raises:
        AssertionError: If a tool with the same id is already registered.
    """
    cmd = {"check": check}
    if fix:
        cmd["fix"] = fix
    return tool(tid, "lint", name, cmd, **kw)


def syntax_tool(tid, name, check, **kw):
    """Register a syntax-role tool (check command only).

    Args:
        tid: Unique tool id.
        name: Human-readable tool name.
        check: Command that verifies the syntax of files.
        **kw: Extra arguments passed to tool().

    Returns:
        str: The tool id ``tid``.

    Raises:
        AssertionError: If a tool with the same id is already registered.
    """
    return tool(tid, "syntax", name, {"check": check}, **kw)


def extend(  # noqa: PLR0913
    lid, tools=(), *, replace=None, subtypes=(), notes=None, candidates=None, tool_defaults=None
):
    """Add tools (and subtypes) to a language defined in another family file.

    replace: {old_tool_id: new_tool_id or None} swaps or drops an existing tool.
    """
    lang = next(x for x in LANGS if x["id"] == lid)
    for old, new in (replace or {}).items():
        lang["tools"] = [
            new if t == old else t for t in lang["tools"] if not (t == old and new is None)
        ]
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
    """Register a deep-role tool (slow whole-project check, check command only).

    Args:
        tid: Unique tool id.
        name: Human-readable tool name.
        check: Command that runs the deep check.
        **kw: Extra arguments passed to tool().

    Returns:
        str: The tool id ``tid``.

    Raises:
        AssertionError: If a tool with the same id is already registered.
    """
    return tool(tid, "deep", name, {"check": check}, **kw)
