"""Pipeline execution: per-language steps run in order, languages run in parallel.

Step order per language: syntax -> marker -> format -> lint -> deep. A file that
fails the syntax step is dropped from the later steps (its errors would be noise).
"""

import copy
import fnmatch
import os
import re
import shutil
import subprocess
import tempfile

import builtin
import generated
import qslog
import versions

from registry import ROLE_LEVEL, level_rank

# why: generated files (git attribute qs-generated) are rewritten by their generator, so
# marking, formatting and linting them would only make the output unstable; secrets still count.
GENERATED_SKIP_ROLES = ("marker", "format", "lint", "deep")
SECRET_SCANNERS = ("gitleaks", "qs-private-key")

ROLE_ORDER = {"syntax": 0, "marker": 1, "format": 2, "lint": 3, "deep": 4}


class Ctx:
    # why: shared engine call contract; a parameter object would change every caller
    def __init__(self, root, mode, tmp, cfg_paths, exec_files, ambiguous=None):  # noqa: PLR0913, PLR0917
        """Hold the state of one run.

        Args:
            root: the repository root.
            mode: fix or check.
            tmp: the temporary folder.
            cfg_paths: (lang_id, tool_id) -> generated config path.
            exec_files: repo-relative executable paths.
            ambiguous: files whose extension was ambiguous.
        """
        self.root, self.mode, self.tmp = root, mode, tmp
        self.cfg_paths = cfg_paths  # (lang_id, tool_id) -> generated config path
        self.exec_files = exec_files  # set of repo-relative executable paths
        self.ambiguous = (
            ambiguous or set()
        )  # files whose extension was ambiguous (confidently resolved)
        self.protect = {}  # file -> non-UTF-8 charset: formatters/markers never touch it
        self.charsets = {}  # lang -> charset name for {charset} (e.g. PMD --encoding)
        # why: a format check runs on copies in a temp root; {repo} stays the real repository
        self.repo = root


class StepResult:
    def __init__(self, tool_id, role):
        """Start an empty result.

        Args:
            tool_id: the tool id.
            role: the tool role.
        """
        self.tool_id, self.role = tool_id, role
        self.status = {}  # file -> SUCCESS|ERROR|SKIP
        self.output = []
        self.note = ""


def _bins(tool):
    """Executables a tool needs.

    Args:
        tool: the registry tool.

    Returns:
        list: binary names.
    """
    bins = tool.get("bin") or []
    return [bins] if isinstance(bins, str) else bins


def available(tool):
    """Whether a tool can run here.

    Args:
        tool: the registry tool.

    Returns:
        bool: True for built-ins or when every binary is on PATH.
    """
    if "builtin" in tool.get("cmd", {}):
        return True
    return all(shutil.which(b) for b in _bins(tool))


def _vars(tool, version, extra):
    """Version-derived variables of a tool.

    Args:
        tool: the registry tool.
        version: the language version.
        extra: more variables to add.

    Returns:
        dict: variable name -> text.
    """
    v = {"version": str(version or "")}
    for name, spec in (tool.get("version_vars") or {}).items():
        val = spec.get("default", "")
        for prefix in sorted(spec.get("map", {}), key=len, reverse=True):
            if str(version or "").startswith(prefix):
                val = spec["map"][prefix]
                break
        v[name] = versions.fmt(str(val), version)
    v.update(extra or {})
    return v


SUITE = os.environ.get("QS_SUITE") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ENV_RE = re.compile(r"\{env:([A-Za-z_][A-Za-z0-9_]*)\}")
_RULE_RE = re.compile(r"\{rule:([A-Za-z0-9_.-]+)\}")


