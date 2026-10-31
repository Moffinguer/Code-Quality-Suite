"""Scripting: Python, shells, Perl, Ruby, PHP, Lua, Tcl, PowerShell, Batch, AWK, R, Julia, Vim, Lisp dialects."""
from core import (A_X86, C_LIKE, HASH, LISP, PLAIN, apt, det, gh, lang, lex, lint_tool, npm, phar, pip,
                  probe, script, shebang_marker, subtype, syntax_tool, tool, fmt_tool, version)

# ------------------------------------------------------------------ Python

RUFF = pip("ruff==0.17.0", "ruff")
PY_VERSION = version("3.12", env="PYTHON_VERSION", label="Python version (e.g. 3.9, 3.11, 3.12)", detect=[
    det("pyproject.toml", r'requires-python\s*=\s*["\'][^0-9]*(3\.\d+)'),
    det("pyproject.toml", r'^\s*python\s*=\s*["\'][^0-9]*(3\.\d+)'),
    det(".python-version", r"^\s*(3\.\d+)"),
    det("setup.cfg", r"python_requires\s*=\s*[^0-9]*(3\.\d+)"),
    det("setup.py", r"python_requires\s*=\s*['\"][^0-9]*(3\.\d+)"),
    det("runtime.txt", r"python-(3\.\d+)"),
    det(".tool-versions", r"^python\s+(3\.\d+)"),
])
fmt_tool("ruff-format", "Ruff formatter (+ import sorting)",
         {"all": [["ruff", "check", "--no-cache", "--select", "I", "--fix", "--quiet", "--exit-zero",
                   ["--config", "{config}"], "{files}"],
                  ["ruff", "format", "--no-cache", "--quiet", ["--config", "{config}"], "{args}", "{files}"]]},
         bin="ruff", install=[RUFF],
         config={"file": "ruff.toml", "format": "toml"},
         defaults={"line-length": 100, "indent-width": 4,
                   "format": {"quote-style": "double", "indent-style": "space", "line-ending": "auto",
                              "docstring-code-format": False}},
         version_rules={"target-version": "py{v_nodot}"},
         homepage="https://docs.astral.sh/ruff", license="MIT",
         notes="replaces black + isort + autopep8 (one formatter); import order is part of formatting")
lint_tool("ruff", "Ruff linter", ["ruff", "check", "--no-cache", "--output-format", "concise",
                                  ["--config", "{config}"], "{args}", "{files}"],
          fix=["ruff", "check", "--no-cache", "--fix", "--output-format", "concise", ["--config", "{config}"],
               "{args}", "{files}"],
          bin="ruff", install=[RUFF],
          config={"file": "ruff.toml", "format": "toml", "inherit": "ruff-format"},
          defaults={"lint": {"select": ["E", "F", "W", "I", "N", "B", "UP", "PL", "C90", "SIM"],
                             "ignore": ["W191", "E111", "E114", "E117", "COM812", "ISC001", "PLR2004"],
                             "mccabe": {"max-complexity": 12},
                             "pylint": {"max-args": 5, "max-branches": 12, "max-returns": 6,
                                        "max-statements": 50, "max-locals": 15, "max-bool-expr": 5,
                                        "max-public-methods": 20}}},
          homepage="https://docs.astral.sh/ruff", license="MIT",
          notes="replaces pylint + flake8: N/PL/C90 carry the intent of the old .pylintrc; rules that fight "
                "the formatter are ignored")
tool("mypy", "deep", "mypy (types)",
     {"check": ["mypy", "--no-error-summary", "--show-error-codes", "--cache-dir", "{tmp}/mypy-cache",
                ["--config-file", "{config}"], "{args}", "{files}"]},
     bin="mypy", level="standard", install=[pip("mypy==2.4.0", "mypy")],
     config={"file": "mypy.ini", "format": "ini"},
     defaults={"mypy": {"ignore_missing_imports": True, "warn_unused_ignores": True, "check_untyped_defs": False}},
     version_rules={"mypy.python_version": "{v_major}.{v_minor}"},
     skip_on=[r"python_version: Python 3\.\d+ is not supported"], skip_why="target Python too old for mypy",
     homepage="https://mypy-lang.org", license="MIT", notes="kept at 'standard' as in v1 of the suite")
