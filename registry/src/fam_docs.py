"""Documentation and markup: Markdown, reST, AsciiDoc, LaTeX, Typst, diagrams, BDD, config management."""
from core import (A_GO, A_X86, PLAIN, WS_SIGNIFICANT, apt, gh, jar, lang, lex, lint_tool, npm, pip, probe,
                  subtype, syntax_tool, tool, fmt_tool)

# ------------------------------------------------------------------ Markdown

MDL = npm("markdownlint-cli2@0.23.3")
fmt_tool("markdownlint-fix", "markdownlint-cli2 --fix",
         ["markdownlint-cli2", "--fix", ["--config", "{config}"], "{files::}"], check="diff",
         bin="markdownlint-cli2", needs=["node"], install=[MDL], success_fix=[0, 1],
         config={"file": ".markdownlint.jsonc", "format": "jsonc", "base": "markdown/markdownlint.jsonc"},
         homepage="https://github.com/DavidAnson/markdownlint-cli2", license="MIT",
         notes="the formatter is markdownlint's own fixer (v1 behaviour): exit 1 = unfixable findings left")
lint_tool("markdownlint", "markdownlint-cli2", ["markdownlint-cli2", ["--config", "{config}"], "{files::}"],
          bin="markdownlint-cli2", needs=["node"], install=[MDL],
          config={"file": ".markdownlint.jsonc", "format": "jsonc", "base": "markdown/markdownlint.jsonc",
                  "inherit": "markdownlint-fix"})
lang("markdown", "Markdown", kind="markup", ext=[".md", ".markdown", ".mdown", ".mkd", ".mkdn"],
     tools=["markdownlint-fix", "markdownlint"], basic=dict(PLAIN, no_format=True),
     notes="two trailing spaces are a hard line break: only markdownlint (MD009 aware) touches whitespace")

# ------------------------------------------------------------------ reStructuredText / AsciiDoc / others

fmt_tool("rstfmt", "rstfmt", ["rstfmt", "{args}", "{files}"], check=["rstfmt", "--check", "{args}", "{files}"],
         bin="rstfmt", install=[pip("rstfmt==0.0.14", "rstfmt")], rule_args={"joiner": " "}, defaults={"-w": 100},
         notes="v1 behaviour; disable it in the rules file for Sphinx sources it cannot round-trip")
lint_tool("rstcheck", "rstcheck", ["rstcheck", "--report-level", "warning", "{files}"], bin="rstcheck",
          install=[pip("rstcheck==6.3.0", "rstcheck")])
lang("rst", "reStructuredText", kind="markup", ext=[".rst", ".rest"], tools=["rstfmt", "rstcheck"],
     basic=dict(PLAIN, no_format=True))
syntax_tool("asciidoctor-check", "asciidoctor (parse, safe mode)",
            ["asciidoctor", "--safe-mode", "safe", "--failure-level", "ERROR", "-o", "/dev/null", "{file}"],
            bin="asciidoctor", install=[apt("asciidoctor")], batch=False)
lang("asciidoc", "AsciiDoc", kind="markup", ext=[".adoc", ".asciidoc"], tools=["asciidoctor-check"], basic=PLAIN)
lang("org", "Org mode", kind="markup", ext=[".org"], basic=PLAIN)
lang("textile", "Textile / wiki markup", kind="markup", ext=[".textile", ".wiki", ".mediawiki", ".creole"],
     basic=PLAIN)
lang("text", "Plain text", kind="markup", ext=[".txt", ".text"],
     names=["README", "LICENSE", "COPYING", "AUTHORS", "CHANGELOG", "NOTICE", "requirements.txt"],
     basic=PLAIN, notes="encoding, conflict markers and safe whitespace only")
syntax_tool("mandoc-lint", "mandoc -T lint", ["mandoc", "-T", "lint", "-W", "warning", "{files}"], bin="mandoc",
            install=[apt("mandoc")])