def _subst(t, ctx, tool, version, vv):
    """Replace the {placeholders} of a command token.

    Args:
        t: the token.
        ctx: the run context.
        tool: the registry tool.
        version: the language version.
        vv: the variables from _vars.

    Returns:
        str: the expanded token.
    """
    cfg = ctx.cfg_paths.get((tool.get("_lang"), tool["id"]), "")
    s = t.replace("{root}", ctx.root).replace("{tmp}", ctx.tmp).replace("{suite}", SUITE)
    s = s.replace("{repo}", getattr(ctx, "repo", ctx.root))
    s = s.replace("{npm}", os.environ.get("QS_NPM", "/opt/npm"))
    s = s.replace("{charset}", ctx.charsets.get(tool.get("_lang"), "UTF-8"))
    s = _ENV_RE.sub(lambda m: os.environ.get(m.group(1), ""), s)
    rules = tool.get("_rules") or {}
    s = _RULE_RE.sub(
        lambda m: "" if rules.get(m.group(1)) in (None, False) else str(rules.get(m.group(1))), s
    )
    s = s.replace("{config_dir}", os.path.dirname(cfg) if cfg else "").replace("{config}", cfg)
    s = versions.fmt(s, version) if version is not None else versions.fmt(s, "")
    for k, val in vv.items():
        s = s.replace("{var:" + k + "}", str(val))
    for k in ("found", "found_dir", "group"):
        if k in vv:
            s = s.replace("{" + k + "}", str(vv[k]))
    return s


# why: shared engine call contract; a parameter object would change every caller
def expand(tokens, ctx, tool, files, args, version, extra=None):  # noqa: PLR0913, PLR0917
    """Expand a command template. A nested list is an optional group: it is dropped
    when any of its placeholders resolves empty (e.g. ["--config", "{config}"])."""
    out = []
    vv = _vars(tool, version, extra)
    for t in tokens:
        if isinstance(t, list):
            grp = [_subst(x, ctx, tool, version, vv) for x in t]
            if all(grp):
                out += grp
        elif t == "{files}":
            out += files
        elif t == "{files_csv}":
            out.append(",".join(files))
        elif t.startswith("{files:") and t.endswith("}"):
            out += [t[7:-1] + f for f in files]
        elif t == "{dirs}":
            seen = []
            for f in files:
                d = os.path.dirname(f) or "."
                d = d if os.path.isabs(d) or d.startswith(".") else "./" + d
                if d not in seen:
                    seen.append(d)
            out += [d + "/" if not d.endswith("/") else d for d in seen]
        elif t == "{args}":
            out += args
        elif t == "{file}":
            out.append(files[0])
        else:
            out.append(_subst(t, ctx, tool, version, vv))
    return out


def set_path(data, dotted, value):
    """Set a dotted key when it is not already set.

    Args:
        data: the dict (edited in place).
        dotted: the key path, e.g. a.b.c.
        value: the value to set.
    """
    cur = data
    keys = dotted.split(".")
    for k in keys[:-1]:
        cur = cur.setdefault(k, {})
        if not isinstance(cur, dict):
            return
    cur.setdefault(keys[-1], value)


def effective_rules(tool, rules, version):
    """Rules from the rules file plus version-derived values the user did not set."""
    out = copy.deepcopy(rules or {})
    if version:
        vv = _vars(tool, version, {})
        for raw_path, tmpl in (tool.get("version_rules") or {}).items():
            path = versions.fmt(raw_path, version)
            if not isinstance(tmpl, str):
                set_path(out, path, tmpl)
                continue
            val = versions.fmt(tmpl, version)
            for k, x in vv.items():
                val = val.replace("{var:" + k + "}", str(x))
            if val.startswith("{int}"):
                val = int(re.sub(r"\D", "", val[5:]) or 0)
            elif val.startswith("{float}"):
                try:
                    val = float(val[7:])
                except ValueError:
                    continue
            set_path(out, path, val)
    return out


def rule_args(tool, rules):
    """Render rules as CLI arguments for tools configured only by flags (no config file)."""
    spec = tool.get("rule_args")
    if not spec:
        return []
    joiner = spec.get("joiner", " ") if isinstance(spec, dict) else " "
    prefix = spec.get("prefix", "--") if isinstance(spec, dict) else "--"
    aliases = spec.get("aliases", {}) if isinstance(spec, dict) else {}
    out = []
    for name, v in (rules or {}).items():
        if name.startswith("$"):
            continue
        k = aliases.get(
            name, name
        )  # why: a flag renamed upstream keeps working in existing rules files
        flag = k if k.startswith("-") else prefix + k
        for x in v if isinstance(v, list) else [v]:
            if x is True:
                out.append(flag)
            elif x is False or x is None:
                continue
            elif joiner in ("=", ""):
                out.append(f"{flag}{joiner}{x}")
            else:
                out += [flag, str(x)]
    return out


