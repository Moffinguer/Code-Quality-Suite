"""2.1 additions: tools for languages that only had the built-in fallback, and missing roles.

Every tool here was run in a sandbox on a valid and a broken sample (research notes:
docs/LANGUAGES.md "Not included" lists what was rejected and why). Heavy or noisy tools are
opt-in (default_enabled=False): they are installed only once the rules file enables them.
Helpers live in engine/helpers (qs_parse.py, qs_check.rb, qs_check.php, FtlCheck.java...) and
engine/js/qs-node.mjs.
"""
from core import (A_X64, A_X86, apt, deep_tool, extend, fmt_tool, gh, jar, lint_tool, npm, phar, pip, script,
                  subtype, syntax_tool, tool, url)

H = "{suite}/engine/helpers"
NODE = ["node", "{suite}/engine/js/qs-node.mjs"]
PMD_URL = ("https://github.com/pmd/pmd/releases/download/pmd_releases%2F7.28.0/pmd-dist-7.28.0-bin.zip")
PMD = url(PMD_URL, ["pmd"], arch=None)
WASM_TOOLS = gh("bytecodealliance/wasm-tools", "v1.261.0", "wasm-tools-{ver}-{arch}-linux.tar.gz", ["wasm-tools"])
SCHEMAT = gh("raviqqe/schemat", "v0.5.12", "schemat_{ver}_linux_{arch}.tar.gz", ["schemat"], arch={"amd64": "amd64"})
JSB = npm("js-beautify@2.0.3")
TS_PY = pip("tree-sitter==0.26.0", "qs-py-ts=bin/python3")
# why a script: the grammar pack is .tar.zst (needs zstd) and only 8 of its ~170 grammars are kept
TS_LIBS = script(r'''
set -euo pipefail
d=/opt/tree-sitter-libs; [ -f "$d/.v1.21.3" ] && exit 0
a=$(uname -m); t=$(mktemp -d)
curl -fsSL --retry 3 "https://github.com/xberg-io/tree-sitter-language-pack/releases/download/v1.21.3/parsers-linux-$a.tar.zst" -o "$t/p.tar.zst"
tar --zstd -xf "$t/p.tar.zst" -C "$t"
mkdir -p "$d"
for l in java rust solidity erlang apex dart scala clojure; do
  find "$t" -name "libtree_sitter_$l.so" -exec install -m 0644 {} "$d/" \; -quit
done
touch "$d/.v1.21.3"; rm -rf "$t"
''')

# ------------------------------------------------------------------ universal syntax (tree-sitter)
# why only these: zero false positives on large real corpora (Java 1385 files, Rust 634...);
# Kotlin, C#, Swift, Groovy, CSS... gave false positives, so their formatter stays the parser.
for _lid, _ts in (("java", "java"), ("rust", "rust"), ("solidity", "solidity"), ("erlang", "erlang"),
                  ("apex", "apex"), ("dart", "dart"), ("scala", "scala"), ("clojure", "clojure")):
    syntax_tool(f"ts-syntax-{_lid}", f"tree-sitter parse ({_ts})",
                ["qs-py-ts", "-I", f"{H}/qs_parse.py", "ts", _ts, "{files}"], bin="qs-py-ts",
                install=[apt("zstd"), TS_PY, TS_LIBS], env={"TS_LIBS": "/opt/tree-sitter-libs"},
                homepage="https://tree-sitter.github.io", license="MIT",
                notes="parse only (ERROR and MISSING nodes); fast and exact, runs before the formatter")
    extend(_lid, [f"ts-syntax-{_lid}"])

# ------------------------------------------------------------------ web templates

syntax_tool("stylus-parse", "stylus parser", NODE + ["syntax-stylus", "{files}"], bin="node", needs=["node"],
            install=[npm("stylus@0.64.0")], notes="parse only: @import is not resolved")
fmt_tool("stylus-supremacy", "stylus-supremacy", ["stylus-supremacy", "format", "{files}", ["-p", "{config}"], "--replace"],
         check=["stylus-supremacy", "format", "{file}", ["-p", "{config}"], "--compare"], batch=False,
         bin="stylus-supremacy", needs=["node"], install=[npm("stylus-supremacy@5.0.3")],
         config={"file": "stylus-supremacy.json", "format": "json", "base": "web/stylus-supremacy.json"},
         homepage="https://thisismanta.github.io/stylus-supremacy", license="MIT",
         notes="indentation syntax kept (no braces, colons or semicolons added)")
extend("stylus", ["stylus-parse", "stylus-supremacy"], candidates=[])

syntax_tool("haml-check", "Haml parse + compile", ["ruby", f"{H}/qs_check.rb", "haml", "{files}"], bin="ruby",
            needs=["ruby"], install=[apt("ruby-haml")],
            notes="`haml --check` misses errors (Haml 6 defers them to run time); this compiles explicitly")
lint_tool("haml-lint", "haml-lint", ["haml-lint", "{files}"], bin="haml-lint", needs=["ruby"],
          install=[script("gem install --no-document -i /opt/gems haml_lint -v 0.78.0")], default_enabled=False,
          success=[0], homepage="https://github.com/sds/haml-lint", license="MIT", notes="opt-in (RuboCop-based)")
extend("haml", ["haml-check", "haml-lint"], candidates=[])
syntax_tool("slim-check", "Slim precompile + compile", ["ruby", f"{H}/qs_check.rb", "slim", "{files}"], bin="ruby",
            needs=["ruby"], install=[apt("ruby-slim")])
