"""Compiled / systems / functional languages and other programming languages."""
from core import (A_GO, A_X64, A_X86, A_X86ARM, C_LIKE, HASH, LISP, ML, PLAIN, apt, det, gh, lang, lex,
                  lint_tool, npm, pip, probe, script, shebang_marker, subtype, syntax_tool, tool, fmt_tool,
                  url, version)

# ------------------------------------------------------------------ C family

CLANG_FORMAT = pip("clang-format==23.1.3", "clang-format")
fmt_tool("clang-format", "clang-format", ["clang-format", "-i", "--style=file:{config}", "{args}", "{files}"],
         check=["clang-format", "--dry-run", "--Werror", "--style=file:{config}", "{args}", "{files}"],
         bin="clang-format", install=[CLANG_FORMAT],
         config={"file": ".clang-format", "format": "yaml", "base": "c/clang-format"},
         homepage="https://clang.llvm.org/docs/ClangFormat.html", license="Apache-2.0 WITH LLVM-exception")
CPPCHECK_DEFAULTS = {"--enable": "all", "--inline-suppr": True,
                     "--suppress": ["missingIncludeSystem", "missingInclude", "unusedFunction",
                                    "unmatchedSuppression", "checkersReport"]}
lint_tool("cppcheck", "Cppcheck (C++)", ["cppcheck", "--quiet", "--error-exitcode=1", "--language=c++",
                                         "--std=c++{v}", "{args}", "{files}"],
          bin="cppcheck", install=[apt("cppcheck")], rule_args={"joiner": "="}, defaults=CPPCHECK_DEFAULTS,
          license="GPL-3.0", notes="per-file mode: whole-program checks (unusedFunction, missingInclude) off")
lint_tool("cppcheck-c", "Cppcheck (C)", ["cppcheck", "--quiet", "--error-exitcode=1", "--language=c",
                                         "--std=c{v}", "{args}", "{files}"],
          bin="cppcheck", install=[apt("cppcheck")], rule_args={"joiner": "="}, defaults=CPPCHECK_DEFAULTS)
lint_tool("clang-tidy", "clang-tidy", ["clang-tidy", "--quiet", "--config-file={config}", "-p", "{found_dir}",
                                       "{args}", "{files}"],
          bin="clang-tidy", install=[pip("clang-tidy==22.1.8", "clang-tidy")],
          config={"file": ".clang-tidy", "format": "yaml", "base": "c/clang-tidy"},
          requires={"any_file": ["compile_commands.json", "build/compile_commands.json"],
                    "why": "no compile_commands.json (CMake: -DCMAKE_EXPORT_COMPILE_COMMANDS=ON)"},
          timeout=900, notes="needs the compilation database to know includes and flags")
tool("flawfinder", "deep", "Flawfinder (C/C++ security)",
     {"check": ["flawfinder", "--quiet", "--dataonly", "--columns", "{args}", "{files}"]},
     bin="flawfinder", install=[apt("flawfinder")], rule_args={"joiner": "="},
     defaults={"--minlevel": 3, "--error-level": 3}, license="GPL-2.0")
C_VERSION = version("17", env="QS_C_STD", label="C standard (99, 11, 17, 23)", detect=[
    det("CMakeLists.txt", r"CMAKE_C_STANDARD\s+(\d+)"), det("CMakeLists.txt", r"C_STANDARD\s+(\d+)"),
    det("meson.build", r"c_std=c(\d+)"), det("Makefile", r"-std=(?:c|gnu)(\d+)")])
CXX_VERSION = version("17", env="QS_CXX_STD", label="C++ standard (11, 14, 17, 20, 23)", detect=[
    det("CMakeLists.txt", r"CMAKE_CXX_STANDARD\s+(\d+)"), det("CMakeLists.txt", r"cxx_std_(\d+)"),
    det("meson.build", r"cpp_std=c\+\+(\d+)"), det("Makefile", r"-std=(?:c|gnu)\+\+(\d+)")])
CPP_PROBE = [probe(r"^\s*(class|namespace|template\s*<|using\s+namespace)\b", 5), probe(r"\bstd::", 3),
             probe(r"^\s*(public|private|protected):", 3)]
lang("c", "C", ext=[".c", ".h"], probe=[probe(r"^\s*#include\s*<(stdio|stdlib|string|unistd)\.h>", 1)],
     default_for_ambiguous=True,
     tools=["clang-format", "cppcheck-c", "clang-tidy", "flawfinder"], basic=C_LIKE, version=C_VERSION)
lang("cpp", "C++", ext=[".cpp", ".cc", ".cxx", ".c++", ".hpp", ".hh", ".hxx", ".h++", ".ipp", ".tpp", ".inl",
                        ".h", ".ino", ".cppm", ".ixx"],
     probe=CPP_PROBE, tools=["clang-format", "cppcheck", "clang-tidy", "flawfinder"], basic=C_LIKE,
     version=CXX_VERSION)