def _run(cmd, cwd, env, timeout, stdin=None):
    """Run a command with a timeout; stdin is empty unless given.

    Args:
        cmd: the argument list.
        cwd: the working folder.
        env: the environment.
        timeout: seconds.
        stdin: text to feed, or None for none.

    Returns:
        tuple: (return code, stdout, stderr); 127 when the program is missing, 124 on timeout.
    """
    try:
        # why: a tool that falls back to reading stdin must see EOF, never hang the commit
        p = subprocess.run(
            cmd,
            cwd=cwd,
            env=env,
            capture_output=True,
            text=True,
            timeout=timeout,
            errors="replace",
            check=False,
            **({"input": stdin} if stdin is not None else {"stdin": subprocess.DEVNULL}),
        )
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError as e:
        return 127, "", str(e)
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s"


def _env(tool, ctx):
    """Environment of a tool run.

    Args:
        tool: the registry tool.
        ctx: the run context.

    Returns:
        dict: the process environment with the tool's variables expanded.
    """
    env = dict(os.environ)
    for k, v in (tool.get("env") or {}).items():
        env[k] = (
            v.replace("{root}", ctx.root)
            .replace("{tmp}", ctx.tmp)
            .replace("{suite}", SUITE)
            .replace("{charset}", ctx.charsets.get(tool.get("_lang"), "UTF-8"))
        )
    rules = tool.get("_rules") or {}
    for k, spec in (tool.get("env_from_rules") or {}).items():
        val = rules.get(spec["rule"])
        if val is not None:
            env[k] = spec["repeat"] * int(val) if "repeat" in spec else str(val)
    return env


def _has_marker(d, marker):
    """Whether a folder holds a marker file.

    Args:
        d: the folder.
        marker: a file name or glob.

    Returns:
        bool: True when found.
    """
    if any(c in marker for c in "*?["):
        try:
            return any(fnmatch.fnmatch(n, marker) for n in os.listdir(d))
        except OSError:
            return False
    return os.path.exists(os.path.join(d, marker))


def _group(files, root, markers):
    """Group files by the nearest folder holding a marker.

    Args:
        files: repo-relative files.
        root: the repository root.
        markers: a marker or a list of them.

    Returns:
        dict: folder (None when no marker is found) -> files.
    """
    markers = [markers] if isinstance(markers, str) else markers
    groups = {}
    for f in files:
        d = os.path.dirname(os.path.join(root, f))
        found = None
        while d.startswith(root):
            if any(_has_marker(d, m) for m in markers):
                found = d
                break
            if d == root:
                break
            d = os.path.dirname(d)
        groups.setdefault(found, []).append(f)
    return groups


def _requires(tool, ctx):
    """Check the `requires` condition of a tool.

    Args:
        tool: the registry tool.
        ctx: the run context.

    Returns:
        dict: found and found_dir variables, {} when nothing is required, None
        when no required file exists.
    """
    req = tool.get("requires") or {}
    for cand in req.get("any_file", []):
        hits = (
            [cand]
            if not any(c in cand for c in "*?[")
            else [
                n
                for n in (os.listdir(ctx.root) if os.path.isdir(ctx.root) else [])
                if fnmatch.fnmatch(n, cand)
            ]
        )
        for h in hits:
            if os.path.exists(os.path.join(ctx.root, h)):
                p = os.path.join(ctx.root, h)
                return {"found": p, "found_dir": os.path.dirname(p)}
    return None if req.get("any_file") else {}


def _attribute(res, files, rc_ok, out):
    """Set each file's status from a tool outcome.

    Args:
        res: the StepResult.
        files: the files checked.
        rc_ok: True when the tool succeeded.
        out: the tool output (files named in it get the error).
    """
    if rc_ok:
        for f in files:
            res.status[f] = "SUCCESS"
        return
    named = [f for f in files if f in out or os.path.basename(f) in out]
    for f in files:
        res.status[f] = "ERROR" if (f in named or not named) else "SUCCESS"


# ---------------------------------------------------------------- builtins