lint_tool("slim-lint", "slim-lint", ["slim-lint", "{files}"], bin="slim-lint", needs=["ruby"],
          install=[script("gem install --no-document -i /opt/gems slim_lint -v 0.37.0")], default_enabled=False,
          homepage="https://github.com/sds/slim-lint", license="MIT", notes="opt-in")
extend("slim", ["slim-check", "slim-lint"], candidates=[])

lint_tool("pmd-velocity", "PMD (Velocity rules)",
          ["pmd", "check", "--no-cache", "--no-progress", "--format", "text", "--force-language", "velocity",
           ["-R", "{config}"], "{args}", "-d", "{files}"], bin="pmd", needs=["java"], install=[PMD],
          config={"file": "pmd-velocity.xml", "format": "pmd", "base": "pmd-velocity.xml"},
          notes="also reports templates that do not parse (exit 5)")
extend("velocity", ["pmd-velocity"])

syntax_tool("ftl-parse", "FreeMarker parse", ["java", "-cp", "/usr/share/java/freemarker.jar", f"{H}/FtlCheck.java",
                                              "{files}"],
            bin="java", needs=["jdk"], install=[apt("libfreemarker-java")],
            notes="parse only; includes, macros and data are not resolved")
extend("freemarker", ["ftl-parse"])

syntax_tool("smarty-compile", "Smarty compile", ["php", f"{H}/qs_check.php", "smarty", "{files}"], bin="php",
            needs=["php"], install=[apt("smarty4")], notes="compile only; unknown plugins/modifiers are accepted")
JSB_CFG = {"file": "jsbeautify.json", "format": "json", "base": "web/jsbeautify-templates.json"}
fmt_tool("html-beautify-smarty", "js-beautify (html, smarty)", ["html-beautify", "--config", "{config}", "-r", "{files}"],
         check="diff", bin="html-beautify", needs=["node"], install=[JSB], default_enabled=False,
         config=JSB_CFG, defaults={"html": {"templating": ["smarty"]}},
         notes="opt-in: re-indents the HTML around template tags; script/style kept verbatim")
fmt_tool("html-beautify-erb", "js-beautify (html, <% %> templates)",
         ["html-beautify", "--config", "{config}", "-r", "{files}"], check="diff", bin="html-beautify",
         needs=["node"], install=[JSB], default_enabled=False, config=JSB_CFG,
         defaults={"html": {"templating": ["erb"]}},
         notes="opt-in (ASP, EJS): code inside <% %> is kept verbatim. Not for JSP (corrupts nested quotes)")
extend("smarty", ["smarty-compile", "html-beautify-smarty"])
extend("asp", ["html-beautify-erb"])
extend("ejs", ["html-beautify-erb"])

lint_tool("cflint", "CFLint", ["cflint", "-q", "-e", "-text", "-stdout", ["-configfile", "{config}"], "-file",
                               "{files_csv}"],
          bin="cflint", needs=["java"],
          install=[jar("https://github.com/cflint/CFLint/releases/download/CFLint-1.5.0/CFLint-1.5.0-all.jar", "cflint")],
          config={"file": "cflintrc.json", "format": "json", "base": "cfml/cflintrc.json"},
          fail_regex=r"Severity:(ERROR|WARNING)", homepage="https://github.com/cflint/CFLint", license="BSD-3-Clause",
          notes="always exits 0: errors are read from its output; parse errors are reported too")
extend("coldfusion", ["cflint"])

HERB_LINT = npm("@herb-tools/linter@0.11.0")
lint_tool("herb-lint", "Herb linter (HTML+ERB)", ["herb-lint", "--force", "--simple", "--no-github", "{files}"],
          bin="herb-lint", needs=["node"], install=[HERB_LINT], homepage="https://herb-tools.dev", license="MIT",
          notes="real HTML+ERB parser (Ruby parsed with prism); --force: plain *.erb names are skipped otherwise")
fmt_tool("herb-format", "Herb formatter", ["herb-format", "--force", "{files}"],
         check=["herb-format", "--force", "--check", "{files}"], bin="herb-format", needs=["node"],
         install=[npm("@herb-tools/formatter@0.11.0")], default_enabled=False,
         notes="opt-in: upstream marks it as an experimental preview")
extend("erb", ["herb-lint", "herb-format"], candidates=["erb_lint (gem)", "htmlbeautifier (gem)"])

syntax_tool("mermaid-validate", "mermaid parser (jsdom)", ["mermaid-validate", "-q", "{file}"], batch=False,
            bin="mermaid-validate", needs=["node"], install=[npm("@zabaca/mermaid-validate@1.0.1")],
            default_enabled=False, notes="opt-in (179 MB): official mermaid.parse without a browser")
extend("mermaid", ["mermaid-validate"], candidates=["mermaid-cli (renders; needs headless Chromium, ~400 MB)"])

lint_tool("org-lint", "org-lint (Emacs batch)", ["emacs", "-Q", "--batch", "-l", f"{H}/qs-org-lint.el", "{files}"],
          bin="emacs", install=[apt("emacs-nox")], default_enabled=False, notes="opt-in (~120 MB Emacs)")
extend("org", ["org-lint"])

PANACHE = gh("jolars/panache", "v3.15.0", "panache-{arch}-unknown-linux-musl.tar.gz", ["panache"])
lint_tool("panache-lint", "panache lint", ["panache", "lint", "{files}"], bin="panache", install=[PANACHE],
          homepage="https://github.com/jolars/panache", license="MIT", notes="Quarto / R Markdown / Pandoc markdown")