lang("objective-c", "Objective-C / Objective-C++", ext=[".m", ".mm"],
     probe=[probe(r"^\s*#import\b|^\s*@(interface|implementation|protocol|end)\b", 10)],
     tools=["clang-format"], basic=C_LIKE, marker={"modeline": "// -*- mode: objc -*-"})
lang("cuda", "CUDA", ext=[".cu", ".cuh"], tools=["clang-format"], basic=C_LIKE)
lang("opencl", "OpenCL C", ext=[".cl", ".opencl"], probe=[probe(r"__kernel\b|\bkernel\s+void\b", 10)],
     tools=["clang-format"], basic=C_LIKE)
lang("metal", "Metal", ext=[".metal"], tools=["clang-format"], basic=C_LIKE)
syntax_tool("glslang", "glslangValidator", ["glslangValidator", "{file}"], bin="glslangValidator",
            install=[apt("glslang-tools")], batch=False)
lang("glsl", "GLSL", ext=[".vert", ".frag", ".geom", ".comp", ".tesc", ".tese", ".rgen", ".rchit", ".rmiss",
                         ".mesh", ".task"], tools=["glslang"], basic=C_LIKE)
lang("glsl-generic", "GLSL (unknown stage)", ext=[".glsl"], basic=C_LIKE)
lang("hlsl", "HLSL", ext=[".hlsl", ".fx", ".fxh"], basic=C_LIKE)
lang("wgsl", "WGSL", ext=[".wgsl"], basic=C_LIKE, candidates=["naga-cli (cargo)"])

# ------------------------------------------------------------------ Rust / Go / Zig

fmt_tool("rustfmt", "rustfmt", ["rustfmt", "--edition", "{v}", ["--config-path", "{config}"], "{args}", "{files}"],
         check=["rustfmt", "--check", "--edition", "{v}", ["--config-path", "{config}"], "{args}", "{files}"],
         bin="rustfmt", needs=["rust"], config={"file": "rustfmt.toml", "format": "toml"},
         notes="formats modules declared with `mod x;` too (stable rustfmt has no skip_children)")
lint_tool("clippy", "Clippy", ["cargo", "clippy", "--offline", "--quiet", "--no-deps", "--", "-D", "warnings",
                               "{args}"],
          bin="cargo", needs=["rust"], group_by="Cargo.toml", cwd="group", scope="project", timeout=1200,
          offline_skip=[r"failed to (download|get|load|select)", r"no matching package", r"offline",
                        r"can't checkout", r"failed to fetch"],
          notes="runs per crate (nearest Cargo.toml); dependencies must already be vendored/cached")
lang("rust", "Rust", ext=[".rs"], shebang=[r"\brust-script\b"], tools=["rustfmt", "clippy"],
     basic=lex(["//"], [("/*", "*/")], strings=('"',), nested=True),
     version=version("2021", env="RUST_EDITION", label="Rust edition (2015, 2018, 2021, 2024)", detect=[
         det("Cargo.toml", r'^\s*edition\s*=\s*"(\d{4})"')]))

syntax_tool("gofmt-e", "gofmt -e (parse)", ["gofmt", "-e", "-l", "{files}"], bin="gofmt", needs=["go"])
fmt_tool("gofmt", "gofmt", ["gofmt", "-w", "{args}", "{files}"], check=["gofmt", "-l", "{args}", "{files}"],
         bin="gofmt", needs=["go"], fail_on_output=True)
lint_tool("golangci-lint", "golangci-lint",
          ["golangci-lint", "run", "--output.text.path=stdout", ["--new-from-rev={env:QS_BASE_REV}"],
           ["--config", "{config}"], "{args}", "{dirs}"],
          bin="golangci-lint", needs=["go"], group_by="go.mod", cwd="group", timeout=900,
          install=[gh("golangci/golangci-lint", "v2.14.0", "golangci-lint-{ver}-linux-{arch}.tar.gz",
                      ["golangci-lint"], arch=A_GO)],
          config={"file": ".golangci.yml", "format": "yaml"},
          defaults={"version": "2", "linters": {"default": "standard"}, "issues": {"max-same-issues": 0}},
          version_rules={"run.go": "{v_major}.{v_minor}"},
          offline_skip=[r"GOPROXY=off", r"cannot find module", r"missing go\.sum entry", r"no required module",
                        r"could not import", r"module lookup disabled"],
          notes="includes govet/staticcheck/errcheck/ineffassign/unused; only packages of the changed files; "
                "formatters stay off (gofmt owns formatting)")