lang("python", "Python", ext=[".py", ".pyi", ".pyw"], names=["SConstruct", "SConscript", "wscript"],
     shebang=[r"\bpython[0-9.]*\b", r"\bpypy[0-9.]*\b", r"\buv run\b"],
     tools=["qs-python-ast", "qs-marker", "ruff-format", "ruff", "mypy"],
     basic=lex(["#"], [], strings=('"""', "'''", '"', "'")), version=PY_VERSION,
     marker=shebang_marker("#!/usr/bin/env python3"))
lang("jupyter", "Jupyter notebook", kind="data", ext=[".ipynb"],
     tools=["qs-check-json", "ruff-format", "ruff"], basic=dict(PLAIN, no_format=True), version=PY_VERSION)
lint_tool("cython-lint", "cython-lint", ["cython-lint", "--max-line-length", "100", "{args}", "{files}"],
          bin="cython-lint", install=[pip("cython-lint==0.22.0", "cython-lint")])
lang("cython", "Cython", ext=[".pyx", ".pxd", ".pxi"], tools=["cython-lint"],
     basic=lex(["#"], [], strings=('"""', "'''", '"', "'")))

# ------------------------------------------------------------------ shells

SHFMT = pip("shfmt-py==4.2.0", "shfmt")
SHELLCHECK = pip("shellcheck-py==0.11.0.1", "shellcheck")
fmt_tool("shfmt", "shfmt", ["shfmt", "-w", "{args}", "{files}"], check=["shfmt", "-d", "{args}", "{files}"],
         bin="shfmt", install=[SHFMT], rule_args={"joiner": " "}, defaults={"-ln": "bash", "-s": True},
         homepage="https://github.com/mvdan/sh", license="BSD-3-Clause",
         notes="flags given explicitly, so .editorconfig is ignored (the rules file decides); default "
               "indentation is tabs as in v1, set -i 2 for spaces")
lint_tool("shellcheck", "ShellCheck", ["shellcheck", "--norc", "--format", "gcc", "{args}", "{files}"],
          bin="shellcheck", install=[SHELLCHECK], rule_args={"joiner": "="},
          defaults={"--shell": "bash", "--external-sources": True, "--severity": "style"},
          homepage="https://www.shellcheck.net", license="GPL-3.0", notes="no formatting rules: never clashes with shfmt")
SH_LEX = lex(["#"], [], strings=('"', "'"), brackets="", heredoc=True)
SH_PROBES = {
    "bash": [probe(r"\A#!.*\bbash\b", 10), probe(r"\[\[|\bdeclare\s+-|\blocal\s+-a\b|\bshopt\b|\$\{[^}]*//", 1)],
    "sh": [probe(r"\A#!\s*/(usr/)?bin/(env\s+)?(sh|dash|ash|busybox sh)\b", 10)],
    "ksh": [probe(r"\A#!.*\b(ksh|mksh|pdksh|ksh93)\b", 10)],
    "zsh": [probe(r"\A#!.*\bzsh\b", 10), probe(r"\bautoload\s+-U|\bsetopt\b|\bzstyle\b", 3)],
}
syntax_tool("bash-n", "bash -n", ["bash", "-n", "{file}"], bin="bash", batch=False)
syntax_tool("sh-n", "dash -n (POSIX)", ["dash", "-n", "{file}"], bin="dash", batch=False)
syntax_tool("ksh-n", "ksh -n", ["ksh", "-n", "{file}"], bin="ksh", batch=False, install=[apt("ksh")])
syntax_tool("zsh-n", "zsh -n", ["zsh", "-n", "{file}"], bin="zsh", batch=False, install=[apt("zsh")])
lang("bash", "Bash", ext=[".sh", ".bash", ".command"],
     names=[".bashrc", ".bash_profile", ".bash_aliases", ".bash_logout", ".bash_functions", "bashrc",
            "PKGBUILD", "APKBUILD"],
     shebang=[r"\bbash\b"], probe=SH_PROBES["bash"], default_for_ambiguous=True,
     tools=["bash-n", "qs-marker", "shfmt", "shellcheck"], basic=SH_LEX,
     marker=shebang_marker("#!/usr/bin/env bash", always=True))
lang("sh", "POSIX sh", ext=[".sh"], names=[".profile", ".shrc", ".xprofile"],
     shebang=[r"^#!\s*/(usr/)?bin/(env\s+)?(sh|dash|ash)\b"], probe=SH_PROBES["sh"],
     tool_defaults={'shfmt': {'-ln': 'posix', '-s': True}, 'shellcheck': {'--shell': 'sh', '--external-sources': True, '--severity': 'style'}},
     tools=["sh-n", "qs-marker", "shfmt", "shellcheck"], basic=SH_LEX,
     marker=shebang_marker("#!/bin/sh", always=True))
