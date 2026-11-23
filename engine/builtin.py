"""Built-in checks for languages without (or missing) native tools.

basic_syntax: encoding, NUL bytes, merge-conflict markers, bracket balance outside
              strings/comments (lexer driven by the language's `basic` spec).
basic_format: whitespace-only, never changes semantics: strips trailing whitespace
              (not inside multi-line strings, heredocs, or after a trailing
              backslash), ensures one final newline, preserves line endings.
Plus structured checks: properties, ini, csv/tsv, jsonl, json/jsonc, yaml, jsp.
"""

import ast
import configparser
import csv
import io
import json
import re
import sys

import textio

CONFLICT = re.compile(r"^(<{7}|={7}|>{7}|\|{7})( |$)", re.M)
PRIVATE_KEY = re.compile(
    r"-----BEGIN ((RSA|DSA|EC|OPENSSH|PGP|ENCRYPTED) )?PRIVATE KEY( BLOCK)?-----"
)
_PAIRS = {")": "(", "]": "[", "}": "{"}


def slurp(path):
    """Read a file as bytes; raises OSError when unreadable."""
    return textio.read_bytes(path)


# abs path -> declared non-UTF-8 charset (set by the engine from the encoding policy)
CHARSET_OF: dict[str, str] = {}


def read_text(path):
    """Read a file for a built-in check.

    Args:
        path: the file path.

    Returns:
        tuple: (text, error); text is None and error says why when the file is
        binary or not valid in its charset.
    """
    raw = slurp(path)
    if b"\x00" in raw:
        return None, "contains NUL bytes (binary?)"
    cs = CHARSET_OF.get(path)
    try:
        return (raw.decode(cs) if cs else raw.decode("utf-8-sig")), ""
    except (UnicodeDecodeError, LookupError) as e:
        return None, f"not valid {(cs or 'UTF-8').upper()} at byte {getattr(e, 'start', 0)}"


# why: single-pass lexer state machine; splitting it would risk behaviour
def _lex(text, spec):  # noqa: C901, PLR0912, PLR0915
    """Yield (kind, start, end) spans for strings/comments; brackets reported separately.

    spec keys: line_comment [..], block_comment [[open, close]..], strings [delims],
    raw_strings [[open, close]..] (multi-line, no escapes), escape "\\",
    char_prefix (e.g. "#\\" for Lisp chars), nested_block bool.
    """
    line_c = sorted(spec.get("line_comment", []), key=len, reverse=True)
    blocks = spec.get("block_comment", [])
    raws = spec.get("raw_strings", [])
    strs = sorted(spec.get("strings", []), key=len, reverse=True)
    esc = spec.get("escape", "\\")
    nested = spec.get("nested_block", False)
    char_prefix = spec.get("char_prefix", "")
    i, n = 0, len(text)
    while i < n:
        if char_prefix and text.startswith(char_prefix, i):
            i += len(char_prefix) + 1
            continue
        matched = False
        for o, c in raws:
            if text.startswith(o, i):
                j = text.find(c, i + len(o))
                end = n if j < 0 else j + len(c)
                yield ("string", i, end, j < 0)
                i, matched = end, True
                break
        if matched:
            continue
        for o, c in blocks:
            if text.startswith(o, i):
                depth, j = 1, i + len(o)
                while j < n and depth:
                    if nested and text.startswith(o, j):
                        depth += 1
                        j += len(o)
                    elif text.startswith(c, j):
                        depth -= 1
                        j += len(c)
                    else:
                        j += 1
                yield ("comment", i, j, depth > 0)
                i, matched = j, True
                break
        if matched:
            continue
        for lc in line_c:
            if text.startswith(lc, i):
                j = text.find("\n", i)
                end = n if j < 0 else j
                yield ("comment", i, end, False)
                i, matched = end, True
                break
        if matched:
            continue
        for d in strs:
            if text.startswith(d, i):
                j = i + len(d)
                multiline = len(d) >= 3
                while j < n:
                    if esc and text[j] == esc:
                        j += 2
                        continue
                    if text.startswith(d, j):
                        break
                    if text[j] == "\n" and not multiline and not spec.get("multiline_strings"):
                        break
                    j += 1
                closed = j < n and text.startswith(d, j)
                end = j + len(d) if closed else j
                yield ("string", i, end, not closed and multiline)
                i, matched = end, True
                break
        if matched:
            continue
        yield ("code", i, i + 1, False)
        i += 1