lang("go", "Go", ext=[".go"], tools=["gofmt-e", "gofmt", "golangci-lint"],
     basic=lex(["//"], [("/*", "*/")], strings=('"', "'"), raw=[("`", "`")]),
     version=version("1.22", env="GO_VERSION", label="Go version (e.g. 1.22)", ask=False, detect=[
         det("go.mod", r"^go\s+(\d+\.\d+)"), det("go.work", r"^go\s+(\d+\.\d+)")]))
syntax_tool("go-mod-parse", "go mod edit -json (parse)", ["go", "mod", "edit", "-json", "{file}"], bin="go",
            needs=["go"], batch=False)
fmt_tool("go-mod-fmt", "go mod edit -fmt", ["go", "mod", "edit", "-fmt", "{file}"], bin="go", needs=["go"],
         batch=False)
lang("go-mod", "Go module files", kind="config", names=["go.mod"], tools=["go-mod-parse", "go-mod-fmt"],
     basic=PLAIN)

ZIG = pip("ziglang==0.17.0", "zig=ziglang/zig")
syntax_tool("zig-ast-check", "zig ast-check", ["zig", "ast-check", "{file}"], bin="zig", install=[ZIG], batch=False)
fmt_tool("zig-fmt", "zig fmt", ["zig", "fmt", "{files}"], check=["zig", "fmt", "--check", "{files}"], bin="zig",
         install=[ZIG])
lang("zig", "Zig", ext=[".zig", ".zon"], tools=["zig-ast-check", "zig-fmt"], basic=lex(["//"], [], strings=('"', "'")),
     subtypes=[subtype("zon", "Zig object notation", globs=["*.zon"], exclude_tools=["zig-ast-check"])],
     notes="formatting rules follow the installed Zig version")

# ------------------------------------------------------------------ Nim / Crystal / D / V / Odin

lint_tool("nim-check", "nim check", ["nim", "check", "--hints:off", "--colors:off", "{file}"], bin="nim",
          install=[apt("nim")], batch=False, skip_on=[r"cannot open file"], skip_why="imports a package not installed")
fmt_tool("nimpretty", "nimpretty", ["nimpretty", "{files}"], bin="nimpretty", install=[apt("nim")], batch=False)
lang("nim", "Nim", ext=[".nim", ".nims", ".nimble"], tools=["nimpretty", "nim-check"],
     basic=lex(["#"], [("#[", "]#")], strings=('"""', '"'), nested=True))
fmt_tool("crystal-format", "crystal tool format", ["crystal", "tool", "format", "{files}"],
         check=["crystal", "tool", "format", "--check", "{files}"], bin="crystal", install=[apt("crystal")])
lang("crystal", "Crystal", ext=[".cr"], shebang=[r"\bcrystal\b"], tools=["crystal-format"],
     basic=lex(["#"], [], strings=('"',)), candidates=["ameba (needs shards build)"])
lang("d", "D", ext=[".d", ".di"], probe=[probe(r"^\s*(module|import)\s+[\w.]+;", 5)], basic=lex(
    ["//"], [("/*", "*/"), ("/+", "+/")], strings=('"', "`")),
    candidates=["dfmt / D-Scanner (no prebuilt release assets; build with dub)"])
lang("v", "V", ext=[".vv", ".vsh"], basic=C_LIKE, candidates=["v fmt / v vet (V compiler)"])
lang("odin", "Odin", ext=[".odin"], basic=C_LIKE, candidates=["odinfmt (ols)"])

# ------------------------------------------------------------------ Fortran / Ada / COBOL / Pascal / asm

syntax_tool("gfortran-syntax", "gfortran -fsyntax-only", ["gfortran", "-fsyntax-only", "-J", "{tmp}", "{file}"],
            bin="gfortran", install=[apt("gfortran")], batch=False,
            skip_on=[r"Cannot open module file", r"Can't open included file"],
            skip_why="depends on modules/includes compiled elsewhere")
fmt_tool("fprettify", "fprettify", ["fprettify", "{args}", "{files}"], bin="fprettify",
         install=[pip("fprettify==0.3.7", "fprettify")], rule_args={"joiner": " "},
         defaults={"--indent": 3, "--line-length": 132})
lint_tool("fortitude", "Fortitude", ["fortitude", "check", "--output-format", "concise", "{args}", "{files}"],
          bin="fortitude", install=[pip("fortitude-lint==0.9.2", "fortitude")], license="MIT")
lang("fortran", "Fortran", ext=[".f90", ".f95", ".f03", ".f08", ".f18", ".F90", ".f", ".for", ".ftn", ".f77", ".F"],
     tools=["gfortran-syntax", "fprettify", "fortitude"], basic=lex(["!"], [], strings=('"', "'")),
     subtypes=[subtype("fixed-form", "Fixed-form source", globs=["*.f", "*.for", "*.ftn", "*.f77", "*.F"],
                       exclude_tools=["fprettify", "fortitude"])],
     notes="fprettify only handles free form; fixed form gets the column-safe whitespace formatting")