lang("ksh", "KornShell", ext=[".ksh", ".mksh", ".sh"], names=[".kshrc", ".mkshrc"],
     shebang=[r"\b(ksh|mksh|pdksh|ksh93)\b"], probe=SH_PROBES["ksh"],
     tool_defaults={'shfmt': {'-ln': 'mksh', '-s': True}, 'shellcheck': {'--shell': 'ksh', '--external-sources': True, '--severity': 'style'}},
     tools=["ksh-n", "qs-marker", "shfmt", "shellcheck"], basic=SH_LEX,
     marker=shebang_marker("#!/usr/bin/env ksh", always=True))
lang("zsh", "Zsh", ext=[".zsh", ".sh", ".zsh-theme"],
     names=[".zshrc", ".zprofile", ".zshenv", ".zlogin", ".zlogout", "zshrc"],
     shebang=[r"\bzsh\b"], probe=SH_PROBES["zsh"],
     tool_defaults={'shfmt': {'-ln': 'zsh', '-s': True}},
     tools=["zsh-n", "qs-marker", "shfmt"], basic=SH_LEX,
     marker=shebang_marker("#!/usr/bin/env zsh", always=True),
     notes="ShellCheck does not support zsh; shfmt -ln zsh is used for formatting")
lang("bats", "Bats tests", ext=[".bats"], shebang=[r"\bbats\b"],
     tool_defaults={'shfmt': {'-ln': 'bats', '-s': True}, 'shellcheck': {'--external-sources': True, '--severity': 'style'}},
     tools=["qs-marker", "shfmt", "shellcheck"], basic=SH_LEX,
     marker=shebang_marker("#!/usr/bin/env bats", always=True))
syntax_tool("fish-n", "fish --no-execute", ["fish", "--no-execute", "{file}"], bin="fish", batch=False,
            install=[apt("fish")])
fmt_tool("fish_indent", "fish_indent", ["fish_indent", "--write", "{files}"],
         check=["fish_indent", "--check", "{files}"], bin="fish_indent", install=[apt("fish")])
lang("fish", "fish", ext=[".fish"], shebang=[r"\bfish\b"], tools=["fish-n", "qs-marker", "fish_indent"],
     basic=SH_LEX, marker=shebang_marker("#!/usr/bin/env fish"))

# ------------------------------------------------------------------ Perl

syntax_tool("perl-c", "perl -c", ["perl", "-c", "{file}"], bin="perl", needs=["perl"], batch=False,
            skip_on=[r"Can't locate \S+ in @INC"], skip_why="a used module is not installed in the image")
fmt_tool("perltidy", "Perl::Tidy", ["perltidy", "--profile={config}", "-b", "-bext=/", "{args}", "{files}"],
         bin="perltidy", needs=["perl"], install=[apt("perltidy")],
         config={"file": ".perltidyrc", "format": "flags", "base": "perl/perltidyrc"},
         license="GPL-2.0", notes="base profile fixed: --standard-output silently disabled in-place formatting")
lint_tool("perlcritic", "Perl::Critic", ["perlcritic", "--quiet", ["--profile", "{config}"], "{args}", "{files}"],
          bin="perlcritic", needs=["perl"], install=[apt("libperl-critic-perl")],
          config={"file": ".perlcriticrc", "format": "ini", "base": "perl/perlcriticrc"},
          license="GPL-1.0+", notes="CodeLayout::RequireTidyCode off (formatting belongs to perltidy)")
lang("perl", "Perl", ext=[".pl", ".pm", ".t", ".psgi", ".cgi", ".pod"],
     shebang=[r"\bperl[0-9.]*\b"],
     probe=[probe(r"^\s*use\s+(strict|warnings|v5|utf8|feature)\b", 5), probe(r"^\s*my\s+[\$@%]", 3),
            probe(r"^\s*(package\s+[\w:]+;|sub\s+\w+\s*\{)", 3), probe(r"\A#!.*\bperl", 10)],
     default_for_ambiguous=True,
     tools=["perl-c", "qs-marker", "perltidy", "perlcritic"],
     basic=lex(["#"], [], strings=('"', "'")), marker=dict(shebang_marker("#!/usr/bin/env perl"),
                                                          modeline="# -*- mode: perl -*-"),
     candidates=["perlimports (CPAN, loads modules to resolve imports: unreliable offline)"])
