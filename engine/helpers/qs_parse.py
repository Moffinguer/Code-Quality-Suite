"""qs_parse.py - parse-only checks run with the interpreter of each tool's venv.

  <python> -I qs_parse.py jinja FILE...           jinja2 Environment.parse (no rendering)
  <python> -I qs_parse.py cython FILE...          Cython's own parser (no C generation)
  <python> -I qs_parse.py asn1 FILE...            asn1tools.parse_files (pure syntax)
  <python> -I qs_parse.py ts LANG FILE...         tree-sitter: ERROR and MISSING nodes
  <python> -I qs_parse.py llvm FILE...            llvmlite parse_assembly + verify (LLVM IR)
  <python> -I qs_parse.py wl FILE...              Mathics3 parser (Wolfram Language), no evaluation
  python3  -I qs_parse.py abaplint TOOL FILE...   abaplint on staged abapGit-named copies
Output: FILE:LINE[:COL]: message. Exit 0 ok, 1 problems, 2 tool unavailable.
"""

import ctypes
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


def jinja(files):
    """Check Jinja2 templates (parsed, not rendered).

    Args:
        files: the file paths.

    Returns:
        int: 0 ok, 1 problems found, 2 tool unavailable.
    """
    import jinja2  # noqa: PLC0415 - legacy code, kept as is in the 7.1.1 cleanup

    env = jinja2.Environment(
        extensions=[
            "jinja2.ext.do",
            "jinja2.ext.loopcontrols",
            "jinja2.ext.i18n",
            "jinja2.ext.debug",
        ]
    )
    rc = 0
    for f in files:
        try:
            env.parse(open(f, encoding="utf-8").read(), filename=f)  # noqa: SIM115 - legacy code, kept as is in the 7.1.1 cleanup
        except jinja2.TemplateSyntaxError as e:
            print(f"{f}:{e.lineno}: {e.message}")
            rc = 1
    return rc


def cython(files):
    """Check Cython sources (Cython's own parser).

    Args:
        files: the file paths.

    Returns:
        int: 0 ok, 1 problems found, 2 tool unavailable.
    """
    from Cython.Compiler.Errors import CompileError, init_thread  # noqa: PLC0415 - legacy code, kept as is in the 7.1.1 cleanup
    from Cython.Compiler.TreeFragment import StringParseContext, parse_from_strings  # noqa: PLC0415 - legacy code, kept as is in the 7.1.1 cleanup

    include = re.compile(r"^([ \t]*)include[ \t]+['\"].*$", re.M)  # why: needs a file-backed source
    rc = 0
    for f in files:
        src = include.sub(r"\1pass", open(f, encoding="utf-8").read())  # noqa: SIM115 - legacy code, kept as is in the 7.1.1 cleanup
        kw = {"level": "module_pxd"} if f.endswith(".pxd") else {}
        err = None
        for level in (3, 2):  # why: legacy `print x` code is language level 2
            ctx = StringParseContext(f, cpp=True)
            ctx.set_language_level(level)
            init_thread()
            try:
                parse_from_strings(f, src, context=ctx, **kw)
                err = None
                break
            except CompileError as e:
                err = err or e
        if err is not None:
            pos = err.position or (None, 0, 0)
            print(
                f"{f}:{pos[1]}:{pos[2] + 1}: syntax error: {getattr(err, 'message_only', str(err))}"
            )
            rc = 1
    return rc


def asn1(files):
    """Check ASN.1 modules (syntax only).

    Args:
        files: the file paths.

    Returns:
        int: 0 ok, 1 problems found, 2 tool unavailable.
    """
    import asn1tools  # noqa: PLC0415 - legacy code, kept as is in the 7.1.1 cleanup

    rc = 0
    for f in files:
        try:
            asn1tools.parse_files(f)
        except Exception as e:  # ParseError carries the position in its message
            print(f"{f}:1: {str(e).splitlines()[0]}")
            rc = 1
    return rc


def ts(lang, files):
    """Check files with a tree-sitter grammar (reports ERROR and MISSING nodes).

    Args:
        lang: the grammar name.
        files: the file paths.

    Returns:
        int: 0 ok, 1 problems found, 2 tool unavailable.
    """
    from tree_sitter import Language, Parser  # noqa: PLC0415 - legacy code, kept as is in the 7.1.1 cleanup

    libs = os.environ.get("TS_LIBS", "/opt/tree-sitter-libs")
    try:
        lib = ctypes.CDLL(os.path.join(libs, f"libtree_sitter_{lang}.so"))
    except OSError as e:
        print(f"tree-sitter grammar '{lang}' not installed: {e}", file=sys.stderr)
        return 2
    fn = getattr(lib, f"tree_sitter_{lang}")
    fn.restype = ctypes.c_void_p
    cap = ctypes.pythonapi.PyCapsule_New
    cap.restype, cap.argtypes = (
        ctypes.py_object,
        (ctypes.c_void_p, ctypes.c_char_p, ctypes.c_void_p),
    )
    parser = Parser(Language(cap(fn(), b"tree_sitter.Language", None)))
    rc = 0
    for f in files:
        src = open(f, "rb").read()  # noqa: SIM115 - legacy code, kept as is in the 7.1.1 cleanup
        # why: NUL bytes = fuzz fixtures; {{...}} at the top = mustache/cookiecutter template, not code  # noqa: E501 - legacy code, kept as is in the 7.1.1 cleanup
        if b"\x00" in src or (b"{{" in src[:200] and b"}}" in src[:200]):
            continue
        root = parser.parse(src).root_node
        if not root.has_error:
            continue
        rc, stack, n = 1, [root], 0
        while stack and n < 20:
            node = stack.pop()
            if not node.has_error:
                continue
            r, c = node.start_point[0] + 1, node.start_point[1] + 1
            if node.is_missing:
                print(f"{f}:{r}:{c}: syntax error: missing {node.type!r}")
                n += 1
            elif node.type == "ERROR":
                snip = (
                    src[node.start_byte : node.end_byte][:40]
                    .decode("utf-8", "replace")
                    .replace("\n", " ")
                )
                print(f"{f}:{r}:{c}: syntax error: unexpected {snip!r}")
                n += 1
            else:
                stack.extend(reversed(node.children))
        if n == 0:
            print(f"{f}:1: syntax error")
    return rc