syntax_tool("gnat-syntax", "gcc -gnats (syntax only)", ["gcc", "-c", "-gnats", "-gnatf", "{file}"], bin="gcc",
            install=[apt("gnat")], batch=False, cwd="tmp")
lang("ada", "Ada", ext=[".adb", ".ads", ".ada"], tools=["gnat-syntax"], basic=lex(["--"], [], strings=('"',)),
     candidates=["gnatformat / gnatpp (AdaCore, not packaged for Ubuntu)"])
syntax_tool("cobc-syntax", "cobc -fsyntax-only", ["cobc", "-fsyntax-only", "{file}"], bin="cobc",
            install=[apt("gnucobol")], batch=False, skip_on=[r"(copybook|COPY) .*not found", r"cannot find"],
            skip_why="copybooks not available in isolation")
lang("cobol", "COBOL", ext=[".cob", ".cbl", ".cpy", ".cobol", ".pco"], tools=["cobc-syntax"],
     basic=lex(["*>"], [], strings=('"', "'"), brackets="()"),
     notes="fixed-format columns are respected: only trailing whitespace/final newline change")
fmt_tool("pasfmt", "pasfmt", ["pasfmt", "{files}"], check=["pasfmt", "--mode", "check", "{files}"], bin="pasfmt",
         install=[gh("integrated-application-development/pasfmt", "v0.7.0",
                     "pasfmt-{ver}-x86_64-unknown-linux-gnu.tar.gz", ["pasfmt"], arch={"amd64": "x86_64"})])
lang("pascal", "Pascal / Delphi", ext=[".pas", ".dpr", ".dpk", ".lpr", ".pp", ".inc", ".dfm"],
     probe=[probe(r"^\s*(unit|program|library)\s+\w+\s*;", 10), probe(r"^\s*(interface|implementation|uses)\b", 3)],
     tools=["pasfmt"], basic=lex(["//"], [("{", "}"), ("(*", "*)")], strings=("'",), escape="", brackets="()[]"),
     marker={"modeline": "// -*- mode: pascal -*-"})
lang("assembly", "Assembly", ext=[".asm", ".s", ".S", ".nasm", ".inc"],
     probe=[probe(r"^\s*(section|global|extern|mov|push|pop|jmp|\.text|\.data|\.globl)\b", 3)],
     basic=lex([";", "#", "//"], [("/*", "*/")], strings=('"',), brackets=""))

# ------------------------------------------------------------------ hardware description

VERIBLE = gh("chipsalliance/verible", "v0.0-4296-g0f262651", "verible-{tag}-linux-static-{arch}.tar.gz",
             ["verible-verilog-syntax", "verible-verilog-format", "verible-verilog-lint"], arch=A_X86ARM)
syntax_tool("verible-syntax", "verible-verilog-syntax", ["verible-verilog-syntax", "{files}"],
            bin="verible-verilog-syntax", install=[VERIBLE])
fmt_tool("verible-format", "verible-verilog-format", ["verible-verilog-format", "--inplace", "{args}", "{files}"],
         check=["verible-verilog-format", "--verify", "{args}", "{files}"], bin="verible-verilog-format",
         install=[VERIBLE], rule_args={"joiner": "="}, defaults={"--column_limit": 100, "--indentation_spaces": 2})
lint_tool("verible-lint", "verible-verilog-lint", ["verible-verilog-lint", ["--rules_config={config}"], "{files}"],
          bin="verible-verilog-lint", install=[VERIBLE], config={"file": ".rules.verible_lint", "format": "verible"},
          defaults={"line-length": "length:100"}, notes="line length matches the formatter column limit")
for _lid, _name, _ext in (("verilog", "Verilog", [".v", ".vh"]), ("systemverilog", "SystemVerilog", [".sv", ".svh"])):
    lang(_lid, _name, ext=_ext, probe=[probe(r"^\s*(module|endmodule|always|wire|reg|assign)\b", 5)],
         tools=["verible-syntax", "verible-format", "verible-lint"], basic=C_LIKE,
         marker={"modeline": "// -*- mode: verilog -*-"} if _lid == "verilog" else None)
syntax_tool("ghdl-syntax", "ghdl -s", ["ghdl", "-s", "--std={v}", "--workdir={tmp}", "{files}"], bin="ghdl",
            install=[apt("ghdl")], skip_on=[r"unit \"\w+\" not found"], skip_why="depends on other design units")
VSG = pip("vsg==3.35.0", "vsg")
fmt_tool("vsg-fix", "VHDL Style Guide (fix)", ["vsg", "--fix", "--quality_report", "/dev/null",
                                                ["--configuration", "{config}"], "-f", "{files}"],
         check="diff", bin="vsg", install=[VSG], success_fix=[0, 1],
         config={"file": "vsg.json", "format": "json"}, defaults={"rule": {"global": {"indent_size": 2}}})
