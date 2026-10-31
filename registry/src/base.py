"""Runtimes, built-in checks and repository-wide (global) tools."""
from core import (GLOBAL_TOOLS, RUNTIMES, apt, gh, pip, runtime, script, tool, A_X64)

# ------------------------------------------------------------------ runtimes
# why: installed on demand, the first time a language that needs them appears.

# why pinned: same toolchain on every machine; bump with tools/check-versions.py + upstream notes
NODE_V, GO_V, RUST_V, DART_V, JULIA_V = "24.21.0", "1.27.2", "1.99.0", "3.13.5", "1.13.1"

runtime("node", f"Node.js {NODE_V} (24 LTS)", [script(r'''
set -euo pipefail
a=$(dpkg --print-architecture); case "$a" in amd64) n=x64;; arm64) n=arm64;; *) echo "unsupported arch $a"; exit 1;; esac
base=https://nodejs.org/dist/v@NODE_V@
curl -fsSL --retry 3 "$base/SHASUMS256.txt" -o /tmp/node.sums
f=$(awk -v n="linux-$n.tar.xz" '$2 ~ n"$" {print $2; exit}' /tmp/node.sums)
curl -fsSL --retry 3 "$base/$f" -o "/tmp/$f"
(cd /tmp && grep " $f\$" node.sums | sha256sum -c -)
mkdir -p /opt/node && tar -xJf "/tmp/$f" -C /opt/node --strip-components=1 && rm -f "/tmp/$f" /tmp/node.sums
mkdir -p /opt/npm && cd /opt/npm && [ -f package.json ] || printf '{"name":"qs-npm","private":true}\n' > package.json
''')], path=["/opt/node/bin", "/opt/npm/node_modules/.bin"])

# why 21 and not 25: every JVM tool here supports 21 (detekt, ktlint, checkstyle...); 25 is newer than some
runtime("java", "OpenJDK 21 (headless JRE)", [apt("openjdk-21-jre-headless")])
runtime("jdk", "OpenJDK 21 (headless JDK)", [apt("openjdk-21-jdk-headless")])

runtime("go", f"Go {GO_V}", [script(r'''
set -euo pipefail
[ -x /usr/local/go/bin/go ] && exit 0
a=$(dpkg --print-architecture); f="go@GO_V@.linux-$a.tar.gz"
curl -fsSL --retry 3 "https://dl.google.com/go/$f" -o "/tmp/$f"
curl -fsSL --retry 3 "https://dl.google.com/go/$f.sha256" -o /tmp/go.sum
echo "$(tr -d '[:space:]' < /tmp/go.sum)  /tmp/$f" | sha256sum -c -
tar -C /usr/local -xzf "/tmp/$f" && rm -f "/tmp/$f" /tmp/go.sum
''')], path=["/usr/local/go/bin"], env={"GOTOOLCHAIN": "local", "GOFLAGS": "-mod=mod", "GOPROXY": "off"})

runtime("rust", f"Rust {RUST_V} (rustup, minimal + rustfmt + clippy)", [script(r'''
set -euo pipefail
export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
[ -x /opt/cargo/bin/cargo ] && exit 0
a=$(uname -m)
curl -fsSL --retry 3 "https://static.rust-lang.org/rustup/dist/${a}-unknown-linux-gnu/rustup-init" -o /tmp/rustup-init
chmod +x /tmp/rustup-init && /tmp/rustup-init -y --profile minimal --no-modify-path \
  --default-toolchain @RUST_V@ --component rustfmt,clippy
rm -f /tmp/rustup-init && chmod -R a+rX /opt/rustup /opt/cargo
''')], path=["/opt/cargo/bin"], env={"RUSTUP_HOME": "/opt/rustup", "CARGO_HOME": "/opt/cargo",
                                     "CARGO_TARGET_DIR": "/tmp/cargo-target", "CARGO_NET_OFFLINE": "true"})

runtime("dotnet", ".NET SDK 10 (LTS)", [apt("dotnet-sdk-10.0")],
        env={"DOTNET_CLI_TELEMETRY_OPTOUT": "1", "DOTNET_NOLOGO": "1", "DOTNET_CLI_HOME": "/tmp",
             "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1"})