fmt_tool("panache-format", "panache format", ["panache", "format", ["--config", "{config}"], "{files}"],
         check=["panache", "format", ["--config", "{config}"], "--check", "{files}"], bin="panache",
         install=[PANACHE], default_enabled=False, config={"file": "panache.toml", "format": "toml",
                                                          "base": "r/panache.toml"},
         notes="opt-in: moves chunk options to '#|' lines (knitr >= 1.35) and rewrites hard breaks as '\\'")
extend("rmarkdown", ["panache-lint", "panache-format"])

lint_tool("pmd-jsp", "PMD (JSP rules)",
          ["pmd", "check", "--no-cache", "--no-progress", "--no-fail-on-error", "--format", "text",
           ["-R", "{config}"], "{args}", "-d", "{files}"], bin="pmd", needs=["java"], install=[PMD],
          config={"file": "pmd-jsp.xml", "format": "pmd", "base": "pmd-jsp.xml"},
          notes="--no-fail-on-error: PMD's JSP grammar rejects some valid JSP (scriptlets inside start tags); "
                "those files are skipped, not failed")
fmt_tool("djlint-format-jsp", "djLint (reformat JSP)", ["djlint", "--reformat", "--quiet", "{args}", "{files}"],
         check=["djlint", "--check", "--quiet", "{args}", "{files}"], bin="djlint",
         install=[pip("djlint==1.46.4", "djlint")], rule_args={"joiner": "="}, success_fix=[0, 1],
         defaults={"--profile": "html", "--indent": 2}, default_enabled=False,
         notes="opt-in: the only formatter that kept JSP semantics in tests; drops type=\"text/javascript\" and "
               "lowercases method=POST (same meaning in HTML5)")
extend("jsp", ["pmd-jsp", "djlint-format-jsp"],
       notes="balanced <% %> check, PMD JSP rules; djLint formatting is opt-in",
       candidates=["Jasper JspC translation (strongest JSP check; needs every taglib jar of the project)"])

lint_tool("checkstyle-translation", "Checkstyle Translation (i18n bundles)",
          ["checkstyle", ["-c", "{config}"], "{dirs}"], bin="checkstyle", needs=["java"],
          install=[jar("https://github.com/checkstyle/checkstyle/releases/download/checkstyle-14.3.0/"
                       "checkstyle-14.3.0-all.jar", "checkstyle", java_opts=["-Dfile.encoding=UTF-8"])],
          config={"file": "checkstyle-translation.xml", "format": "checkstyle", "base": "checkstyle-translation.xml"},
          env={"JAVA_TOOL_OPTIONS": "-Dcheckstyle.charset={charset}"}, default_enabled=False,
          notes="opt-in: keys missing in a locale variant (messages_es.properties vs messages.properties); "
                "checks whole directories so every file of a bundle is compared")
extend("properties", ["checkstyle-translation"])

# ------------------------------------------------------------------ Lisp family, functional, proof

syntax_tool("raku-c", "raku -c (compile only)", ["raku", "-c", "{file}"], batch=False, bin="raku",
            install=[apt("rakudo")], skip_on=[r"Could not find \S+ in"], skip_why="modules not installed here",
            notes="BEGIN blocks run at compile time (inside the offline, read-only container)")
extend("raku", ["raku-c"], candidates=[])
syntax_tool("schemat-parse", "schemat (S-expression parse)", ["schemat", "--check", "{files}"], bin="schemat",
            install=[SCHEMAT], success=[0, 1], fail_regex=r"^ERROR\t",
            homepage="https://github.com/raviqqe/schemat", license="Unlicense",
            notes="bracket/string/comment structure of any Lisp dialect; formatting differences are ignored; amd64")
fmt_tool("schemat", "schemat", ["schemat", "{files}"], check=["schemat", "--check", "{files}"], bin="schemat",
         install=[SCHEMAT], default_enabled=False, notes="opt-in: fixed, not dialect-idiomatic style")
for _lid in ("emacs-lisp", "racket"):
    extend(_lid, ["schemat-parse"])
extend("common-lisp", ["schemat-parse", "schemat"])
extend("scheme", ["schemat-parse", "schemat"])

RESCRIPT = npm("rescript@12.3.1")
syntax_tool("rescript-parse", "ReScript bsc -only-parse", ["bsc", "-only-parse", "{file}"], batch=False, bin="bsc",
            needs=["node"], install=[RESCRIPT])
fmt_tool("rescript-format", "rescript format", ["rescript", "format", "{files}"],
         check=["rescript", "format", "--check", "{files}"], bin="rescript", needs=["node"], install=[RESCRIPT])
extend("reason", subtypes=[subtype("rescript", "ReScript", globs=["*.res", "*.resi"],
                                   tools=["rescript-parse", "rescript-format"])],
       candidates=["refmt for .re/.rei (Reason 3.6, unmaintained, x64 only)"])

SMLFMT = script(r'''
set -euo pipefail
command -v smlfmt >/dev/null && exit 0
t=$(mktemp -d); apt-get install -y -qq --no-install-recommends mlton make >/dev/null
git clone -q --depth 1 --branch v1.3.0 https://github.com/shwestrick/smlfmt "$t/s" && make -C "$t/s" smlfmt >/dev/null
install -m 0755 "$t/s/smlfmt" /opt/qs/bin/smlfmt; rm -rf "$t"; apt-get purge -y -qq mlton >/dev/null || true
''')
syntax_tool("smlfmt-parse", "smlfmt --read-only", ["smlfmt", "--read-only", "{files}"], bin="smlfmt",
            install=[SMLFMT], default_enabled=False, notes="opt-in: built from source with MLton (amd64)")