# why: one dispatch branch per builtin check; a registry of handlers is a separate refactor
def run_builtin(tool, settings, lang, ctx, files, version):  # noqa: C901, PLR0912, PLR0913, PLR0917
    """Run a built-in check over the files.

    Args:
        tool: the registry tool.
        settings: the tool settings from the rules.
        lang: the registry language.
        ctx: the run context.
        files: repo-relative files.
        version: the language version.

    Returns:
        StepResult: statuses and findings.
    """
    res = StepResult(tool["id"], tool["role"])
    name = tool["cmd"]["builtin"]
    spec = dict((lang or {}).get("basic", {}))
    spec.update(settings.get("rules") or {})
    for f in files:
        p = os.path.join(ctx.root, f)
        if name == "basic_syntax":
            probs = builtin.basic_syntax(p, spec)
        elif name == "basic_format":
            ok = builtin.basic_format(p, spec, write=(ctx.mode == "fix"))
            probs = (
                []
                if ok or ctx.mode == "fix"
                else ["whitespace not normalized (trailing spaces / final newline)"]
            )
        elif name == "marker":
            probs = _marker(lang, settings, ctx, f, p)
        elif name == "python_ast":
            probs = builtin.python_ast(p, version)
        elif name in builtin.CHECKS:
            probs = builtin.CHECKS[name](p)
        elif name == "conflict_markers":
            text, _ = builtin.read_text(p)
            m = builtin.CONFLICT.search(text or "")
            probs = (
                [f"merge-conflict marker at line {text.count(chr(10), 0, m.start()) + 1}"]
                if m
                else []
            )
        elif name == "private_key":
            text, _ = builtin.read_text(p)
            probs = (
                ["looks like a private key"] if text and builtin.PRIVATE_KEY.search(text) else []
            )
        elif name == "mixed_line_endings":
            raw = builtin.slurp(p)
            crlf = raw.count(b"\r\n")
            probs = ["mixed CRLF/LF line endings"] if crlf and raw.count(b"\n") != crlf else []
        elif name == "repo_files":
            # why: loaded only for this builtin, keeps engine start-up light
            import repofiles  # noqa: PLC0415

            probs, warns = repofiles.check(
                ctx.root, f, getattr(ctx, "policy", None), os.environ.get("QS_BRANCH", "")
            )
            for w in warns:
                qslog.log("WARN", "repo-files", w, f, tool["id"], "WARN")
        elif name == "large_file":
            kb = int((settings.get("rules") or {}).get("max_kb", 512))
            big = os.path.getsize(p) > kb * 1024 and not generated.is_generated(ctx.root, f)
            probs = [f"file larger than {kb} KB (use Git LFS or exclude it)"] if big else []
        else:
            probs = [f"unknown builtin {name}"]
        res.status[f] = "ERROR" if probs else "SUCCESS"
        res.output += [f"{f}: {x}" for x in probs]
    return res


def _marker(lang, settings, ctx, rel, path):
    """Findings of the marker (shebang, header) check of a file.

    Args:
        lang: the registry language.
        settings: the tool settings.
        ctx: the run context.
        rel: the repo-relative path.
        path: the absolute path.

    Returns:
        list: findings; empty when ok or unreadable.
    """
    spec = dict((lang or {}).get("marker") or {})
    spec.update(settings.get("rules") or {})
    text, err = builtin.read_text(path)
    if text is None:
        return []
    first = text.split("\n", 1)[0]
    base = os.path.basename(rel)
    want = None
    shebang_due = spec.get("shebang") and (
        spec.get("always") or rel in ctx.exec_files or "." not in base
    )
    if shebang_due and not first.startswith("#!"):
        want = ("shebang", spec["shebang"])
    elif spec.get("modeline") and rel in ctx.ambiguous:
        head = "\n".join(text.split("\n", 4)[:4])
        if not re.search(r"-\*-|\bvim?:", head):
            want = ("modeline", spec["modeline"])
    if not want:
        return []
    if ctx.mode != "fix":
        return [f"missing {want[0]} '{want[1]}' (identifying mark); a commit adds it automatically"]
    if text.startswith("﻿"):
        return [f"has a BOM; add the {want[0]} '{want[1]}' manually"]
    eol = "\r\n" if first.endswith("\r") else "\n"
    lines = text.split("\n")
    if want[0] == "shebang":
        lines.insert(0, want[1] + ("\r" if eol == "\r\n" else ""))
    else:
        # why: some files need a fixed first line (shebang, <?xml ?>, <?php); modeline goes after
        after = spec.get("modeline_after", r"^(#!|<\?xml|<\?php)")
        pos = 1 if lines and re.match(after, lines[0]) else 0
        lines.insert(pos, want[1] + ("\r" if eol == "\r\n" else ""))
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write("\n".join(lines))
    qslog.log("INFO", "marker", f"added {want[0]} '{want[1]}'", rel, "fix", "SUCCESS")
    return []