runtime("php", "PHP CLI", [apt("php-cli", "php-xml", "php-mbstring")])
runtime("ruby", "Ruby", [apt("ruby")], env={"GEM_HOME": "/opt/gems"}, path=["/opt/gems/bin"])
runtime("perl", "Perl", [apt("perl")])
runtime("lua", "Lua 5.4", [apt("lua5.4")])
runtime("erlang", "Erlang/OTP", [apt("erlang-nox")])
runtime("elixir", "Elixir", [apt("elixir")])
runtime("r", "R", [apt("r-base-core")])
runtime("dart", f"Dart SDK {DART_V}", [script(r'''
set -euo pipefail
[ -x /opt/dart-sdk/bin/dart ] && exit 0
a=$(dpkg --print-architecture); case "$a" in amd64) d=x64;; arm64) d=arm64;; *) exit 1;; esac
u="https://storage.googleapis.com/dart-archive/channels/stable/release/@DART_V@/sdk/dartsdk-linux-$d-release.zip"
curl -fsSL --retry 3 "$u" -o /tmp/dart.zip && curl -fsSL "$u.sha256sum" -o /tmp/dart.sum
echo "$(cut -d' ' -f1 /tmp/dart.sum)  /tmp/dart.zip" | sha256sum -c -
unzip -q /tmp/dart.zip -d /opt && rm -f /tmp/dart.zip /tmp/dart.sum && chmod -R a+rX /opt/dart-sdk
''')], path=["/opt/dart-sdk/bin"], env={"PUB_CACHE": "/tmp/pub-cache", "DART_SUPPRESS_ANALYTICS": "true"})
runtime("julia", f"Julia {JULIA_V}", [script(r'''
set -euo pipefail
[ -x /opt/julia/bin/julia ] && exit 0
v=@JULIA_V@; a=$(uname -m); case "$a" in x86_64) d=x64;; aarch64) d=aarch64;; *) exit 1;; esac
curl -fsSL --retry 3 "https://julialang-s3.julialang.org/bin/linux/$d/${v%.*}/julia-$v-linux-$a.tar.gz" -o /tmp/julia.tgz
mkdir -p /opt/julia && tar -xzf /tmp/julia.tgz -C /opt/julia --strip-components=1 && rm -f /tmp/julia.tgz
''')], path=["/opt/julia/bin"], env={"JULIA_DEPOT_PATH": "/tmp/julia-depot:/opt/julia-depot"})
runtime("pwsh", "PowerShell 7 + PSScriptAnalyzer", [
    gh("PowerShell/PowerShell", "v7.6.6", "powershell-{ver}-linux-{arch}.tar.gz", ["pwsh"], arch=A_X64),
    script(r'''pwsh -NoLogo -NoProfile -Command "Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer -Scope AllUsers -Force"'''),
], env={"POWERSHELL_TELEMETRY_OPTOUT": "1", "POWERSHELL_UPDATECHECK": "Off"})
runtime("swipl", "SWI-Prolog", [apt("swi-prolog-nox")])
runtime("ocaml", "OCaml compiler", [apt("ocaml-nox")])

_PINS = {"@NODE_V@": NODE_V, "@GO_V@": GO_V, "@RUST_V@": RUST_V, "@DART_V@": DART_V, "@JULIA_V@": JULIA_V}
for _r in RUNTIMES.values():
    for _i in _r["install"]:
        for _k, _v in _PINS.items():
            if "script" in _i:
                _i["script"] = _i["script"].replace(_k, _v)
runtime("tex", "chktex", [apt("chktex")])

# ------------------------------------------------------------------ built-in steps (no install)

tool("qs-basic-syntax", "syntax", "Built-in minimal syntax check", {"builtin": "basic_syntax"},
     internal=False, fallback=True,
     notes="encoding (UTF-8), NUL bytes, merge-conflict markers, bracket balance outside strings/comments")
tool("qs-basic-format", "format", "Built-in safe formatting", {"builtin": "basic_format"},
     fallback=True,
     notes="trailing whitespace and one final newline only; keeps line endings, BOM, multi-line strings, "
           "heredocs and backslash continuations")