fmt_tool("smlfmt", "smlfmt", ["smlfmt", "--force", "{files}"], check=["smlfmt", "--check", "{files}"], bin="smlfmt",
         install=[SMLFMT], default_enabled=False, notes="opt-in; never without --force/--check (it prompts)")
extend("sml", ["smlfmt-parse", "smlfmt"])

syntax_tool("agda-scope", "agda --only-scope-checking", ["agda", "--no-libraries", "--only-scope-checking", "{file}"],
            batch=False, cwd="tmp", bin="agda",
            install=[gh("agda/agda", "v2.8.0.2", "Agda-{tag}-linux.tar.xz", ["agda"], arch={"amd64": ""})],
            default_enabled=False, notes="opt-in (55 MB, amd64); the standard library is not installed")
extend("agda", ["agda-scope"])

fmt_tool("cabal-gild", "cabal-gild", ["cabal-gild", "--mode", "format", "{file}"],
         check=["cabal-gild", "--mode", "check", "{file}"], batch=False, bin="cabal-gild",
         install=[gh("tfausak/cabal-gild", "1.8.4.2", "cabal-gild-{tag}-linux-{arch}.tar.gz", ["cabal-gild"],
                     arch=A_X64)],
         homepage="https://github.com/tfausak/cabal-gild", license="MIT")
extend("cabal", ["cabal-gild"], candidates=[])

syntax_tool("wl-parse", "Mathics3 parser", ["qs-py-mathics", "-I", f"{H}/qs_parse.py", "wl", "{files}"],
            bin="qs-py-mathics", install=[pip("Mathics3==10.0.1", "qs-py-mathics=bin/python3")],
            default_enabled=False, notes="opt-in (~390 MB): open-source WL parser, nothing is evaluated")
extend("mathematica", ["wl-parse"])

tool("ocp-indent", "format", "ocp-indent", {"stdout": ["ocp-indent", "{file}"]}, bin="ocp-indent",
     install=[apt("ocp-indent")], notes="indentation only: never re-breaks lines")
extend("ocaml", ["ocp-indent"], candidates=["ocamlformat (opam only; needs a per-project .ocamlformat)"])

lint_tool("credo", "Credo", ["credo", "suggest", "--strict", "--format", "oneline", "{files}"], bin="credo",
          needs=["elixir"], default_enabled=False,
          install=[script(r'''
set -euo pipefail
command -v credo >/dev/null && exit 0
t=$(mktemp -d); export HOME=$t MIX_HOME=$t/mix HEX_HOME=$t/hex
git clone -q --depth 1 --branch v1.7.19 https://github.com/rrrene/credo "$t/c" && cd "$t/c"
mix local.hex --force >/dev/null && MIX_ENV=prod mix deps.get >/dev/null && MIX_ENV=prod mix escript.build >/dev/null
install -m 0755 credo /opt/qs/bin/credo; rm -rf "$t"
''')], notes="opt-in: escript built from the release tag; syntax errors stay with elixir-parse")
extend("elixir", ["credo"], candidates=[])

lint_tool("ameba", "Ameba", ["ameba", "--no-color", "{files}"], bin="ameba",
          install=[gh("crystal-ameba/ameba", "v1.7.0", "ameba-{ver}-linux-musl-{arch}.tar.gz", ["ameba"])],
          homepage="https://github.com/crystal-ameba/ameba", license="MIT", notes="includes Lint/Syntax")
extend("crystal", ["ameba"], candidates=[])

lint_tool("pl-lint", "SWI-Prolog static lint", ["swipl", "-q", "-f", "none", "-g", "main", "-t", "halt",
                                                f"{H}/qs_pl_lint.pl", "--", "{files}"],
          bin="swipl", needs=["swipl"], level="strict",
          notes="singleton variables and undefined predicates; nothing is executed (strict: dynamic calls can "
                "look undefined)")
extend("prolog", ["pl-lint"])

lint_tool("elvis", "Elvis", ["elvis", "rock", ["--config", "{config}"], "{files}"], bin="elvis", needs=["erlang"],
          config={"file": "elvis.config", "format": "text", "base": "erlang/elvis.config"}, default_enabled=False,
          install=[script(r'''
set -euo pipefail
command -v elvis >/dev/null && exit 0
t=$(mktemp -d); export HOME=$t
curl -fsSL --retry 3 -o "$t/rebar3" https://github.com/erlang/rebar3/releases/download/3.24.0/rebar3 && chmod +x "$t/rebar3"
git clone -q --depth 1 --branch 4.1.1-otp24 https://github.com/inaka/elvis "$t/e" && cd "$t/e" && "$t/rebar3" escriptize >/dev/null
install -m 0755 _build/default/bin/elvis /opt/qs/bin/elvis; rm -rf "$t"
''')], notes="opt-in; without a config it silently checks nothing, so one is always passed")
extend("erlang", ["elvis"])

# ------------------------------------------------------------------ systems, shaders, low level

GLSLA = gh("nolanderc/glsl_analyzer", "v1.7.1", "{arch}-linux-musl.zip", ["glsl_analyzer"])
syntax_tool("glsl-analyzer-parse", "glsl_analyzer --parse-file", ["glsl_analyzer", "--parse-file", "{file}"],
            batch=False, bin="glsl_analyzer", install=[GLSLA], license="GPL-3.0",
            notes="stage-agnostic parse (works on shader chunks without main/#version)")