lang("roff", "man pages (roff/mdoc)", kind="markup", ext=[".man", ".mdoc", ".roff", ".ms", ".me"],
     globs=["man/**/*.[1-9]", "man[1-9]/*.[1-9]", "*.[1-9].in"], tools=["mandoc-lint"], basic=PLAIN)

# ------------------------------------------------------------------ TeX family / Typst

fmt_tool("tex-fmt", "tex-fmt", ["tex-fmt", "{args}", "{files}"], check=["tex-fmt", "--check", "{args}", "{files}"],
         bin="tex-fmt", rule_args={"joiner": " "}, defaults={"--wraplen": 80, "--tabsize": 2},
         install=[gh("WGUNDERWOOD/tex-fmt", "v0.5.7", "tex-fmt-{arch}-linux.tar.gz", ["tex-fmt"], arch=A_X86,
                     verified=False)],
         homepage="https://github.com/WGUNDERWOOD/tex-fmt", license="MIT",
         notes="replaces latexindent (no TeX Live needed); verbatim environments are left untouched")
lint_tool("chktex", "ChkTeX", ["chktex", "-q", "-v0", "-I0", "{args}", "{files}"], bin="chktex", needs=["tex"],
          rule_args={"joiner": ""}, defaults={"-n": [1]}, fail_on_output=True,
          notes="-n1 off as in v1; fails when ChkTeX prints any warning")
TEX_LEX = lex(["%"], [], strings=(), brackets="{}", char_prefix="\\")
lang("latex", "LaTeX", kind="markup", ext=[".tex", ".ltx", ".sty", ".cls", ".dtx", ".latex"],
     probe=[probe(r"\\(documentclass|usepackage|ProvidesClass|ProvidesPackage|NeedsTeXFormat|begin\{)", 10)],
     tools=["tex-fmt", "chktex"], basic=TEX_LEX, marker={"modeline": "% -*- mode: latex -*-"})
# why {file} first: bibtex-tidy 1.15 rejects --modify unless the input file comes before the options
fmt_tool("bibtex-tidy", "bibtex-tidy", ["bibtex-tidy", "{file}", "--modify", "--quiet", "{args}"], check="diff",
         bin="bibtex-tidy", batch=False, needs=["node"], install=[npm("bibtex-tidy@1.15.1")], rule_args={"joiner": "="},
         defaults={"--curly": True, "--space": 2, "--no-align": True, "--no-sort": True},
         notes="no sorting or merging by default: formatting only")
lang("bibtex", "BibTeX", kind="data", ext=[".bib"], tools=["bibtex-tidy"], basic=dict(PLAIN, line_comment=["%"],
                                                                                       brackets="{}"))
fmt_tool("typstyle", "typstyle", ["typstyle", "--inplace", "{args}", "{files}"],
         check=["typstyle", "--check", "{args}", "{files}"], bin="typstyle", rule_args={"joiner": "="},
         defaults={"--column": 100},
         install=[gh("Enter-tainer/typstyle", "v0.15.2", "typstyle-{arch}-unknown-linux-gnu", ["typstyle"], arch=A_X86)])
lang("typst", "Typst", kind="markup", ext=[".typ"], tools=["typstyle"], basic=lex(["//"], [("/*", "*/")],
                                                                                    strings=('"',)))

# ------------------------------------------------------------------ diagrams

syntax_tool("plantuml-check", "PlantUML -checkonly", ["plantuml", "-checkonly", "-failfast2", "{files}"],
            bin="plantuml", needs=["java"],
            install=[jar("https://github.com/plantuml/plantuml/releases/download/v1.2026.8/plantuml-mit-1.2026.8.jar",
                         "plantuml", java_opts=["-Djava.awt.headless=true"])])
lang("plantuml", "PlantUML", kind="markup", ext=[".puml", ".plantuml", ".pu", ".iuml", ".wsd"],
     tools=["plantuml-check"], basic=PLAIN)
syntax_tool("dot-check", "Graphviz parse", ["dot", "-Tcanon", "-o", "/dev/null", "{file}"], bin="dot",
            install=[apt("graphviz")], batch=False)