lint_tool("vsg", "VHDL Style Guide", ["vsg", ["--configuration", "{config}"], "-of", "syntastic", "-f", "{files}"],
          bin="vsg", install=[VSG], config={"file": "vsg.json", "format": "json", "inherit": "vsg-fix"})
lang("vhdl", "VHDL", ext=[".vhd", ".vhdl", ".vho"], tools=["ghdl-syntax", "vsg-fix", "vsg"],
     basic=lex(["--"], [("/*", "*/")], strings=('"',), escape="", brackets="()"),
     version=version("08", env="QS_VHDL_STD", label="VHDL standard (87, 93, 93c, 00, 02, 08, 19)", ask=False))

# ------------------------------------------------------------------ Apple / mobile / .NET

fmt_tool("swiftformat", "SwiftFormat", ["swiftformat", "--quiet", ["--config", "{config}"], "{args}", "{files}"],
         check=["swiftformat", "--lint", "--quiet", ["--config", "{config}"], "{args}", "{files}"],
         bin="swiftformat",
         install=[gh("nicklockwood/SwiftFormat", "0.63.1", "swiftformat_linux{arch}.zip", ["swiftformat"],
                     arch={"amd64": "", "arm64": "_aarch64"})],
         config={"file": ".swiftformat", "format": "flags-space"}, defaults={"indent": 4, "maxwidth": 120},
         version_rules={"swiftversion": "{v}"}, license="MIT")
lint_tool("swiftlint", "SwiftLint", ["swiftlint", "lint", "--quiet", "--strict", ["--config", "{config}"], "{files}"],
          bin="swiftlint",
          install=[gh("realm/SwiftLint", "0.65.1", "swiftlint_linux_{arch}.zip", ["swiftlint"], arch=A_GO)],
          config={"file": ".swiftlint.yml", "format": "yaml"},
          defaults={"disabled_rules": ["trailing_whitespace", "opening_brace", "trailing_comma", "vertical_whitespace",
                                       "line_length", "colon", "comma", "statement_position", "indentation_width",
                                       "closure_parameter_position", "leading_whitespace", "void_return"]},
          license="MIT", notes="style rules that SwiftFormat rewrites are disabled")
lang("swift", "Swift", ext=[".swift"], shebang=[r"\bswift\b"], tools=["qs-marker", "swiftformat", "swiftlint"],
     basic=lex(["//"], [("/*", "*/")], strings=('"""', '"'), nested=True),
     marker=shebang_marker("#!/usr/bin/env swift"),
     version=version("5.10", env="QS_SWIFT_VERSION", label="Swift version (e.g. 5.9, 6.0)", ask=False, detect=[
         det("Package.swift", r"swift-tools-version:\s*(\d+\.\d+)"), det(".swift-version", r"^\s*(\d+\.\d+)")]))
fmt_tool("dart-format", "dart format", ["dart", "format", "--language-version={v}", "{files}"],
         check=["dart", "format", "--output=none", "--set-exit-if-changed", "--language-version={v}", "{files}"],
         bin="dart", needs=["dart"])
lint_tool("dart-analyze", "dart analyze", ["dart", "analyze", "--fatal-infos", "{files}"], bin="dart",
          needs=["dart"], skip_on=[r"Target of URI doesn't exist", r"uri_does_not_exist", r"Couldn't resolve the package"],
          skip_why="package dependencies are not resolved inside the container")
lang("dart", "Dart", ext=[".dart"], shebang=[r"\bdart\b"], tools=["dart-format", "dart-analyze"],
     basic=lex(["//"], [("/*", "*/")], strings=('"""', "'''", '"', "'"), nested=True),
     version=version("3.9", env="QS_DART_VERSION", label="Dart language version", ask=False, detect=[
         det("pubspec.yaml", r"sdk:\s*['\"]?[\^>=~ ]*(\d+\.\d+)")]))
DOTNET_TOOL = "dotnet tool install {pkg} --tool-path /opt/qs/dotnet-tools {ver} && ln -sf /opt/qs/dotnet-tools/{bin} /opt/qs/bin/{bin}"
fmt_tool("csharpier", "CSharpier", ["csharpier", "format", "{files}"], check=["csharpier", "check", "{files}"],
         bin="csharpier", needs=["dotnet"],
         install=[script(DOTNET_TOOL.format(pkg="csharpier", ver="--version '1.*'", bin="csharpier"))],
         homepage="https://csharpier.com", license="MIT", notes="opinionated: few options by design")
lang("csharp", "C#", ext=[".cs", ".csx"], tools=["csharpier"], basic=dict(C_LIKE, brackets=""),
     candidates=["dotnet format style/analyzers (needs the project to restore and build)"])