tool("glsl-analyzer-format", "format", "glsl_analyzer --format", {"stdout": ["glsl_analyzer", "--format", "{file}"]},
     bin="glsl_analyzer", install=[GLSLA],
     notes="refuses (and changes nothing) when #ifdef switches a function header")
extend("glsl-generic", ["glsl-analyzer-parse", "glsl-analyzer-format"])
extend("glsl", ["glsl-analyzer-format"])

fmt_tool("clang-format-hlsl", "clang-format (HLSL as C++)",
         ["clang-format", "-i", "--style=file:{config}", "--assume-filename=x.cpp", "{files}"],
         check=["clang-format", "--dry-run", "--Werror", "--style=file:{config}", "--assume-filename=x.cpp", "{files}"],
         bin="clang-format", install=[pip("clang-format==23.1.3", "clang-format")],
         config={"file": ".clang-format", "format": "yaml", "base": "c/clang-format"})
syntax_tool("glslang-hlsl", "glslangValidator (HLSL front end)",
            ["glslangValidator", "-V", "-D", "-e", "main", "-S", "frag", "-o", "/dev/null", "{file}"], batch=False,
            bin="glslangValidator", install=[apt("glslang-tools")], default_enabled=False,
            notes="opt-in: lags DXC (no templates, partial SM6)")
extend("hlsl", ["glslang-hlsl", "clang-format-hlsl"], candidates=["DXC (reference compiler; 515 MB download, amd64)"])

V = url("https://github.com/vlang/v/releases/download/0.5.2/v_linux{arch}.zip", ["v"],
        arch={"amd64": "", "arm64": "_arm64"})
V_PREP = script("HOME=/tmp VMODULES=/tmp/.vmodules /opt/qs/bin/v fmt -help >/dev/null 2>&1; "
                "HOME=/tmp VMODULES=/tmp/.vmodules /opt/qs/bin/v vet -help >/dev/null 2>&1; "
                "chmod -R a+rX /opt/qs/pkg || true")
V_ENV = {"HOME": "/tmp", "VMODULES": "/tmp/.vmodules"}
syntax_tool("v-check-syntax", "v -check-syntax", ["v", "-check-syntax", "{file}"], batch=False, bin="v",
            install=[V, V_PREP], env=V_ENV, notes="~125 MB (the V compiler)")
fmt_tool("v-fmt", "v fmt", ["v", "fmt", "-w", "{files}"], check=["v", "fmt", "-verify", "{files}"], bin="v",
         install=[V, V_PREP], env=V_ENV)
lint_tool("v-vet", "v vet", ["v", "vet", "-W", "{files}"], bin="v", install=[V, V_PREP], env=V_ENV,
          default_enabled=False, notes="opt-in")
extend("v", ["v-check-syntax", "v-fmt", "v-vet"], candidates=[])

tool("odinfmt", "format", "odinfmt", {"stdout": ["odinfmt", "{file}"]}, bin="odinfmt",
     install=[gh("DanielGavin/ols", "dev-2026-08", "ols-{arch}-unknown-linux-gnu.zip",
                 ["odinfmt=odinfmt-{arch}-unknown-linux-gnu"], arch={"amd64": "x86_64", "arm64": "arm64"})],
     notes="from the ols monthly release; unparsable files are left untouched")
extend("odin", ["odinfmt"], candidates=["odin check -vet (~170 MB compiler)"])

syntax_tool("nasm-check", "nasm (parse/assemble to /dev/null)", ["nasm", "-f", "elf64", "-o", "/dev/null", "{file}"],
            batch=False, bin="nasm", install=[apt("nasm")], default_enabled=False,
            skip_on=[r"unable to open include file"], notes="opt-in: only for NASM-syntax x86 (.asm/.nasm)")
extend("assembly", subtypes=[subtype("nasm", "NASM source", globs=["*.asm", "*.nasm"], tools=["nasm-check"])])

syntax_tool("llvm-ir-check", "llvmlite parse + verify", ["qs-py-llvm", "-I", f"{H}/qs_parse.py", "llvm", "{files}"],
            bin="qs-py-llvm", install=[pip("llvmlite==0.50.0", "qs-py-llvm=bin/python3")], default_enabled=False,
            notes="opt-in (~170 MB, LLVM 22)")
extend("llvm-ir", ["llvm-ir-check"])

fmt_tool("gnatformat", "GNATformat", ["gnatformat", "--no-project", "{files}"],
         check=["gnatformat", "--no-project", "--check", "{files}"], bin="gnatformat",
         install=[gh("alire-project/GNAT-FSF-builds", "gnatformat-26.0-1", "gnatformat-{arch}-linux-26.0-1.tar.gz",
                     ["gnatformat"])],
         homepage="https://github.com/AdaCore/gnatformat", license="Apache-2.0 WITH LLVM-exception",
         notes="Alire community build; unparsable files are left untouched")
extend("ada", ["gnatformat"], candidates=[])

lint_tool("perlimports", "perlimports", ["perlimports", "--lint", "--no-config-file", "-f", "{file}"], batch=False,
          bin="perlimports", install=[apt("perlimports")], default_enabled=False,
          notes="opt-in: loads the modules it analyses (only installed ones are resolved)")
extend("perl", ["perlimports"], candidates=[])