lang("raku", "Raku", ext=[".raku", ".rakumod", ".rakutest", ".p6", ".pm6"], shebang=[r"\braku\b"],
     basic=lex(["#"], [], strings=('"',)), candidates=["raku -c (needs Rakudo)"])

# ------------------------------------------------------------------ Ruby

RUBOCOP = script("GEM_HOME=/opt/gems gem install --no-document rubocop -v '~> 1.80' && "
                 "ln -sf /opt/gems/bin/rubocop /opt/qs/bin/rubocop")
syntax_tool("ruby-c", "ruby -wc", ["ruby", "-wc", "{file}"], bin="ruby", needs=["ruby"], batch=False)
fmt_tool("rubocop-layout", "RuboCop (layout only)",
         ["rubocop", "--fix-layout", "--cache", "false", "--format", "quiet", "--force-exclusion",
          ["--config", "{config}"], "{args}", "{files}"],
         bin="rubocop", needs=["ruby"], install=[RUBOCOP], success_fix=[0, 1],
         config={"file": ".rubocop.yml", "format": "yaml"},
         defaults={"AllCops": {"NewCops": "enable", "SuggestExtensions": False},
                   "Layout/LineLength": {"Max": 120}},
         version_rules={"AllCops.TargetRubyVersion": "{float}{v_major}.{v_minor}"},
         homepage="https://rubocop.org", license="MIT",
         notes="the Layout department is the formatter; the other departments are the linter")
lint_tool("rubocop", "RuboCop (lint)", ["rubocop", "--except", "Layout", "--cache", "false", "--format", "emacs",
                                        "--force-exclusion", ["--config", "{config}"], "{args}", "{files}"],
          bin="rubocop", needs=["ruby"], install=[RUBOCOP],
          config={"file": ".rubocop.yml", "format": "yaml", "inherit": "rubocop-layout"},
          version_rules={"AllCops.TargetRubyVersion": "{float}{v_major}.{v_minor}"})
lang("ruby", "Ruby", ext=[".rb", ".rake", ".gemspec", ".ru", ".rbw", ".jbuilder", ".podspec"],
     names=["Rakefile", "Gemfile", "Guardfile", "Vagrantfile", "Podfile", "Fastfile", "Brewfile", "Capfile",
            "Dangerfile", "Berksfile", "Thorfile", ".irbrc", ".pryrc"],
     shebang=[r"\bruby[0-9.]*\b"], tools=["ruby-c", "qs-marker", "rubocop-layout", "rubocop"],
     basic=lex(["#"], [("=begin", "=end")], strings=('"', "'")),
     marker=shebang_marker("#!/usr/bin/env ruby"),
     version=version("3.3", env="QS_RUBY_VERSION", label="Ruby version (e.g. 3.1, 3.3)", detect=[
         det(".ruby-version", r"^\s*(?:ruby-)?(\d+\.\d+)"), det("Gemfile", r'^\s*ruby\s+["\'][^0-9]*(\d+\.\d+)'),
         det(".tool-versions", r"^ruby\s+(\d+\.\d+)")]))

# ------------------------------------------------------------------ PHP

syntax_tool("php-l", "php -l", ["php", "-l", "{file}"], bin="php", needs=["php"], batch=False)
fmt_tool("php-cs-fixer", "PHP CS Fixer",
         ["php-cs-fixer", "fix", "--using-cache=no", "--quiet", "--config={config}", "{args}", "{files}"],
         check=["php-cs-fixer", "fix", "--dry-run", "--diff", "--using-cache=no", "--config={config}", "{args}",
                "{files}"],
         bin="php-cs-fixer", needs=["php"],
         install=[phar("https://github.com/PHP-CS-Fixer/PHP-CS-Fixer/releases/download/v3.95.27/php-cs-fixer.phar",
                       "php-cs-fixer")],
         config={"file": ".php-cs-fixer.php", "format": "php-cs-fixer", "base": "php/php-cs-fixer.dist.php"},
         defaults={"@PSR12": True}, env={"PHP_CS_FIXER_IGNORE_ENV": "1"},
         homepage="https://cs.symfony.com", license="MIT")