fmt_tool("dotnet-format-ws", "dotnet format whitespace", ["dotnet", "format", "whitespace", ".", "--folder",
                                                           "--include", "{files}"],
         check=["dotnet", "format", "whitespace", ".", "--folder", "--verify-no-changes", "--include", "{files}"],
         bin="dotnet", needs=["dotnet"], notes="reads the repository .editorconfig (dotnet has no flag for another file)")
lang("vbnet", "Visual Basic .NET", ext=[".vb"], tools=["dotnet-format-ws"], basic=lex(["'"], [], strings=('"',),
                                                                                    escape="", brackets="()"))
fmt_tool("fantomas", "Fantomas", ["fantomas", "{files}"], check=["fantomas", "--check", "{files}"], bin="fantomas",
         needs=["dotnet"], install=[script(DOTNET_TOOL.format(pkg="fantomas", ver="--version '7.*'", bin="fantomas"))],
         license="Apache-2.0")
lang("fsharp", "F#", ext=[".fs", ".fsi", ".fsx", ".fsscript"],
     probe=[probe(r"^\s*(open|module|namespace)\s+[\w.]+|^\s*let\s+(rec\s+|mutable\s+)?\w+", 5)],
     tools=["fantomas"], basic=lex(["//"], [("(*", "*)")], strings=('"""', '"'), nested=True),
     marker={"modeline": "// -*- mode: fsharp -*-"})

# ------------------------------------------------------------------ functional

fmt_tool("fourmolu", "Fourmolu", ["fourmolu", "--mode", "inplace", "{args}", "{files}"],
         check=["fourmolu", "--mode", "check", "{args}", "{files}"], bin="fourmolu", rule_args={"joiner": " "},
         install=[gh("fourmolu/fourmolu", "v0.21.0.0", "fourmolu-{ver}-linux-{arch}.zip", ["fourmolu"],
                     arch=A_X86ARM)],
         defaults={"--indentation": 4, "--column-limit": "none"}, license="BSD-3-Clause")
lint_tool("hlint", "HLint", ["hlint", "{args}", "{files}"], bin="hlint",
          rule_args={"joiner": "="},
          install=[gh("ndmitchell/hlint", "v3.10", "hlint-{ver}-{arch}-linux.tar.gz", ["hlint"],
                      arch={"amd64": "x86_64"})], license="BSD-3-Clause")
lang("haskell", "Haskell", ext=[".hs", ".lhs", ".hs-boot", ".hsc"], shebang=[r"\b(runhaskell|stack|cabal)\b"],
     tools=["fourmolu", "hlint"], basic=lex(["--"], [("{-", "-}")], strings=('"',), nested=True))
lang("cabal", "Cabal package files", kind="config", ext=[".cabal"], names=["cabal.project"], basic=PLAIN,
     candidates=["cabal-fmt"])
syntax_tool("ocaml-parse", "ocamlc -stop-after parsing", ["ocamlc", "-stop-after", "parsing", "-c", "{file}"],
            bin="ocamlc", needs=["ocaml"], batch=False, cwd="tmp")
lang("ocaml", "OCaml", ext=[".ml", ".mli", ".mll", ".mly"], shebang=[r"\bocaml\b"], tools=["ocaml-parse"],
     basic=ML, candidates=["ocamlformat (opam only)"])
lang("reason", "ReasonML / ReScript", ext=[".re", ".rei", ".res", ".resi"], basic=C_LIKE,
     candidates=["rescript format (npm rescript)"])
lang("sml", "Standard ML", ext=[".sml", ".fun"], basic=ML)
fmt_tool("elm-format", "elm-format", ["elm-format", "--yes", "{files}"], check=["elm-format", "--validate", "{files}"],
         bin="elm-format",
         install=[gh("avh4/elm-format", "0.8.8", "elm-format-{ver}-linux-{arch}.tgz", ["elm-format"],
                    arch={"amd64": "x64", "arm64": "aarch64"})])
lang("elm", "Elm", ext=[".elm"], tools=["elm-format"], basic=lex(["--"], [("{-", "-}")], strings=('"""', '"'),
                                                                  nested=True))
fmt_tool("purs-tidy", "purs-tidy", ["purs-tidy", "format-in-place", "{files}"], check=["purs-tidy", "check", "{files}"],
         bin="purs-tidy", needs=["node"], install=[npm("purs-tidy@0.11.1")])
lang("purescript", "PureScript", ext=[".purs"], tools=["purs-tidy"],
     basic=lex(["--"], [("{-", "-}")], strings=('"""', '"'), nested=True))