# ---------------------------------------------------------------- external tools


def _cwd(tool, ctx, gdir, unit, work=None):
    """Working folder of a tool run.

    Args:
        tool: the registry tool.
        ctx: the run context.
        gdir: the group folder.
        unit: the files of the run.
        work: a temporary root replacing the repository root.

    Returns:
        str: the folder.
    """
    root = work or ctx.root
    where = tool.get("cwd", "root")
    if where == "group":
        return gdir if not work else os.path.join(work, os.path.relpath(gdir or ctx.root, ctx.root))
    if where == "file_dir":
        return os.path.join(root, os.path.dirname(unit[0]))
    if where == "tmp":
        return ctx.tmp
    if where == "npm":
        # why: Node tools resolve plugins and shared configs from the shared prefix.
        return os.environ.get("QS_NPM", "/opt/npm")
    if where == "config_dir":
        cfg = ctx.cfg_paths.get((tool.get("_lang"), tool["id"]))
        return os.path.dirname(cfg) if cfg else ctx.tmp
    return root


def _paths(tool, ctx, unit, work=None):
    """File arguments of a tool run.

    Args:
        tool: the registry tool.
        ctx: the run context.
        unit: the files of the run.
        work: a temporary root replacing the repository root.

    Returns:
        list: relative paths when the tool runs at the root, else absolute ones.
    """
    root = work or ctx.root
    return unit if tool.get("cwd", "root") == "root" else [os.path.join(root, f) for f in unit]


# why: shared engine call contract; a parameter object would change every caller
def _stdout_format(tool, settings, ctx, files, version, res, env, timeout, args, extra):  # noqa: PLR0913, PLR0917
    """Formatter that prints the formatted file on stdout (xmllint --format, latexindent -s ...)."""
    seq = tool["cmd"]["stdout"]
    ok_codes = tool.get("success", [0])
    for f in files:
        p = os.path.join(ctx.root, f)
        cmd = expand(seq, ctx, tool, [p], args, version, extra)
        stdin = builtin.slurp(p).decode("utf-8", "replace") if tool.get("stdin") else None
        rc, out, err = _run(cmd, _cwd(tool, ctx, ctx.root, [f]), env, timeout, stdin)
        if rc not in ok_codes or not out.strip():
            res.status[f] = "ERROR"
            res.output += [
                f"{f}: {line}" for line in (err or out or f"exit {rc}").splitlines() if line.strip()
            ][:40]
            continue
        cur = builtin.slurp(p).decode("utf-8", "replace")
        if "\r\n" in cur and "\r\n" not in out:
            out = out.replace("\n", "\r\n")  # why: keep the file's line endings
        if out == cur:
            res.status[f] = "SUCCESS"
        elif ctx.mode == "fix":
            with open(p, "w", encoding="utf-8", newline="") as fh:
                fh.write(out)
            res.status[f] = "SUCCESS"
        else:
            res.status[f] = "ERROR"
            res.output.append(f"{f}: not formatted (a commit formats it)")
    return res