lint_tool("zlint", "ZLint", ["zlint", "--no-summary", "--deny-warnings", ["-c", "{config}"], "{files}"], bin="zlint",
          install=[gh("DonIsaac/zlint", "v0.10.0", "zlint-linux-{arch}", ["zlint"])],
          config={"file": "zlint.json", "format": "json", "base": "zig/zlint.json"},
          homepage="https://github.com/DonIsaac/zlint", license="MIT", notes="never run `zlint update` (network)")
extend("zig", ["zlint"])

lint_tool("cobc-warnings", "cobc -Wextra", ["cobc", "-fsyntax-only", "-Wextra", "-Wno-terminator", "-Werror", "{file}"],
          batch=False, bin="cobc", install=[apt("gnucobol")], skip_on=[r"(copybook|COPY) .*not found", r"cannot find"],
          skip_why="copybooks not available in isolation")
extend("cobol", ["cobc-warnings"])

lint_tool("fpc-check", "Free Pascal (fpc -s)", ["fpc", "-s", "-vewn", "-Sew", "-FE{tmp}", "{file}"], batch=False,
          bin="fpc", install=[apt("fp-compiler", "fp-units-rtl")], default_enabled=False,
          skip_on=[r"Can't find unit"], skip_why="project units (VCL/FMX...) are not available",
          notes="opt-in (~80 MB)")
extend("pascal", ["fpc-check"])

# gawk --lint=invalid crashes (exit 2) on any '+' with gawk 5.2.1 (Ubuntu 24.04)
syntax_tool("gawk-parse2", "gawk parse (no execution)", ["gawk", "-o/dev/null", "-f", "{file}"], batch=False,
            bin="gawk", install=[apt("gawk")], notes="-o pretty-prints instead of running: nothing executes")
extend("awk", replace={"gawk-parse": "gawk-parse2"})

# ------------------------------------------------------------------ data, IDL, config

lint_tool("abaplint", "abaplint", ["python3", "-I", f"{H}/qs_parse.py", "abaplint", "abaplint", "{files}"],
          bin="abaplint", needs=["node"], install=[npm("@abaplint/cli@2.120.74")],
          homepage="https://abaplint.org", license="MIT",
          notes="files are staged as abapGit names (zfoo.prog.abap) with an offline config (no dependencies)")
extend("abap", ["abaplint"], candidates=[])

ZPA = gh("felipebz/zpa-cli", "3.2.1", "zpa-cli-{tag}.zip", ["zpa-cli"], arch=None)
ZPA_EXT = "pks,pkb,pls,plb,pck,prc,fnc,trg,tps,tpb,sql"
syntax_tool("zpa-syntax", "ZPA (PL/SQL parse)", ["zpa-cli", "--sources", ".", "--files", "{files_csv}", "--extensions",
                                                 ZPA_EXT, "--syntax-only", "--fail-on", "syntax"],
            bin="zpa-cli", needs=["java"], install=[ZPA], homepage="https://github.com/felipebz/zpa", license="LGPL-3.0")
lint_tool("zpa", "ZPA (PL/SQL rules)", ["zpa-cli", "--sources", ".", "--files", "{files_csv}", "--extensions", ZPA_EXT,
                                         "--fail-on", "major"],
          bin="zpa-cli", needs=["java"], install=[ZPA],
          notes="~40 Sonar-style rules without a server (unused variables, = NULL, SELECT *, COMMIT...)")
extend("plsql", ["zpa-syntax", "zpa"], candidates=[])

syntax_tool("thrift-check", "thrift compiler", ["thrift", "-r", "--gen", "json", "-out", "{tmp}", "{file}"], batch=False,
            bin="thrift", install=[apt("thrift-compiler")], skip_on=[r"Could not find include file"],
            skip_why="included files not available")
extend("thrift", ["thrift-check"])
syntax_tool("capnp-check", "capnp compile", ["sh", "-c", 'capnp compile -I /usr/include -o- "$1" >/dev/null', "sh",
                                            "{file}"],
            batch=False, bin="capnp", install=[apt("capnproto", "libcapnp-dev")])
extend("capnp", ["capnp-check"])
syntax_tool("flatc-check", "flatc --schema", ["flatc", "--schema", "-b", "-o", "{tmp}", "{file}"], batch=False,
            bin="flatc", install=[gh("google/flatbuffers", "v25.12.19", "Linux.flatc.binary.g++-13.zip", ["flatc"],
                                     arch={"amd64": ""})],
            notes="amd64 (no arm64 release asset)")
extend("flatbuffers", ["flatc-check"])
syntax_tool("asn1-parse", "asn1tools parse", ["qs-py-asn1", "-I", f"{H}/qs_parse.py", "asn1", "{files}"],
            bin="qs-py-asn1", install=[pip("asn1tools==0.169.0", "qs-py-asn1=bin/python3")])
extend("asn1", ["asn1-parse"])
syntax_tool("wit-check", "wasm-tools component wit", ["wasm-tools", "component", "wit", "{file}"], batch=False,
            bin="wasm-tools", install=[WASM_TOOLS],
            skip_on=[r"package '.*' not found", r"failed to resolve"], skip_why="dependencies (deps/) not present")
extend("wit", ["wit-check"])
syntax_tool("wasm-tools-parse", "wasm-tools parse", ["wasm-tools", "parse", "{file}", "-o", "/dev/null"], batch=False,
            bin="wasm-tools", install=[WASM_TOOLS], notes="current WAT incl. GC, SIMD and exceptions")
extend("wasm-text", replace={"wat2wasm": "wasm-tools-parse"})