fmt_tool("erlfmt", "erlfmt", ["erlfmt", "--write", "{files}"], check=["erlfmt", "--check", "{files}"], bin="erlfmt",
         needs=["erlang"], install=[script(r'''
set -euo pipefail
curl -fsSL --retry 3 https://github.com/erlang/rebar3/releases/download/3.27.1/rebar3 -o /opt/qs/bin/rebar3 && chmod +x /opt/qs/bin/rebar3
rm -rf /tmp/erlfmt && git clone --depth 1 --branch v1.8.0 https://github.com/WhatsApp/erlfmt /tmp/erlfmt
cd /tmp/erlfmt && HOME=/tmp /opt/qs/bin/rebar3 as release escriptize && install -m 0755 _build/release/bin/erlfmt /opt/qs/bin/erlfmt
rm -rf /tmp/erlfmt
''')])
lint_tool("erlc", "erlc -Wall", ["erlc", "-Wall", "-o", "{tmp}", "{files}"], bin="erlc", needs=["erlang"],
          skip_on=[r"can't find include (lib|file)"], skip_why="includes from other applications")
lang("erlang", "Erlang", ext=[".erl", ".hrl", ".escript", ".app.src"], names=["rebar.config", "sys.config"],
     shebang=[r"\bescript\b"], tools=["erlfmt", "erlc"],
     basic=lex(["%"], [], strings=('"', "'"), char_prefix="$"),
     subtypes=[subtype("config", "Erlang terms file", globs=["*.app.src", "rebar.config", "sys.config"],
                       exclude_tools=["erlc"])])
syntax_tool("elixir-parse", "Code.string_to_quoted!", ["elixir", "-e",
                                                        "for f <- System.argv(), do: Code.string_to_quoted!(File.read!(f), file: f)",
                                                        "{files}"], bin="elixir", needs=["elixir"])
fmt_tool("mix-format", "mix format", ["mix", "format", ["--dot-formatter", "{config}"], "{files}"],
         check=["mix", "format", "--check-formatted", ["--dot-formatter", "{config}"], "{files}"], bin="mix",
         needs=["elixir"], cwd="tmp", config={"file": ".formatter.exs", "format": "exs"},
         defaults={"line_length": 98}, env={"MIX_HOME": "/tmp/mix", "HEX_OFFLINE": "1"},
         notes="uses the generated .formatter.exs, never the project one (its plugins need deps)")
lang("elixir", "Elixir", ext=[".ex", ".exs", ".heex", ".leex"], shebang=[r"\belixir\b"],
     tools=["elixir-parse", "mix-format"], basic=lex(["#"], [], strings=('"""', '"', "'")),
     subtypes=[subtype("heex", "HEEx template", globs=["*.heex", "*.leex"], exclude_tools=["elixir-parse"])],
     candidates=["credo (needs the Mix project and deps)"])
fmt_tool("gleam-format", "gleam format", ["gleam", "format", "{files}"], check=["gleam", "format", "--check", "{files}"],
         bin="gleam", install=[gh("gleam-lang/gleam", "v1.19.1", "gleam-{tag}-{arch}-unknown-linux-musl.tar.gz",
                                  ["gleam"], arch=A_X86)])
lang("gleam", "Gleam", ext=[".gleam"], tools=["gleam-format"], basic=lex(["//"], [], strings=('"',)))
syntax_tool("prolog-read", "SWI-Prolog read_term", ["swipl", "{suite}/engine/helpers/qs_check.pl", "--", "{files}"],
            bin="swipl", needs=["swipl"])
lang("prolog", "Prolog", ext=[".pl", ".P", ".prolog"],
     probe=[probe(r"^:-\s*(module|use_module|dynamic|initialization|discontiguous)\b", 10),
            probe(r"^[a-z]\w*(\([^)]*\))?\s*:-", 5)],
     shebang=[r"\bswipl\b"], tools=["prolog-read"], basic=lex(["%"], [("/*", "*/")], strings=('"', "'")),
     marker={"modeline": "% -*- mode: prolog -*-"})

# ------------------------------------------------------------------ other programming languages

lint_tool("solhint", "Solhint", ["solhint", "--formatter", "unix", ["--config", "{config}"], "{files}"],
          bin="solhint", needs=["node"], install=[npm("solhint@6.2.5")],
          config={"file": ".solhint.json", "format": "json"},
          defaults={"extends": "solhint:recommended",
                    "rules": {"quotes": "off", "max-line-length": "off", "no-trailing-whitespace": "off"}},
          notes="layout rules off: Prettier (solidity plugin) owns them")
lang("solidity", "Solidity", ext=[".sol"], tools=["prettier", "solhint"], basic=C_LIKE)
MISS_HIT = pip("miss_hit==0.9.44", "mh_style", "mh_lint")
fmt_tool("mh-style", "MISS_HIT mh_style --fix", ["mh_style", "--fix", "--brief", "{args}", "{files}"], check="diff",
         bin="mh_style", install=[MISS_HIT], success_fix=[0, 1], rule_args={"joiner": " "}, defaults={"--octave": False})