# why: central step runner; splitting it is a separate refactor
def run_tool(tool, settings, lang, ctx, files, version, lid=None):  # noqa: C901, PLR0911, PLR0912, PLR0913, PLR0915, PLR0917
    """Run one registry tool over the files.

    Args:
        tool: the registry tool.
        settings: the tool settings from the rules.
        lang: the registry language.
        ctx: the run context.
        files: repo-relative files.
        version: the language version.
        lid: the language id.

    Returns:
        StepResult: statuses and findings.
    """
    tool = dict(tool, _lang=lid)
    if tool["role"] in GENERATED_SKIP_ROLES and tool["id"] not in SECRET_SCANNERS:
        files = [f for f in files if not generated.is_generated(ctx.root, f)]
        if not files:
            return StepResult(tool["id"], tool["role"])
    if "builtin" in tool.get("cmd", {}):
        return run_builtin(tool, settings, lang, ctx, files, version)
    res = StepResult(tool["id"], tool["role"])
    cmds = tool["cmd"]
    role = tool["role"]
    rules = effective_rules(tool, settings.get("rules"), version)
    tool["_rules"] = rules
    args = rule_args(tool, rules) + list(settings.get("args") or [])
    why = None
    if tool.get("skip_version") and version and re.search(tool["skip_version"], str(version)):
        why = f"not applicable to version {version}"
    elif tool.get("requires_rule") and not rules.get(tool["requires_rule"]):
        why = f"set rules.{tool['requires_rule']} to enable it"
    if why:
        res.note = "skipped: " + why
        for f in files:
            res.status[f] = "SKIP"
        return res
    extra = _requires(tool, ctx)
    if extra is None:
        res.note = "skipped: " + (
            tool.get("requires", {}).get("why") or "prerequisite file not found"
        )
        for f in files:
            res.status[f] = "SKIP"
        return res
    env = _env(tool, ctx)
    timeout = tool.get("timeout", 300)
    if "stdout" in cmds:
        return _stdout_format(tool, settings, ctx, files, version, res, env, timeout, args, extra)
    autofix = settings.get("autofix", tool.get("autofix", False))
    fixing = ctx.mode == "fix" and "fix" in cmds and (role in ("format", "marker") or autofix)
    ok_codes = (
        tool.get("success_fix", tool.get("success", [0])) if fixing else tool.get("success", [0])
    )
    groups = {None: files}
    if tool.get("group_by"):
        groups = _group(files, ctx.root, tool["group_by"])
        if None in groups and not tool.get("ungrouped_ok"):
            for f in groups.pop(None):
                res.status[f] = "SKIP"
            res.note = f"no {tool['group_by']} found for some files (skipped)"
    if role == "format" and ctx.mode != "fix" and cmds.get("check") == "diff":
        return _diff_check(tool, ctx, groups, version, res, env, timeout, args, extra)
    pipe = isinstance(cmds.get("check"), dict) and "pipe" in cmds["check"]
    if role == "format" and ctx.mode != "fix" and pipe:
        return _pipe_check(tool, ctx, groups, version, res, env, timeout, args, extra)
    seq = cmds.get("fix") if fixing else cmds.get("check")
    if not seq:
        for f in files:
            res.status.setdefault(f, "SKIP")
        return res
    seqs = _seqs(seq)
    batch = tool.get("batch", True)
    pats = (tool.get("offline_skip") or []) + (tool.get("skip_on") or [])
    for gdir, gfiles in groups.items():
        units = [gfiles] if batch else [[f] for f in gfiles]
        for unit in units:
            ok_all, out_all = True, ""
            gextra = dict(extra, group=gdir or ctx.root)
            for s in seqs:
                cmd = expand(s, ctx, tool, _paths(tool, ctx, unit), args, version, gextra)
                rc, out, err = _run(cmd, _cwd(tool, ctx, gdir or ctx.root, unit), env, timeout)
                out_all += out + err
                if (
                    rc not in ok_codes
                    or (tool.get("fail_on_output") and not fixing and out.strip())
                    or (tool.get("fail_regex") and re.search(tool["fail_regex"], out + err, re.M))
                ):
                    # why fail_regex: some linters (CFLint, bibtool, Royale) exit 0 and only print
                    ok_all = False
                    break
            if not ok_all and pats and any(re.search(p, out_all, re.I) for p in pats):
                for f in unit:
                    res.status[f] = "SKIP"
                res.note = (
                    "skipped: needs dependencies or network that are not available offline"
                    if any(re.search(p, out_all, re.I) for p in tool.get("offline_skip") or [])
                    else "skipped: "
                    + tool.get("skip_why", "the tool cannot analyse this file in isolation")
                )
                continue
            _attribute(res, unit, ok_all, out_all)
            res.output += [line for line in out_all.splitlines() if line.strip()]
    return res


def _seqs(seq):
    """A command is a token list; {"all": [cmd, cmd]} runs several in order."""
    return seq["all"] if isinstance(seq, dict) else [seq]