lint_tool("cmake-lint", "cmake-lint (cmakelang)", ["cmake-lint", "{files}", ["--config-files", "{config}"]],
          bin="cmake-lint", install=[pip("cmakelang==0.6.13", "cmake-lint")],
          config={"file": "cmake-lint.json", "format": "json", "base": "cmake/cmake-lint.json"},
          notes="layout codes disabled: gersemi owns the layout")
extend("cmake", ["cmake-lint"], candidates=[])
lint_tool("desktop-file-validate", "desktop-file-validate", ["desktop-file-validate", "--no-hints", "{files}"],
          bin="desktop-file-validate", install=[apt("desktop-file-utils")])
extend("desktop-entry", ["desktop-file-validate"])
lint_tool("systemd-verify", "systemd-analyze verify", ["systemd-analyze", "verify", "--man=no", "{files:./}"],
          bin="systemd-analyze", install=[apt("systemd")], default_enabled=False,
          notes="opt-in: binaries named in ExecStart= must exist in the image")
extend("systemd", ["systemd-verify"])
lint_tool("asciidoctor-lint", "asciidoctor (warnings)",
          ["asciidoctor", "-v", "-S", "safe", "--failure-level=WARN", "-o", "/dev/null", "{file}"], batch=False,
          bin="asciidoctor", install=[apt("asciidoctor")])
extend("asciidoc", ["asciidoctor-lint"])
syntax_tool("bibclean", "bibclean (check only)", ["sh", "-c", 'bibclean -no-prettyprint < "$1" > /dev/null', "sh",
                                                 "{file}"],
            batch=False, bin="bibclean", install=[apt("bibclean")])
extend("bibtex", ["bibclean"])
syntax_tool("buf-build", "buf build", ["buf", "build", "{file}", "-o", "/dev/null"], batch=False, bin="buf",
            needs=["node"], install=[npm("@bufbuild/buf@1.73.0")],
            skip_on=[r"imported file does not exist"], skip_why="imports outside the module")
extend("protobuf", ["buf-build"])
syntax_tool("dockerfile-utils", "dockerfile-utils lint", ["dockerfile-utils", "lint", "{file}"], batch=False,
            bin="dockerfile-utils", needs=["node"], install=[npm("dockerfile-utils@0.16.3")])
extend("dockerfile", ["dockerfile-utils"])
syntax_tool("make-parse", "GNU make parse (dry run)",
            ["make", "-f", "{file}", "--no-print-directory", "-n", "-R", "SHELL=/bin/true", "--eval=__qs_parse__: ; @:",
             "__qs_parse__"], batch=False, cwd="file_dir", bin="make", install=[apt("make")],
            skip_on=[r"No such file or directory"], skip_why="included makefiles not available",
            notes="SHELL=/bin/true: $(shell ...) and recipes never execute")
extend("makefile", ["make-parse"])
syntax_tool("typst-compile", "typst compile", ["typst", "compile", "{file}", "/dev/null", "--format", "pdf"],
            batch=False, bin="typst",
            install=[gh("typst/typst", "v0.15.1", "typst-{arch}-unknown-linux-musl.tar.xz", ["typst"])],
            default_enabled=False, notes="opt-in (54 MB): compiles, so missing images/packages are reported too")
extend("typst", ["typst-compile"])
for _lid, _tid, _cmd, _inst in (
        ("textproto", "txtpbfmt", "txtpbfmt", "github.com/protocolbuffers/txtpbfmt/cmd/txtpbfmt@6e6d8ebdba957f6f62c4afbba7d0518606c509c0"),
        ("hcl", "hclfmt", "hclfmt", "github.com/hashicorp/hcl/v2/cmd/hclfmt@v2.25.0")):
    _go = script("export GOPATH=/tmp/go GOCACHE=/tmp/go-cache GOFLAGS= GOPROXY=https://proxy.golang.org,direct "
                 f"GOBIN=/opt/qs/bin; command -v {_cmd} >/dev/null || /usr/local/go/bin/go install {_inst}; "
                 "rm -rf /tmp/go /tmp/go-cache")
    if _tid == "txtpbfmt":
        fmt_tool(_tid, "txtpbfmt", ["txtpbfmt", "{files}"], check="diff", bin=_tid, needs=["go"], install=[_go],
                 default_enabled=False, notes="opt-in (needs the Go toolchain in the image); also the parser")
    else:
        fmt_tool(_tid, "hclfmt", ["hclfmt", "-w", "{file}"], check=["hclfmt", "-require-no-change", "{file}"],
                 batch=False, bin=_tid, needs=["go"], install=[_go], default_enabled=False,
                 notes="opt-in (needs the Go toolchain in the image); whitespace-only")
    extend(_lid, [_tid])

# ------------------------------------------------------------------ scripting and markup gaps

syntax_tool("sass-parse", "sass-parser (parse only)", NODE + ["syntax-sass", "{files}"], bin="node", needs=["node"],
            install=[npm("sass-parser@0.4.57")], notes="no @use/@import resolution: missing modules are not errors")
fmt_tool("sass-formatter", "sass-formatter", ["sass-formatter", "-w", "{files}"],
         check=["sass-formatter", "-ch", "{files}"], bin="sass-formatter", needs=["node"],
         install=[npm("sass-formatter@0.8.0")], notes="indentation and spacing only")
extend("sass", ["sass-formatter"], replace={"sass-compile": "sass-parse"})