lint_tool("phpstan", "PHPStan", ["phpstan", "analyse", "--no-progress", "--no-ansi", "--error-format=raw",
                                 "--memory-limit=1G", ["-c", "{config}"], "{args}", "{files}"],
          bin="phpstan", needs=["php"],
          install=[phar("https://github.com/phpstan/phpstan/releases/download/2.3.1/phpstan.phar", "phpstan")],
          config={"file": "phpstan.neon", "format": "neon"},
          defaults={"parameters": {"level": 5}},
          version_rules={"parameters.phpVersion": "{int}{v_major}0{v_minor}00"},
          requires={"any_file": ["vendor/autoload.php"],
                    "why": "no vendor/autoload.php (run composer install so classes resolve)"},
          homepage="https://phpstan.org", license="MIT")
lang("php", "PHP", ext=[".php", ".phtml", ".php3", ".php4", ".php5", ".php7", ".php8", ".phps", ".inc"],
     shebang=[r"\bphp[0-9.]*\b"], probe=[probe(r"<\?php\b", 10)],
     tools=["php-l", "qs-marker", "php-cs-fixer", "phpstan"], basic=C_LIKE,
     marker=shebang_marker("#!/usr/bin/env php"),
     version=version("8.3", env="PHP_VERSION", label="PHP version (e.g. 7.4, 8.1, 8.3)", detect=[
         det("composer.json", r'"php"\s*:\s*"[^0-9]*(\d+\.\d+)'),
         det(".php-version", r"^\s*(\d+\.\d+)"), det(".tool-versions", r"^php\s+(\d+\.\d+)")]))

# ------------------------------------------------------------------ Lua

syntax_tool("luac", "luac -p", ["luac5.4", "-p", "{files}"], bin="luac5.4", needs=["lua"],
            skip_version=r"(?i)luau", install=[apt("lua5.4")])
fmt_tool("stylua", "StyLua", ["stylua", ["--config-path", "{config}"], "{args}", "{files}"],
         check=["stylua", "--check", ["--config-path", "{config}"], "{args}", "{files}"], bin="stylua",
         install=[gh("JohnnyMorganz/StyLua", "v2.6.0", "stylua-linux-{arch}.zip", ["stylua"], arch=A_X86)],
         config={"file": "stylua.toml", "format": "toml"},
         defaults={"column_width": 120, "indent_type": "Tabs", "indent_width": 4, "quote_style": "AutoPreferDouble"},
         version_rules={"syntax": "{var:syntax}"},
         version_vars={"syntax": {"default": "All", "map": {"5.1": "Lua51", "5.2": "Lua52", "5.3": "Lua53",
                                                            "5.4": "Lua54", "luau": "Luau", "Luau": "Luau"}}},
         license="MPL-2.0")
lint_tool("luacheck", "luacheck", ["luacheck", "--no-color", "--formatter", "plain", "--std", "{var:std}",
                                   ["--config", "{config}"], "{args}", "{files}"],
          bin="luacheck", needs=["lua"], install=[apt("lua-check")],
          config={"file": ".luacheckrc", "format": "lua"}, defaults={"max_line_length": False},
          version_vars={"std": {"default": "max", "map": {"5.1": "lua51", "5.2": "lua52", "5.3": "lua53",
                                                          "5.4": "lua54", "luajit": "luajit"}}},
          license="MIT", notes="line length off: StyLua owns it")
lang("lua", "Lua", ext=[".lua", ".luau", ".rockspec"], names=[".luacheckrc", ".busted"],
     shebang=[r"\blua(jit|[0-9.]*)?\b"], tools=["luac", "qs-marker", "stylua", "luacheck"],
     basic=lex(["--"], [("--[[", "]]")], strings=('"', "'"), raw=[("[[", "]]")]),
     marker=shebang_marker("#!/usr/bin/env lua"),
     version=version("5.4", env="LUA_VERSION", label="Lua version (5.1, 5.2, 5.3, 5.4, luajit, luau)", detect=[
         det(".lua-version", r"^\s*([0-9.]+|luajit|luau)"), det(".luarc.json", r'"version"\s*:\s*"Lua\s*([0-9.]+)'),
         det(".tool-versions", r"^lua\s+(\d+\.\d+)")]))

# ------------------------------------------------------------------ Tcl / PowerShell / Batch / AWK