lint_tool("mh-lint", "MISS_HIT mh_lint", ["mh_lint", "--brief", "{args}", "{files}"], bin="mh_lint",
          install=[MISS_HIT], rule_args={"joiner": " "}, defaults={"--octave": False})
lang("matlab", "MATLAB / Octave", ext=[".m", ".mlx"],
     probe=[probe(r"^\s*function\s+(\[[^\]]*\]\s*=\s*|\w+\s*=\s*)?\w+\s*\(", 5), probe(r"^\s*%", 2),
            probe(r"^\s*end\s*$", 1)],
     tools=["mh-style", "mh-lint"], basic=lex(["%"], [("%{", "%}")], strings=('"',), brackets="()[]{}"),
     marker={"modeline": "% -*- mode: matlab -*-"})
lang("mathematica", "Wolfram Language", ext=[".wl", ".wls", ".nb"], shebang=[r"\bwolframscript\b"],
     basic=lex([], [("(*", "*)")], strings=('"',), nested=True))
lint_tool("sas-lint", "@sasjs/lint", ["node", "{suite}/engine/js/qs-node.mjs", "lint-sas", "{files}"], bin="node",
          cwd="npm", needs=["node"], install=[npm("@sasjs/lint@4.1.3")])
lang("sas", "SAS", ext=[".sas"], tools=["sas-lint"], basic=lex([], [("/*", "*/")], strings=('"', "'"), brackets="()"))
lang("abap", "ABAP", ext=[".abap"], basic=lex(['"'], [], strings=("'", "`"), brackets=""),
     candidates=["abaplint (needs an abaplint.json project config)"])
lang("vba", "VBA / VB6", ext=[".bas", ".cls", ".frm", ".vba", ".vbs"],
     probe=[probe(r"^Attribute VB_\w+|^VERSION \d\.\d+ CLASS", 10), probe(r"^\s*(Option Explicit|Sub |Function )", 3)],
     basic=lex(["'"], [], strings=('"',), escape="", brackets="()"), marker={"modeline": "' -*- mode: vba -*-"})
lang("haxe", "Haxe", ext=[".hx", ".hxml"], basic=C_LIKE, candidates=["haxe-formatter", "checkstyle for Haxe"])
lang("actionscript", "ActionScript", ext=[".as"], basic=C_LIKE)
lang("coldfusion", "ColdFusion", ext=[".cfm", ".cfc", ".cfml"], basic=dict(PLAIN, brackets=""))
lang("smalltalk", "Smalltalk", ext=[".st"], basic=lex([], [('"', '"')], strings=("'",), escape="", brackets="()[]"))
lang("forth", "Forth", ext=[".fth", ".4th", ".forth"], basic=dict(PLAIN, brackets=""))
for _lid, _name, _ext, _lex in (("lean", "Lean", [".lean"], lex(["--"], [("/-", "-/")], strings=('"',), nested=True)),
                                ("coq", "Coq / Rocq", [".v"], ML), ("agda", "Agda", [".agda"],
                                                                   lex(["--"], [("{-", "-}")], strings=('"',), nested=True)),
                                ("idris", "Idris", [".idr", ".lidr"], lex(["--"], [("{-", "-}")], strings=('"',),
                                                                       nested=True))):
    lang(_lid, _name, ext=_ext, basic=_lex,
         probe=[probe(r"^\s*(Theorem|Lemma|Proof|Qed|Definition|Inductive|Require)\b", 10)] if _lid == "coq" else (),
         marker={"modeline": "(* -*- mode: coq -*- *)"} if _lid == "coq" else None)
syntax_tool("wat2wasm", "wat2wasm (parse)", ["wat2wasm", "--output=/dev/null", "{file}"], bin="wat2wasm",
            install=[apt("wabt")], batch=False)
lang("wasm-text", "WebAssembly text", ext=[".wat", ".wast"], tools=["wat2wasm"],
     basic=lex([";;"], [("(;", ";)")], strings=('"',), nested=True))
lang("llvm-ir", "LLVM IR", ext=[".ll"], basic=lex([";"], [], strings=('"',)))
GDTOOLKIT = pip("gdtoolkit==4.5.0", "gdformat", "gdlint")
fmt_tool("gdformat", "gdformat", ["gdformat", "{files}"], check=["gdformat", "--check", "{files}"], bin="gdformat",
         install=[GDTOOLKIT])
lint_tool("gdlint", "gdlint", ["gdlint", "{files}"], bin="gdlint", install=[GDTOOLKIT])
lang("gdscript", "GDScript (Godot 4)", ext=[".gd"], tools=["gdformat", "gdlint"],
     basic=lex(["#"], [], strings=('"""', '"', "'")))
lang("godot-resource", "Godot scenes/resources", kind="data", ext=[".tscn", ".tres", ".godot"], basic=PLAIN)