lint_tool("coffeelint", "CoffeeLint", ["coffeelint", "{files}"], bin="coffeelint", needs=["node"],
          install=[npm("@coffeelint/cli@5.2.11")], notes="also reports compiler syntax errors")
extend("coffeescript", ["coffeelint"])
syntax_tool("cython-parse", "Cython parser", ["qs-py-cython", "-I", f"{H}/qs_parse.py", "cython", "{files}"],
            bin="qs-py-cython", install=[pip("Cython==3.3.0", "qs-py-cython=bin/python3")],
            notes="cython-lint skips unparsable files silently, so parsing is a separate step")
extend("cython", ["cython-parse"])
syntax_tool("mdx-parse", "@mdx-js/mdx compile", NODE + ["syntax-mdx", "{files}"], bin="node", needs=["node"],
            install=[npm("@mdx-js/mdx@3.1.1")], notes="Prettier does not detect MDX syntax errors")
extend("mdx", ["mdx-parse"])
syntax_tool("liquid-parse", "liquid-html-parser", NODE + ["syntax-liquid", "{files}"], bin="node", needs=["node"],
            install=[npm("@shopify/liquid-html-parser@2.10.2")])
extend("liquid", ["liquid-parse"])
syntax_tool("jinja-parse", "jinja2 parse", ["qs-py-jinja", "-I", f"{H}/qs_parse.py", "jinja", "{files}"],
            bin="qs-py-jinja", install=[pip("Jinja2==3.1.6", "qs-py-jinja=bin/python3")])
extend("jinja", ["jinja-parse"], subtypes=[subtype("django", "Django templates", globs=["*.djhtml", "*.dtl"],
                                                   exclude_tools=["jinja-parse"])])
TWIGCS = phar("https://github.com/VincentLanglet/Twig-CS-Fixer/releases/download/4.1.1/twig-cs-fixer.phar",
              "twig-cs-fixer")
syntax_tool("twig-parse", "Twig parse", ["php", f"{H}/qs_check.php", "twig", "/opt/qs/bin/twig-cs-fixer", "{files}"],
            bin="twig-cs-fixer", needs=["php"], install=[TWIGCS],
            notes="Twig bundled in Twig-CS-Fixer; framework tags/filters/functions are accepted")
lint_tool("twig-cs-fixer", "Twig-CS-Fixer", ["twig-cs-fixer", "lint", "--no-interaction", "{files}"],
          bin="twig-cs-fixer", needs=["php"], install=[TWIGCS], license="MIT")
extend("twig", ["twig-parse", "twig-cs-fixer"])
syntax_tool("hbs-parse", "Handlebars.parse", NODE + ["syntax-hbs", "{files}"], bin="node", needs=["node"],
            install=[npm("handlebars@4.7.10")])
# why T001 off: {{#if x}} without inner spaces is idiomatic Handlebars, and djlint-format keeps it
extend("handlebars", ["hbs-parse"], tool_defaults={"djlint": {"ignore": "H006,H013,H021,H030,H031,T001"}})
lint_tool("pug-lint", "pug-lint", ["pug-lint", "{files}"], bin="pug-lint", needs=["node"],
          install=[npm("pug-lint@2.7.0")], notes="also reports lexer/parser errors (exit 2)")
extend("pug", ["pug-lint"])

# ------------------------------------------------------------------ still fallback-only (why)
# Researched in 2.1; the built-in checks (encoding, conflict markers, bracket balance, safe
# whitespace) still apply. Opt-in candidates can be added with the same pattern as above.
for _lid, _why in (
        ("razor", ["no offline CLI: the Razor compiler runs only inside a dotnet build with a NuGet restore"]),
        ("wgsl", ["naga-cli (validator; cargo build, no release binaries)",
                  "no safe formatter: @wasm-fmt/wgslfmt corrupted shaders in tests"]),
        ("d", ["D-Scanner / dfmt (no release binaries; ~4 min build with LDC)", "ldc2 -o- (186 MB, opt-in deep check)"]),
        ("vba", ["vba-linter 0.0.x (needs files staged in a directory; flags every LF line ending)"]),
        ("haxe", ["haxe --no-output (type-checks: needs the class path and haxelib libraries)",
                  "haxe-formatter / haxe-checkstyle (no binaries; haxelib server unreachable offline)"]),
        ("actionscript", ["Apache Royale linter.jar / formatter.jar (Allman/tab style rewrites AS3 code)"]),
        ("smalltalk", ["GNU Smalltalk is not packaged for Ubuntu 24.04; Pharo/Squeak need a VM image"]),
        ("forth", ["gforth can only run files (no parse-only mode); executing them is unsafe"]),
        ("lean", ["lean 4 (3 GB toolchain; elaboration runs #eval)"]),
        ("coq", ["coqc -vos (~1.15 GB; writes .vo next to sources)"]),
        ("idris", ["Idris 2 has no packages or binaries for Ubuntu 24.04"]),
        ("godot-resource", ["godot --headless ResourceLoader (146 MB engine + a staged project)"]),
        ("ignore-list", ["codeowners-validator (CODEOWNERS only); git ignores malformed lines silently"]),
        ("apache", ["apache2 -t on a generated wrapper (false positives on missing certificates/paths)"]),
        ("conf", ["a bare .conf has no dialect; apache/nginx files are detected by content"]),
        ("textile", ["pandoc reader (158 MB; catches only gross MediaWiki errors)"]),
        ("text", ["plain text: encoding, conflict markers and safe whitespace are the checks"])):
    extend(_lid, candidates=_why)