TCLINT = pip("tclint==0.9.0", "tclint", "tclfmt")
fmt_tool("tclfmt", "tclfmt", ["tclfmt", "--in-place", "{files}"], check=["tclfmt", "--check", "{files}"],
         bin="tclfmt", install=[TCLINT], license="MIT")
lint_tool("tclint", "tclint", ["tclint", "{args}", "{files}"], bin="tclint", install=[TCLINT])
lang("tcl", "Tcl", ext=[".tcl", ".tk", ".itcl", ".tm", ".exp"], shebang=[r"\b(tclsh|wish|expect)\b"],
     tools=["qs-marker", "tclfmt", "tclint"], basic=lex(["#"], [], strings=('"',)),
     marker=shebang_marker("#!/usr/bin/env tclsh"))

PS = "{suite}/engine/helpers/qs-ps.ps1"
syntax_tool("ps-parse", "PowerShell parser", ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File", PS,
                                              "syntax", "{files}"], bin="pwsh", needs=["pwsh"])
fmt_tool("ps-format", "Invoke-Formatter (PSScriptAnalyzer)",
         ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File", PS, "format", "{config}", "{files}"],
         check="diff", bin="pwsh", needs=["pwsh"],
         config={"file": "PSFormatterSettings.psd1", "format": "psd1"},
         defaults={"IncludeRules": ["PSPlaceOpenBrace", "PSPlaceCloseBrace", "PSUseConsistentWhitespace",
                                    "PSUseConsistentIndentation", "PSAlignAssignmentStatement",
                                    "PSUseCorrectCasing"],
                   "Rules": {"PSUseConsistentIndentation": {"Enable": True, "IndentationSize": 4},
                             "PSPlaceOpenBrace": {"Enable": True, "OnSameLine": True},
                             "PSUseConsistentWhitespace": {"Enable": True}}})
lint_tool("psscriptanalyzer", "PSScriptAnalyzer",
          ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-File", PS, "lint", "{config}", "{files}"],
          bin="pwsh", needs=["pwsh"], config={"file": "PSScriptAnalyzerSettings.psd1", "format": "psd1"},
          defaults={"Severity": ["Error", "Warning"],
                    "ExcludeRules": ["PSPlaceOpenBrace", "PSPlaceCloseBrace", "PSUseConsistentWhitespace",
                                     "PSUseConsistentIndentation", "PSAlignAssignmentStatement"]},
          notes="formatting rules excluded here: Invoke-Formatter owns them")
lang("powershell", "PowerShell", ext=[".ps1", ".psm1", ".psd1"], shebang=[r"\bpwsh\b"],
     tools=["ps-parse", "qs-marker", "ps-format", "psscriptanalyzer"],
     basic=lex(["#"], [("<#", "#>")], strings=('"', "'"), escape="`"),
     marker=shebang_marker("#!/usr/bin/env pwsh"))
lint_tool("blinter", "Blinter", ["blinter", "{file}"], bin="blinter", batch=False,
          install=[pip("Blinter==1.1.31", "blinter")], license="AGPL-3.0",
          notes="fails on critical findings; style findings are reported only")
lang("batch", "Windows Batch", ext=[".bat", ".cmd"], tools=["blinter"],
     basic=lex(["REM ", "rem ", "::"], [], strings=('"',), escape="^", brackets="()"),
     notes="CRLF line endings are preserved by the built-in formatting")
syntax_tool("gawk-parse", "gawk parse (no execution)", ["gawk", "--lint=invalid", "-o/dev/null", "-f", "{file}"],
            bin="gawk", install=[apt("gawk")], batch=False,
            notes="-o pretty-prints instead of running the program, so nothing is executed")
lang("awk", "AWK", ext=[".awk", ".gawk", ".mawk"], shebang=[r"\b[gnm]?awk\b"],
     tools=["gawk-parse", "qs-marker"], basic=lex(["#"], [], strings=('"',)),
     marker=shebang_marker("#!/usr/bin/awk -f"), candidates=["gawk --pretty-print (moves comments)"])

# ------------------------------------------------------------------ R / Julia

syntax_tool("r-parse", "R parser", ["Rscript", "--vanilla", "-e",
                                    "for (f in commandArgs(TRUE)) invisible(parse(f, keep.source = FALSE))",
                                    "--args", "{files}"], bin="Rscript", needs=["r"])