lang("graphviz", "Graphviz DOT", kind="markup", ext=[".dot", ".gv"], tools=["dot-check"],
     basic=lex(["//", "#"], [("/*", "*/")], strings=('"',)), candidates=["dot -Tcanon (drops comments)"])
D2 = gh("terrastruct/d2", "v0.9.0", "d2-{tag}-linux-{arch}.tar.gz", ["d2"], arch=A_GO)
syntax_tool("d2-validate", "d2 validate", ["d2", "validate", "{file}"], bin="d2", install=[D2], batch=False)
fmt_tool("d2-fmt", "d2 fmt", ["d2", "fmt", "{files}"], bin="d2", install=[D2])
lang("d2", "D2 diagrams", kind="markup", ext=[".d2"], tools=["d2-validate", "d2-fmt"], basic=lex(["#"], [],
                                                                                              strings=('"', "'")))
lang("mermaid", "Mermaid", kind="markup", ext=[".mmd", ".mermaid"], basic=PLAIN,
     candidates=["mermaid-cli (needs headless Chromium)"])

# ------------------------------------------------------------------ BDD / test DSLs

fmt_tool("gherkin-format", "gherkin-utils format", ["gherkin-utils", "format", "{files}"], check="diff",
         bin="gherkin-utils", needs=["node"], install=[npm("@cucumber/gherkin-utils@12.0.2")], license="MIT")
lint_tool("gherkin-lint", "gherkin-lint", ["gherkin-lint", ["-c", "{config}"], "{files}"], bin="gherkin-lint",
          needs=["node"], install=[npm("gherkin-lint@4.2.4")], config={"file": ".gherkin-lintrc", "format": "json"},
          defaults={"no-files-without-scenarios": "on", "no-unnamed-features": "on", "no-unnamed-scenarios": "on",
                    "no-dupe-scenario-names": "on", "no-dupe-feature-names": "on", "no-empty-file": "on",
                    "no-partially-commented-tag-lines": "on", "indentation": "off", "no-trailing-spaces": "off",
                    "no-multiple-empty-lines": "off"},
          notes="layout rules off: gherkin-utils owns them")
lang("gherkin", "Gherkin", kind="markup", ext=[".feature"], tools=["gherkin-format", "gherkin-lint"],
     basic=dict(PLAIN, line_comment=["#"]))
ROBOCOP = pip("robotframework-robocop==9.1.0", "robocop")
fmt_tool("robocop-format", "Robocop format", ["robocop", "format", "--no-cache", "{files}"],
         check=["robocop", "format", "--check", "--no-cache", "{files}"], bin="robocop", install=[ROBOCOP])
lint_tool("robocop", "Robocop check", ["robocop", "check", "--no-cache", "{files}"], bin="robocop", install=[ROBOCOP])
lang("robot", "Robot Framework", kind="markup", ext=[".robot", ".resource"], tools=["robocop-format", "robocop"],
     basic=dict(PLAIN, line_comment=["#"]))

# ------------------------------------------------------------------ configuration management

fmt_tool("puppet-lint-fix", "puppet-lint --fix", ["puppet-lint", "--fix", "--no-autoloader_layout-check", "{files}"],
         check="diff", bin="puppet-lint", needs=["ruby"], install=[apt("puppet-lint")], success_fix=[0, 1])
lint_tool("puppet-lint", "puppet-lint", ["puppet-lint", "--fail-on-warnings", "--no-autoloader_layout-check",
                                         "--log-format", "%{path}:%{line}:%{column}: %{KIND}: %{message}", "{files}"],
          bin="puppet-lint", needs=["ruby"], install=[apt("puppet-lint")])
lang("puppet", "Puppet", kind="infra", ext=[".pp", ".epp"],
     probe=[probe(r"^\s*(class|define|node)\s+[\w:]+\s*(\(|\{|inherits)", 10), probe(r"^\s*\w+\s*\{\s*['\"]", 5)],
     tools=["puppet-lint-fix", "puppet-lint"], basic=lex(["#"], [("/*", "*/")], strings=('"', "'")),
     marker={"modeline": "# -*- mode: puppet -*-"})