def basic_syntax(path, spec):
    """Check the bracket balance and the string and comment rules of a file.

    Args:
        path: the file path.
        spec: the language's `basic` rules (comment and string delimiters, brackets).

    Returns:
        list: findings (line, message); empty when the file is valid.
    """
    text, err = read_text(path)
    if text is None:
        return [err]
    problems = []
    m = CONFLICT.search(text)
    if m:
        problems.append(f"merge-conflict marker at line {text.count(chr(10), 0, m.start()) + 1}")
    brackets = spec.get("brackets", "()[]{}")
    if not brackets:
        return problems
    opens = set(brackets[0::2])
    closes = {brackets[k + 1]: brackets[k] for k in range(0, len(brackets), 2)}
    stack = []
    for kind, s, _e, unterminated in _lex(text, spec):
        if kind != "code":
            if unterminated:
                problems.append(
                    f"unterminated {kind} starting at line {text.count(chr(10), 0, s) + 1}"
                )
                return problems
            continue
        ch = text[s]
        if ch in opens:
            stack.append((ch, s))
        elif ch in closes:
            if not stack or stack[-1][0] != closes[ch]:
                problems.append(f"unbalanced '{ch}' at line {text.count(chr(10), 0, s) + 1}")
                return problems
            stack.pop()
    if stack:
        ch, s = stack[-1]
        problems.append(f"unclosed '{ch}' opened at line {text.count(chr(10), 0, s) + 1}")
    return problems


_HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


# why: single-pass whitespace normaliser; splitting it would risk behaviour
def basic_format(path, spec, write=True):  # noqa: C901, PLR0912
    """Return True if the file is (or would be) unchanged."""
    raw = slurp(path)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return True
    bom = text.startswith("﻿")
    eol = "\r\n" if text.count("\r\n") > text.count("\n") / 2 and "\r\n" in text else "\n"
    body = text[1:] if bom else text
    lines = body.replace("\r\n", "\n").split("\n")
    final_nl = body.endswith("\n") or body.endswith("\r\n")
    if final_nl:
        lines = lines[:-1]
    keep = set()
    if spec.get("ws_significant"):
        keep = set(range(len(lines)))
    else:
        joined = "\n".join(lines)
        for kind, s, e, _ in (
            _lex(joined, spec) if spec.get("strings") or spec.get("raw_strings") else ()
        ):
            if kind == "string" and "\n" in joined[s:e]:
                a = joined.count("\n", 0, s)
                b = joined.count("\n", 0, e)
                keep.update(range(a, b))
        if spec.get("heredoc"):
            k = 0
            while k < len(lines):
                m = _HEREDOC.search(lines[k])
                if m:
                    tag, j = m.group(2), k + 1
                    while j < len(lines) and lines[j].strip() != tag:
                        keep.add(j)
                        j += 1
                    k = j
                k += 1
    out = []
    for k, ln in enumerate(lines):
        if k in keep:
            out.append(ln)
            continue
        stripped = ln.rstrip(" \t")
        # why: removing spaces after a trailing backslash would create a line continuation.
        if stripped.endswith("\\") and stripped != ln:
            out.append(ln)
        else:
            out.append(stripped)
    while out and out[-1] == "" and not spec.get("ws_significant"):
        out.pop()
    new = eol.join(out) + (eol if out else "")
    if bom:
        new = "﻿" + new
    changed = new != text
    if changed and write:
        with open(path, "w", encoding="utf-8", newline="") as fh:
            fh.write(new)
    return not changed


def python_ast(path, version=None):
    """Native Python parse check, honouring the target version when the checker supports it."""
    text, err = read_text(path)
    if text is None:
        return [err]
    target = None
    m = re.match(r"(\d+)\.(\d+)", str(version or ""))
    if m:
        target = (int(m.group(1)), int(m.group(2)))
    run = sys.version_info[:2]
    try:
        if target and (3, 7) <= target <= run:
            ast.parse(text, filename=path, feature_version=target)
        else:
            ast.parse(text, filename=path)
    except SyntaxError as e:
        if target and target > run:
            return []  # why: newer syntax than this checker knows; ruff still parses it
        where = f"line {e.lineno}" + (f" col {e.offset}" if e.offset else "")
        return [
            f"{where}: {e.msg}" + (f" (target Python {target[0]}.{target[1]})" if target else "")
        ]
    return []


def check_properties(path):
    """Check the syntax of a .properties file.

    Args:
        path: the file path.

    Returns:
        list: findings (line, message); empty when the file is valid.
    """
    text, err = read_text(path)
    if text is None:
        return [err]
    problems, seen, cont = [], {}, False
    for n, line in enumerate(text.splitlines(), 1):
        if cont:
            cont = line.rstrip().endswith("\\") and not line.rstrip().endswith("\\\\")
            continue
        s = line.strip()
        if not s or s[0] in "#!":
            continue
        m = re.match(r"((?:\\.|[^=:\s\\])+)\s*[=:\s]?", s)
        if not m:
            problems.append(f"line {n}: malformed entry")
            continue
        key = m.group(1)
        if key in seen:
            problems.append(f"line {n}: duplicate key '{key}' (first at line {seen[key]})")
        seen.setdefault(key, n)
        cont = s.endswith("\\") and not s.endswith("\\\\")
    return problems