fmt_tool("air", "Air (R formatter)", ["air", "format", "{files}"], check=["air", "format", "--check", "{files}"],
         bin="air", install=[gh("posit-dev/air", "0.12.0", "air-{arch}-unknown-linux-gnu.tar.gz", ["air"], arch=A_X86)],
         homepage="https://posit-dev.github.io/air", license="MIT")
lint_tool("lintr", "lintr", ["Rscript", "--vanilla", "{suite}/engine/helpers/qs-lintr.R", "{config}", "{files}"],
          bin="Rscript", needs=["r"], install=[apt("r-cran-lintr")],
          config={"file": ".lintr", "format": "rc-colon"},
          defaults={"linters": "linters_with_defaults(line_length_linter(120), indentation_linter = NULL, "
                               "object_name_linter = NULL)"},
          notes="indentation/style linters off: Air owns formatting")
lang("r", "R", ext=[".r", ".R", ".Rprofile"], names=[".Rprofile"], shebang=[r"\bRscript\b"],
     tools=["r-parse", "qs-marker", "air", "lintr"], basic=lex(["#"], [], strings=('"', "'")),
     marker=shebang_marker("#!/usr/bin/env Rscript"))
lang("rmarkdown", "R Markdown / Quarto", kind="markup", ext=[".rmd", ".Rmd", ".qmd"],
     basic=dict(PLAIN, no_format=True), notes="trailing spaces can be hard line breaks: never stripped")
JULIA_FMT = script("JULIA_DEPOT_PATH=/opt/julia-depot julia -e 'using Pkg; Pkg.add(\"JuliaFormatter\"); "
                   "using JuliaFormatter' && chmod -R a+rX /opt/julia-depot")
syntax_tool("julia-parse", "Julia parser", ["julia", "--startup-file=no", "-e",
                                            "for f in ARGS; Meta.parseall(read(f, String); filename=f); end",
                                            "{files}"], bin="julia", needs=["julia"])
fmt_tool("juliaformatter", "JuliaFormatter",
         ["julia", "--startup-file=no", "-e", "using JuliaFormatter; for f in ARGS; format_file(f); end", "{files}"],
         check="diff", bin="julia", needs=["julia"], install=[JULIA_FMT], timeout=600)
lang("julia", "Julia", ext=[".jl"], shebang=[r"\bjulia\b"], tools=["julia-parse", "qs-marker", "juliaformatter"],
     basic=lex(["#"], [("#=", "=#")], strings=('"""', '"'), nested=True),
     marker=shebang_marker("#!/usr/bin/env julia"))

# ------------------------------------------------------------------ Vim / Lisp family / misc scripting

lint_tool("vint", "Vint", ["vint", "--no-color", "{files}"], bin="vint", install=[pip("vim-vint==0.3.21", "vint")])
lang("vim", "Vim script", ext=[".vim", ".vimrc"], names=[".vimrc", "vimrc", ".gvimrc", "_vimrc", ".exrc"],
     tools=["vint"], basic=dict(PLAIN, heredoc=False),
     notes="formatting is the built-in safe one (same as shell scripts in v1)")
lang("emacs-lisp", "Emacs Lisp", ext=[".el"], names=[".emacs", "_emacs"],
     basic=dict(LISP, brackets="", char_prefix="?\\"))
lang("common-lisp", "Common Lisp", ext=[".lisp", ".lsp", ".asd", ".cl"],
     probe=[probe(r"^\s*\((defun|defmacro|defpackage|in-package|defclass|defvar|defparameter)\b", 5)],
     basic=LISP, marker={"modeline": ";;; -*- mode: lisp -*-"}, shebang=[r"\bsbcl\b"])
lang("scheme", "Scheme", ext=[".scm", ".ss", ".sld"], shebang=[r"\b(guile|chicken|csi)\b"],
     probe=[probe(r"^\s*\((define|define-library|import)\b", 3)], basic=LISP)
lang("racket", "Racket", ext=[".rkt", ".rktl", ".rktd"], shebang=[r"\bracket\b"], basic=LISP,
     candidates=["raco fmt (needs Racket)"])
syntax_tool("coffee-compile", "CoffeeScript compile check", ["coffee", "--compile", "--print", "{file}"],
            bin="coffee", needs=["node"], install=[npm("coffeescript@2.7.0")], batch=False)
lang("coffeescript", "CoffeeScript", ext=[".coffee", ".litcoffee"], tools=["coffee-compile"],
     basic=lex(["#"], [("###", "###")], strings=('"""', "'''", '"', "'")))