def llvm(files):
    """Check LLVM IR files (parse and verify).

    Args:
        files: the file paths.

    Returns:
        int: 0 ok, 1 problems found, 2 tool unavailable.
    """
    import llvmlite.binding as llvm_b  # noqa: PLC0415 - legacy code, kept as is in the 7.1.1 cleanup

    rc = 0
    for f in files:
        try:
            llvm_b.parse_assembly(open(f, encoding="utf-8").read()).verify()  # noqa: SIM115 - legacy code, kept as is in the 7.1.1 cleanup
        except RuntimeError as e:
            print(f"{f}: {str(e).replace('<string>', f).strip()}")
            rc = 1
    return rc


def wl(files):
    """Check Wolfram Language files (parsed, nothing evaluated).

    Args:
        files: the file paths.

    Returns:
        int: 0 ok, 1 problems found, 2 tool unavailable.
    """
    from mathics.core.parser.parser import Parser  # noqa: PLC0415 - legacy code, kept as is in the 7.1.1 cleanup
    from mathics_scanner.errors import SyntaxError as WLSyntaxError  # noqa: PLC0415 - legacy code, kept as is in the 7.1.1 cleanup
    from mathics_scanner.feed import MultiLineFeeder  # noqa: PLC0415 - legacy code, kept as is in the 7.1.1 cleanup

    rc = 0
    for f in files:
        src = open(f, encoding="utf-8").read()  # noqa: SIM115 - legacy code, kept as is in the 7.1.1 cleanup
        if src.startswith("#!"):  # wolframscript shebang becomes a comment, line numbers kept
            head, _, rest = src.partition("\n")
            src = "(*" + head[2:] + "*)\n" + rest
        feeder, parser = MultiLineFeeder(src, f), Parser()
        try:
            while not feeder.empty():
                if parser.parse(feeder) is None:
                    break
        except WLSyntaxError as e:
            print(f"{f}: syntax error: {type(e).__name__} {e}")
            rc = 1
    return rc


ABAP_TYPES = [
    (r"^\s*CLASS\s+\S+\s+DEFINITION", "clas"),
    (r"^\s*INTERFACE\s+\S+", "intf"),
    (r"^\s*FUNCTION-POOL\b", "fugr"),
    (r"^\s*REPORT\b|^\s*PROGRAM\b", "prog"),
]


def abaplint(tool, files):
    """abaplint only reads abapGit-named files (<name>.<type>.abap); a loose foo.abap is skipped."""
    tmp = tempfile.mkdtemp(prefix="qs-abap-")
    names = {}
    try:
        for f in files:
            base = os.path.basename(f).lower()
            if not re.search(r"\.(prog|clas|intf|fugr|fugr\.\w+|incl)\.abap$", base):
                text = open(f, encoding="utf-8", errors="replace").read()  # noqa: SIM115 - legacy code, kept as is in the 7.1.1 cleanup
                kind = next((k for rx, k in ABAP_TYPES if re.search(rx, text, re.I | re.M)), "prog")
                stem = re.sub(r"[^a-z0-9_]", "_", os.path.splitext(base)[0])
                base = f"{stem}.{kind}.abap"
            shutil.copy(f, os.path.join(tmp, base))
            names[base] = f
        cfg = json.loads(os.environ.get("QS_ABAPLINT_CONFIG") or "{}")
        cfg.setdefault("global", {"files": "/*.abap"})
        cfg["dependencies"] = []  # why: the default config git-clones dependencies at run time
        cfg.setdefault("syntax", {"version": "v757", "errorNamespace": "."})
        cfg.setdefault(
            "rules",
            {
                "parser_error": True,
                "keyword_case": True,
                "indentation": True,
                "unused_variables": True,
                "unreachable_code": True,
                "empty_statement": True,
                "obsolete_statement": True,
                "line_length": {"length": 120},
            },
        )
        json.dump(cfg, open(os.path.join(tmp, "abaplint.json"), "w"))  # noqa: SIM115 - legacy code, kept as is in the 7.1.1 cleanup
        p = subprocess.run(  # noqa: PLW1510 - legacy code, kept as is in the 7.1.1 cleanup
            [tool, "abaplint.json", "-f", "standard"],
            cwd=tmp,
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
        )
        out = p.stdout + p.stderr
        for base, orig in names.items():
            out = out.replace("./" + base, orig).replace(base, orig)
        print(out.strip())
        return 1 if p.returncode else 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv):
    """Dispatch to the parser named by the first argument.

    Args:
        argv: the mode followed by its arguments.

    Returns:
        int: the exit code (2 when no mode is given).

    Raises:
        KeyError: the mode is unknown.
    """
    if not argv:
        print(__doc__)
        return 2
    mode, rest = argv[0], argv[1:]
    if mode == "ts":
        return ts(rest[0], rest[1:])
    if mode == "abaplint":
        return abaplint(rest[0], rest[1:])
    return {"jinja": jinja, "cython": cython, "asn1": asn1, "llvm": llvm, "wl": wl}[mode](rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