def check_ini(path):
    """Check the syntax of an INI file.

    Args:
        path: the file path.

    Returns:
        list: findings (line, message); empty when the file is valid.
    """
    text, err = read_text(path)
    if text is None:
        return [err]
    cp = configparser.RawConfigParser(
        strict=True,
        allow_no_value=True,
        interpolation=None,
        comment_prefixes=("#", ";"),
        inline_comment_prefixes=None,
    )
    try:
        cp.read_string(
            text if re.match(r"\s*[\[#;]", text) or not text.strip() else "[__root__]\n" + text
        )
    except configparser.Error as e:
        return [str(e).splitlines()[0]]
    return []


def check_ini_loose(path):
    """INI dialects that allow repeated keys (systemd units, desktop entries)."""
    text, err = read_text(path)
    if text is None:
        return [err]
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if not s or s[0] in "#;":
            continue
        if s.startswith("["):
            if not re.match(r"^\[[^\[\]]+\]$", s):
                return [f"line {n}: malformed section header"]
        elif "=" not in s and not line[:1].isspace() and not s.endswith("\\"):
            return [f"line {n}: expected key=value"]
    return []


def check_toml(path):
    """Check the syntax of a TOML file.

    Args:
        path: the file path.

    Returns:
        list: findings (line, message); empty when the file is valid.
    """
    text, err = read_text(path)
    if text is None:
        return [err]
    try:
        # why: absent before Python 3.11, the check is skipped there
        import tomllib  # noqa: PLC0415
    except ImportError:
        return []
    try:
        tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        return [str(e)]
    return []


def check_csv(path, delimiter=","):
    """Check that a CSV file parses and has consistent rows.

    Args:
        path: the file path.
        delimiter: the field delimiter.

    Returns:
        list: findings (line, message); empty when the file is valid.
    """
    text, err = read_text(path)
    if text is None:
        return [err]
    rows = list(csv.reader(io.StringIO(text), delimiter=delimiter, strict=True))
    if not rows:
        return []
    width = len(rows[0])
    for n, r in enumerate(rows[1:], 2):
        if r and len(r) != width:
            return [f"row {n}: {len(r)} fields, header has {width}"]
    return []


def check_jsonl(path):
    """Check the syntax of a JSON Lines file.

    Args:
        path: the file path.

    Returns:
        list: findings (line, message); empty when the file is valid.
    """
    text, err = read_text(path)
    if text is None:
        return [err]
    for n, line in enumerate(text.splitlines(), 1):
        if line.strip():
            try:
                json.loads(line)
            except json.JSONDecodeError as e:
                return [f"line {n}: {e.msg}"]
    return []


def strip_jsonc(text):
    """Remove comments and trailing commas from JSON with comments.

    Args:
        text: the JSONC text.

    Returns:
        str: plain JSON text (string contents untouched).
    """
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        else:
            out.append(c)
        i += 1
    s = "".join(out)
    return re.sub(r",(\s*[}\]])", r"\1", s)


def check_json(path, jsonc=False):
    """Check the syntax of a JSON file.

    Args:
        path: the file path.
        jsonc: accept comments and trailing commas.

    Returns:
        list: findings (line, message); empty when the file is valid.
    """
    text, err = read_text(path)
    if text is None:
        return [err]
    try:
        json.loads(strip_jsonc(text) if jsonc else text)
    except json.JSONDecodeError as e:
        return [f"line {e.lineno} col {e.colno}: {e.msg}"]
    return []


def check_yaml(path):
    """Check the syntax of a YAML file.

    Args:
        path: the file path.

    Returns:
        list: findings (line, message); empty when the file is valid.
    """
    text, err = read_text(path)
    if text is None:
        return [err]
    try:
        # why: optional dependency (python3-yaml in the base image)
        import yaml  # noqa: PLC0415
    except ImportError:
        return []
    try:
        for _ in yaml.compose_all(text, Loader=yaml.SafeLoader):
            pass
    except yaml.YAMLError as e:
        return [str(e).replace("\n", " ")[:300]]
    return []


def check_jsp(path):
    """Check the syntax of a JSP file.

    Args:
        path: the file path.

    Returns:
        list: findings (line, message); empty when the file is valid.
    """
    text, err = read_text(path)
    if text is None:
        return [err]
    o, c = text.count("<%"), text.count("%>")
    return [] if o == c else [f"unbalanced <% %> delimiters ({o} open, {c} close)"]


CHECKS = {
    "properties": check_properties,
    "ini": check_ini,
    "ini-loose": check_ini_loose,
    "toml": check_toml,
    "csv": lambda p: check_csv(p, ","),
    "tsv": lambda p: check_csv(p, "\t"),
    "jsonl": check_jsonl,
    "json": check_json,
    "jsonc": lambda p: check_json(p, jsonc=True),
    "yaml": check_yaml,
    "jsp": check_jsp,
}