tool("qs-marker", "marker", "Identifying mark (shebang / modeline)", {"builtin": "marker"},
     notes="adds the shebang (scripts) or an editor modeline (ambiguous extensions) during the commit")
for _name, _what in (("properties", "Java .properties: malformed lines, duplicate keys"),
                     ("ini", "INI: sections, duplicate keys/sections"),
                     ("ini-loose", "INI dialects with repeated keys (systemd, desktop entries)"),
                     ("toml", "TOML: strict parse (tomllib)"),
                     ("csv", "CSV: quoting and a constant number of fields"),
                     ("tsv", "TSV: constant number of fields"),
                     ("jsonl", "JSON Lines: one valid JSON value per line"),
                     ("json", "JSON: strict parse"),
                     ("jsonc", "JSON with comments / trailing commas: parse"),
                     ("yaml", "YAML: parse (all documents, custom tags allowed)"),
                     ("jsp", "JSP: balanced <% %> delimiters")):
    tool(f"qs-check-{_name}", "syntax", f"Built-in {_name} check", {"builtin": _name}, notes=_what)
tool("qs-python-ast", "syntax", "Python native parser (ast)", {"builtin": "python_ast"},
     notes="uses the language version as feature_version when the checker supports it")

# ------------------------------------------------------------------ repository-wide checks

GLOBAL_TOOLS += [
    tool("qs-conflict-markers", "syntax", "Merge-conflict markers", {"builtin": "conflict_markers"}),
    tool("qs-private-key", "lint", "Private keys committed by mistake", {"builtin": "private_key"},
         level="syntax"),
    tool("qs-mixed-eol", "lint", "Mixed CRLF/LF line endings in one file", {"builtin": "mixed_line_endings"},
         level="format"),
    tool("qs-large-file", "lint", "Large files", {"builtin": "large_file"}, defaults={"max_kb": 512}),
    tool("qs-repo-files", "lint", "Repository files: VERSION, CHANGELOG, README badge, CITATION, CODEOWNERS",
         {"builtin": "repo_files"}, level="syntax",
         notes="VERSION semver = branch root = pom.xml; CHANGELOG.md in Common Changelog format; "
               "README version badge = last release; CITATION.cff required keys; CODEOWNERS syntax"),
    tool("gitleaks", "lint", "Gitleaks (secrets)",
         {"check": ["gitleaks", "dir", "--no-banner", "--redact", "--exit-code", "1",
                    ["--config", "{config}"], "{args}", "{files}"]},
         bin="gitleaks", batch=False,
         install=[gh("gitleaks/gitleaks", "v8.30.1", "gitleaks_{ver}_linux_{arch}.tar.gz", ["gitleaks"],
                     arch=A_X64)],
         homepage="https://github.com/gitleaks/gitleaks", license="MIT",
         notes="offline: rules are built in"),
    tool("typos", "deep", "typos (spelling in code and docs)",
         {"check": ["typos", "--format", "brief", ["--config", "{config}"], "{args}", "{files}"]},
         bin="typos", config={"file": "typos.toml", "format": "toml"},
         defaults={"default": {"extend-ignore-re": [], "extend-words": {}}},
         install=[pip("typos==1.51.1", "typos")], license="MIT/Apache-2.0"),
    tool("editorconfig-checker", "deep", "editorconfig-checker",
         {"check": ["ec", "-no-color", "{args}", "{files}"]}, bin="ec",
         requires={"any_file": [".editorconfig"], "why": "no .editorconfig in the repository"},
         install=[pip("editorconfig-checker==3.11.1", "ec")], license="MIT",
         notes="only when the repository has .editorconfig; formatters must agree with it"),
    tool("lizard", "deep", "Lizard (complexity, all languages)",
         {"check": ["lizard", "--warnings_only", "{args}", "{files}"]}, bin="lizard",
         rule_args={"joiner": " "},
         defaults={"-C": 12, "-L": 80, "-a": 7},
         install=[pip("lizard==1.24.1", "lizard")], license="MIT",
         notes="CCN 12 / 80 lines / 7 parameters, aligned with the Checkstyle base rules"),
]