def _run_bytes(cmd, cwd, env, timeout, data):
    """Run a command that reads a file on stdin and prints the result on stdout, as bytes.

    Args:
        cmd: the expanded command.
        cwd: working directory.
        env: environment.
        timeout: seconds before the run is abandoned.
        data: bytes fed on stdin.

    Returns:
        tuple: (exit code, stdout bytes, stderr text); 127 when the tool is missing and
        124 on timeout. Bytes keep the line endings, which text mode would rewrite.
    """
    try:
        p = subprocess.run(
            cmd, cwd=cwd, env=env, capture_output=True, timeout=timeout, input=data, check=False
        )
        return p.returncode, p.stdout, p.stderr.decode("utf-8", "replace")
    except FileNotFoundError as e:
        return 127, b"", str(e)
    except subprocess.TimeoutExpired:
        return 124, b"", f"timeout after {timeout}s"


# why: shared engine call contract; a parameter object would change every caller
def _pipe_check(tool, ctx, groups, version, res, env, timeout, args, extra):  # noqa: PLR0913, PLR0917
    """Check mode that pipes each file through stdin filters run on the real repository.

    cmd.check = {"pipe": [cmd, ...]}: the file's bytes go to the first command, each
    output feeds the next, and the last output is compared with the file. The commands run
    with the fix mode's working directory and {file} is the real path, so tools that find
    their config or project layout from the path (ruff --stdin-filename) see the same
    repository as the fix, unlike a copy in a temp root.

    Args:
        tool, ctx, groups, version, env, timeout, args, extra: as in run_tool.
        res: the StepResult to fill.

    Returns:
        StepResult: res, with SUCCESS for formatted files and ERROR otherwise.
    """
    ok_codes = tool.get("success_fix", tool.get("success", [0]))
    for gdir, gfiles in groups.items():
        for f in gfiles:
            cur = builtin.slurp(os.path.join(ctx.root, f))
            data, failed = cur, False
            for s in tool["cmd"]["check"]["pipe"]:
                gextra = dict(extra, group=gdir or ctx.root)
                cmd = expand(s, ctx, tool, _paths(tool, ctx, [f]), args, version, gextra)
                cwd = _cwd(tool, ctx, gdir or ctx.root, [f])
                rc, data, err = _run_bytes(cmd, cwd, env, timeout, data)
                if rc not in ok_codes:
                    res.output += [f"{f}: {line}" for line in err.splitlines() if line.strip()]
                    res.output += [f"{f}: exit {rc}"] if not err.strip() else []
                    failed = True
                    break
            res.status[f] = "SUCCESS" if not failed and data == cur else "ERROR"
            if not failed and data != cur:
                res.output.append(f"{f}: not formatted (a commit formats it)")
    return res


# why: shared engine call contract; a parameter object would change every caller
def _diff_check(tool, ctx, groups, version, res, env, timeout, args, extra):  # noqa: C901, PLR0913, PLR0917
    """Check mode for formatters without a reliable --check: format a copy and compare."""
    work = tempfile.mkdtemp(dir=ctx.tmp, prefix=f"chk-{tool['id']}-")
    seqs = _seqs(tool["cmd"]["fix"])
    files = [f for g in groups.values() for f in g]
    for f in files:
        dst = os.path.join(work, f)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(ctx.root, f), dst)
    for marker in (
        [tool["group_by"]] if isinstance(tool.get("group_by"), str) else tool.get("group_by") or []
    ):
        for gdir in groups:
            if (
                gdir
                and not any(c in marker for c in "*?[")
                and os.path.exists(os.path.join(gdir, marker))
            ):
                dst = os.path.join(work, os.path.relpath(gdir, ctx.root), marker)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(os.path.join(gdir, marker), dst)
    sub = Ctx(work, "fix", ctx.tmp, ctx.cfg_paths, ctx.exec_files, ctx.ambiguous)
    sub.repo, sub.charsets = ctx.repo, ctx.charsets
    ok_codes = tool.get("success_fix", tool.get("success", [0]))
    for gdir, gfiles in groups.items():
        units = [gfiles] if tool.get("batch", True) else [[f] for f in gfiles]
        for unit in units:
            for s in seqs:
                cmd = expand(
                    s,
                    sub,
                    tool,
                    _paths(tool, sub, unit, work),
                    args,
                    version,
                    dict(extra, group=gdir),
                )
                rc, out, err = _run(cmd, _cwd(tool, ctx, gdir, unit, work), env, timeout)
                if rc not in ok_codes:
                    for f in unit:
                        res.status[f] = "ERROR"
                    res.output += [line for line in (out + err).splitlines() if line.strip()]
                    break
    for f in files:
        if res.status.get(f) == "ERROR":
            continue
        same = builtin.slurp(os.path.join(ctx.root, f)) == builtin.slurp(os.path.join(work, f))
        res.status[f] = "SUCCESS" if same else "ERROR"
        if not same:
            res.output.append(f"{f}: not formatted (a commit formats it)")
    shutil.rmtree(work, ignore_errors=True)
    return res


# ---------------------------------------------------------------- planning


# why: shared engine call contract; a parameter object would change every caller
def plan(reg, data, lang_id, lang_files, subtypes_by_file, env_level, rules_mod, quiet=False):  # noqa: C901, PLR0912, PLR0913, PLR0917
    """Return (ordered list of (tool, settings, files), level) for a language."""
    lang = reg.languages[lang_id]
    lvl = rules_mod.lang_level(data, lang_id, env_level)
    if lvl == "off":
        return [], lvl
    tool_files, order = {}, []
    for f in lang_files:
        for t in reg.tools_for(lang_id, subtypes_by_file.get(f, [])):
            if t not in tool_files:
                tool_files[t] = []
                order.append(t)
            tool_files[t].append(f)
    steps = []
    covered = {"syntax": set(), "format": set()}
    for tid in order:
        tool = reg.tools.get(tid)
        if not tool or tool.get("fallback"):
            continue
        st = rules_mod.tool_settings(data, lang_id, tid, tool["role"])
        tlevel = st.get("level") or tool.get("level") or ROLE_LEVEL[tool["role"]]
        if not st["enabled"] or level_rank(lvl) < level_rank(tlevel):
            # why: a tool the user turned off is a decision, not a gap for the fallback to fill
            # (opt-in tools that are off by default still leave the gap to the fallback).
            if tool.get("default_enabled", True):
                covered.get(tool["role"], set()).update(tool_files[tid])
            continue
        if not available(tool):
            if not quiet:
                qslog.log(
                    "WARN",
                    lang_id,
                    f"tool '{tid}' not installed; skipped (it is installed on the next "
                    "commit that needs it)",
                    action="plan",
                    status="SKIP",
                )
            continue
        covered.get(tool["role"], set()).update(tool_files[tid])
        steps.append((tool, st, tool_files[tid]))
    for role, fb in (("syntax", "qs-basic-syntax"), ("format", "qs-basic-format")):
        need = [f for f in lang_files if f not in covered[role]]
        if role == "format" and lang.get("basic", {}).get("no_format"):
            need = []
        st = rules_mod.tool_settings(data, lang_id, fb, role)
        if need and st["enabled"] and level_rank(lvl) >= level_rank(ROLE_LEVEL[role]):
            steps.append((reg.tools[fb], st, need))
    steps.sort(key=lambda s: ROLE_ORDER[s[0]["role"]])
    return steps, lvl


def run_language(reg, lang_id, steps, ctx, version):
    """Run the planned steps of one language.

    Args:
        reg: the Registry.
        lang_id: the language id.
        steps: (tool, settings, files) triples in order.
        ctx: the run context.
        version: the language version.

    Returns:
        list: the StepResults.
    """
    lang = reg.languages[lang_id]
    alive = None
    results = []
    for tool, st, step_files in steps:
        files = [f for f in step_files if alive is None or f in alive]
        if tool["role"] in ("format", "marker") and ctx.protect:
            # why: formatters read and write UTF-8; a legacy-charset file would be corrupted
            kept = [f for f in files if f not in ctx.protect]
            for f in sorted(set(files) - set(kept)):
                qslog.log(
                    "WARN",
                    lang_id,
                    f"{tool['id']} skipped: file is {ctx.protect[f]} (tools assume UTF-8)",
                    f,
                    tool["id"],
                    "SKIP",
                )
            files = kept
        if not files:
            continue
        r = run_tool(tool, st, lang, ctx, files, version, lang_id)
        results.append(r)
        if tool["role"] == "syntax":
            failed = {f for f, s in r.status.items() if s == "ERROR"}
            alive = (alive if alive is not None else set(files)) - failed
    return results
