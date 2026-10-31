"""Web: JavaScript/TypeScript, JSON family, HTML, CSS family, components, GraphQL, templates."""
from core import (C_LIKE, HASH, PLAIN, WS_SIGNIFICANT, lang, lex, lint_tool, npm, pip, probe, script,
                  shebang_marker, subtype, syntax_tool, tool, fmt_tool, apt)

PRETTIER_NPM = npm("prettier@3.9.10", "prettier-plugin-svelte@4.1.1", "svelte@5.57.2",
                   "prettier-plugin-astro@1.1.1", "@prettier/plugin-pug@3.6.0",
                   "prettier-plugin-solidity@2.4.1", "prettier-plugin-apex@2.3.0",
                   "@shopify/prettier-plugin-liquid@1.11.2")
ESLINT_NPM = npm("eslint@10.12.0", "@eslint/js@10.0.1", "globals@17.13.0", "typescript@6.0.3",
                 "typescript-eslint@8.71.1", "eslint-plugin-html@8.2.1", "eslint-plugin-vue@10.11.1",
                 "vue-eslint-parser@10.4.1", "eslint-plugin-svelte@3.23.1", "svelte-eslint-parser@1.9.0",
                 "svelte@5.57.2", "eslint-plugin-astro@3.2.1", "astro-eslint-parser@3.2.0")
STYLELINT_NPM = npm("stylelint@17.16.0", "stylelint-config-standard@40.0.0",
                    "stylelint-config-standard-scss@17.0.0", "stylelint-config-standard-less@4.1.0",
                    "postcss-html@2.0.0", "postcss-scss@4.0.9", "postcss-less@6.0.0")
COPY_BASES = script("install -m 0644 {suite}/config/web/eslint.base.mjs /opt/npm/eslint.base.mjs")

# ------------------------------------------------------------------ shared tools

tool("prettier", "format", "Prettier",
     {"fix": ["prettier", "--write", "--log-level", "warn", "--no-editorconfig", ["--config", "{config}"],
              "{args}", "{files}"],
      "check": ["prettier", "--check", "--log-level", "warn", "--no-editorconfig", ["--config", "{config}"],
                "{args}", "{files}"]},
     bin="prettier", cwd="npm", needs=["node"], install=[PRETTIER_NPM],
     config={"file": "prettierrc.json", "format": "json", "base": "web/prettierrc.json"},
     homepage="https://prettier.io", license="MIT",
     notes="the only formatter for JS/TS/CSS/HTML/Vue/Svelte/Astro/JSON/GraphQL/MDX; runs with "
           "--no-editorconfig so the rules file is the single source of truth")
tool("eslint", "lint", "ESLint",
     {"check": ["eslint", "--no-warn-ignored", "--max-warnings", "0", ["--config", "{config}"], "{args}",
                "{files}"],
      "fix": ["eslint", "--fix", "--no-warn-ignored", "--max-warnings", "0", ["--config", "{config}"], "{args}",
              "{files}"]},
     bin="eslint", cwd="npm", needs=["node"], install=[ESLINT_NPM, COPY_BASES],
     config={"file": "eslint.config.mjs", "format": "eslint", "base": "{npm}/eslint.base.mjs"},
     homepage="https://eslint.org", license="MIT",
     notes="recommended rule sets only (ESLint >= 9 has no stylistic rules, so it cannot clash with "
           "Prettier). rules here are overrides on top of the image base config")
tool("stylelint", "lint", "Stylelint",
     {"check": ["stylelint", "--config-basedir", "{npm}", "--allow-empty-input",
                ["--config", "{config}"], "{args}", "{files}"]},
     bin="stylelint", cwd="npm", needs=["node"], install=[STYLELINT_NPM],
     config={"file": "stylelintrc.json", "format": "json", "base": "web/stylelintrc.json"},
     defaults={"rules": {"rule-empty-line-before": None, "at-rule-empty-line-before": None,
                         "comment-empty-line-before": None, "declaration-empty-line-before": None,
                         "custom-property-empty-line-before": None}},
     homepage="https://stylelint.io", license="MIT",
     notes="Stylelint >= 16 dropped stylistic rules; the remaining blank-line rules are off because "
           "Prettier owns blank lines")
tool("qs-ts-syntax", "syntax", "TypeScript parser (syntax only)",
     {"check": ["node", "{suite}/engine/js/qs-node.mjs", "syntax-ts", "{files}"]},
     bin="node", cwd="npm", needs=["node"], install=[npm("typescript@6.0.3")],
     notes="parse diagnostics only (no type checking): works per file, offline, for JS/JSX/TS/TSX")
tool("tsc", "deep", "TypeScript compiler (project type check)",
     {"check": ["tsc", "--noEmit", "--pretty", "false", "-p", "{found}"]},
     bin="tsc", needs=["node"], install=[npm("typescript@6.0.3")], batch=True, scope="project",
     requires={"any_file": ["tsconfig.json"], "why": "no tsconfig.json at the repository root"},
     offline_skip=[r"Cannot find (module|type definition file)", r"TS2307", r"TS2688"], timeout=900)

# ------------------------------------------------------------------ JavaScript / TypeScript

JS_LEX = lex(["//"], [("/*", "*/")], strings=('"', "'", "`"), multiline_strings=True)
lang("javascript", "JavaScript", ext=[".js", ".mjs", ".cjs", ".jsx"],
     shebang=[r"\bnode\b", r"\bdeno\b", r"\bbun\b"],
     tools=["qs-ts-syntax", "qs-marker", "prettier", "eslint"], basic=JS_LEX,
     marker=shebang_marker("#!/usr/bin/env node"),
     subtypes=[subtype("minified", "Minified bundle", globs=["*.min.js", "*.bundle.js"],
                       exclude_roles=["marker", "format", "lint", "deep"])])
lang("typescript", "TypeScript", ext=[".ts", ".tsx", ".mts", ".cts"],
     probe=[probe(r"^\s*(import|export|interface|type|const|let|function|class|declare|namespace)\b", 2)],
     default_for_ambiguous=True,
     tools=["qs-ts-syntax", "prettier", "eslint", "tsc"], basic=JS_LEX,
     subtypes=[subtype("declaration", "Type declarations", globs=["*.d.ts"], exclude_tools=["eslint"])])

# ------------------------------------------------------------------ JSON family

lang("json", "JSON", kind="data", ext=[".json", ".geojson", ".webmanifest", ".har", ".avsc", ".jsonld",
                                      ".gltf", ".topojson"],
     names=[".babelrc", ".prettierrc", ".stylelintrc", ".htmlhintrc", ".jshintrc", ".watchmanconfig",
            "composer.lock", ".markdownlintrc"],
     tools=["qs-check-json", "prettier"], basic=PLAIN,
     subtypes=[
         subtype("lockfile", "Lockfile (generated)", names=["package-lock.json", "composer.lock", "flake.lock",
                                                           "Pipfile.lock", "packages.lock.json", "deno.lock",
                                                           "npm-shrinkwrap.json", "bun.lock"],
                 exclude_roles=["marker", "format", "lint", "deep"]),
         subtype("json-schema", "JSON Schema", content=[r'"\$schema"\s*:\s*"https?://json-schema\.org'],
                 tools=["check-jsonschema-meta"]),
         subtype("renovate", "Renovate config", names=["renovate.json", ".renovaterc.json"],
                 tools=["check-jsonschema-renovate"]),
         subtype("cloudformation", "CloudFormation template",
                 content=[r'"AWSTemplateFormatVersion"|"Type"\s*:\s*"AWS::'], tools=["cfn-lint"]),
     ])
lang("jsonc", "JSON with comments", kind="data", ext=[".jsonc", ".code-workspace", ".code-snippets"],
     globs=["tsconfig.json", "tsconfig.*.json", "jsconfig.json", "jsconfig.*.json", ".vscode/*.json",
            ".devcontainer/devcontainer.json", ".devcontainer.json", ".eslintrc.json", "deno.json",
            "turbo.json", "biome.json", ".swcrc", "*.jsonc"],
     tools=["qs-check-jsonc", "prettier"], basic=PLAIN)
lang("json5", "JSON5", kind="data", ext=[".json5"], tools=["prettier"], basic=lex(["//"], [("/*", "*/")]))
lang("jsonl", "JSON Lines", kind="data", ext=[".jsonl", ".ndjson", ".jsonlines"],
     tools=["qs-check-jsonl"], basic=dict(PLAIN, no_format=True))

# ------------------------------------------------------------------ HTML / components

lint_tool("html-validate", "html-validate",
          ["html-validate", "--formatter", "text", ["--config", "{config}"], "{args}", "{files}"],
          bin="html-validate", cwd="npm", needs=["node"], install=[npm("html-validate@11.16.2")],
          config={"file": "htmlvalidate.json", "format": "json", "base": "web/htmlvalidate.json"},
          license="MIT", notes="extends html-validate:prettier so markup style is left to Prettier")
lang("html", "HTML", kind="markup", ext=[".html", ".htm", ".xhtml", ".shtml"],
     tools=["prettier", "html-validate", "eslint", "stylelint"],
     basic=lex(["<!--"], [("<!--", "-->")], strings=(), brackets=""),
     subtypes=[
         subtype("template", "Server-side template inside .html (Jinja/Django/Nunjucks/Twig/Liquid)",
                 content=[r"\{%-?\s*(block|extends|load|if|for|include|macro|set|raw|with|url|static|csrf_token)\b"],
                 exclude_tools=["prettier", "html-validate", "eslint", "stylelint"],
                 tools=["djlint-format", "djlint"]),
         subtype("angular", "Angular component template", globs=["*.component.html"],
                 exclude_tools=["prettier", "eslint"], tools=["prettier-angular"]),
     ])
fmt_tool("prettier-angular", "Prettier (Angular templates)",
         ["prettier", "--write", "--log-level", "warn", "--no-editorconfig", "--parser", "angular",
          ["--config", "{config}"], "{args}", "{files}"],
         check=["prettier", "--check", "--log-level", "warn", "--no-editorconfig", "--parser", "angular",
                ["--config", "{config}"], "{args}", "{files}"],
         bin="prettier", cwd="npm", needs=["node"], install=[PRETTIER_NPM],
         config={"file": "prettierrc.json", "format": "json", "base": "web/prettierrc.json"})
lang("vue", "Vue SFC", kind="markup", ext=[".vue"], tools=["prettier", "eslint", "stylelint"],
     basic=lex(["//"], [("<!--", "-->"), ("/*", "*/")], strings=(), brackets=""))
lang("svelte", "Svelte", kind="markup", ext=[".svelte"], tools=["prettier", "eslint", "stylelint"],
     basic=lex([], [("<!--", "-->")], strings=(), brackets=""))
lang("astro", "Astro", kind="markup", ext=[".astro"], tools=["prettier", "eslint"],
     basic=lex([], [("<!--", "-->")], strings=(), brackets=""))

# ------------------------------------------------------------------ CSS family

CSS_LEX = lex([], [("/*", "*/")], brackets="()[]{}")
SCSS_LEX = lex(["//"], [("/*", "*/")], brackets="()[]{}")
lang("css", "CSS", kind="style", ext=[".css", ".pcss", ".postcss"], tools=["prettier", "stylelint"],
     basic=CSS_LEX,
     subtypes=[subtype("minified", "Minified CSS", globs=["*.min.css"], exclude_roles=["format", "lint"])])
lang("scss", "SCSS", kind="style", ext=[".scss"], tools=["prettier", "stylelint"], basic=SCSS_LEX)
lang("less", "Less", kind="style", ext=[".less"], tools=["prettier", "stylelint"], basic=SCSS_LEX)
syntax_tool("sass-compile", "Dart Sass compile check",
            ["sass", "--no-source-map", "--quiet", "{file}", "{tmp}/qs-sass.css"],
            bin="sass", needs=["node"], install=[npm("sass@1.105.1")], batch=False,
            skip_on=[r"Can't find stylesheet to import"], skip_why="imports not resolvable in isolation")
lang("sass", "Sass (indented syntax)", kind="style", ext=[".sass"], tools=["sass-compile"],
     basic=dict(SCSS_LEX, brackets="()[]"),
     notes="indentation-significant: only the built-in whitespace formatting applies")
lang("stylus", "Stylus", kind="style", ext=[".styl", ".stylus"], basic=dict(SCSS_LEX, brackets="()[]"),
     candidates=["stylus-supremacy (formatter, unmaintained)"])

# ------------------------------------------------------------------ GraphQL / MDX

syntax_tool("qs-graphql-syntax", "GraphQL parser",
            ["node", "{suite}/engine/js/qs-node.mjs", "syntax-graphql", "{files}"],
            bin="node", cwd="npm", needs=["node"], install=[npm("graphql@16.14.2")])
lint_tool("graphql-schema-linter", "graphql-schema-linter",
          ["graphql-schema-linter", "--format", "compact", ["--config-directory", "{config_dir}"], "{files}"],
          bin="graphql-schema-linter", cwd="npm", needs=["node"],
          install=[npm("graphql-schema-linter@3.0.1", "graphql@16.14.2")],
          config={"file": "package.json", "format": "json"},
          defaults={"graphql-schema-linter": {"rules": ["defined-types-are-used", "deprecations-have-a-reason",
                                                        "enum-values-all-caps", "types-are-capitalized",
                                                        "fields-are-camel-cased", "input-object-values-are-camel-cased"]}})
lang("graphql", "GraphQL", kind="query", ext=[".graphql", ".gql", ".graphqls"],
     tools=["qs-graphql-syntax", "prettier"], basic=lex(["#"], [], strings=('"""', '"')),
     subtypes=[subtype("schema", "GraphQL schema (SDL)",
                       content=[r"^\s*(type|schema|interface|enum|input|scalar|union|directive)\s"],
                       tools=["graphql-schema-linter"])])
lang("mdx", "MDX", kind="markup", ext=[".mdx"], tools=["prettier"], basic=dict(PLAIN, no_format=True))

# ------------------------------------------------------------------ server-side templates

DJLINT = pip("djlint==1.46.4", "djlint")
fmt_tool("djlint-format", "djLint (reformat)",
         ["djlint", "--reformat", "--quiet", "{args}", "{files}"],
         check=["djlint", "--check", "--quiet", "{args}", "{files}"],
         bin="djlint", install=[DJLINT], rule_args={"joiner": "="}, success_fix=[0, 1],
         defaults={"profile": "jinja", "indent": 2, "max-line-length": 120},
         notes="exit 1 on --reformat only means 'files changed'")
lint_tool("djlint", "djLint (lint)", ["djlint", "--lint", "{args}", "{files}"], bin="djlint", install=[DJLINT],
          rule_args={"joiner": "="}, config={"inherit": "djlint-format"},
          defaults={"ignore": "H006,H013,H021,H030,H031"},
          notes="inherits profile/indent from djlint-format so lint and format agree")
TPL = lex([], [("{#", "#}"), ("<!--", "-->")], strings=(), brackets="")
lang("jinja", "Jinja / Django / Nunjucks templates", kind="template",
     ext=[".j2", ".jinja", ".jinja2", ".njk", ".nunjucks", ".djhtml", ".dtl"],
     tools=["djlint-format", "djlint"], basic=TPL)
lang("twig", "Twig", kind="template", ext=[".twig"], tools=["djlint-format", "djlint"], basic=TPL)
lang("handlebars", "Handlebars / Mustache", kind="template", ext=[".hbs", ".handlebars", ".mustache"],
     tools=["djlint-format", "djlint"], basic=lex([], [("{{!--", "--}}"), ("{{!", "}}")], strings=(), brackets=""))
lang("go-template", "Go templates", kind="template", ext=[".gotmpl", ".gohtml", ".tmpl"], globs=["templates/_*.tpl"],
     tools=["djlint-format", "djlint"], basic=TPL)
lang("liquid", "Liquid", kind="template", ext=[".liquid"], tools=["prettier"], basic=TPL)
lang("ejs", "EJS", kind="template", ext=[".ejs"], tools=["ejs-lint"], basic=TPL)
syntax_tool("ejs-lint", "ejs-lint", ["ejslint", "{file}"], bin="ejslint", needs=["node"],
            install=[npm("ejs-lint@2.0.1")], batch=False)
syntax_tool("erb-syntax", "ERB compile + ruby -c",
            ["sh", "-c", 'erb -x -T - "$1" | ruby -c >/dev/null', "erb-syntax", "{file}"],
            bin=["erb", "ruby"], needs=["ruby"], batch=False)
lang("erb", "ERB (Ruby templates)", kind="template", ext=[".erb", ".rhtml"], tools=["erb-syntax"], basic=TPL,
     candidates=["erb_lint (needs a Ruby project)", "htmlbeautifier"])
lang("pug", "Pug", kind="template", ext=[".pug", ".jade"], tools=["prettier"], basic=dict(PLAIN, brackets=""))
fmt_tool("blade-formatter", "blade-formatter", ["blade-formatter", "--write", "{args}", "{files}"],
         check=["blade-formatter", "--check-formatted", "{args}", "{files}"],
         bin="blade-formatter", needs=["node"], install=[npm("blade-formatter@1.44.4")], license="MIT")
lang("blade", "Laravel Blade", kind="template", globs=["*.blade.php"], tools=["blade-formatter"], basic=TPL)
for _lid, _name, _ext in (("haml", "Haml", [".haml"]), ("slim", "Slim", [".slim"]),
                          ("velocity", "Apache Velocity", [".vm", ".vtl"]),
                          ("freemarker", "FreeMarker", [".ftl", ".ftlh", ".ftlx"]),
                          ("smarty", "Smarty", [".tpl"]), ("razor", "Razor", [".cshtml", ".razor"]),
                          ("asp", "Classic ASP / ASP.NET pages", [".asp", ".aspx", ".ascx", ".asax"])):
    lang(_lid, _name, kind="template", ext=_ext, basic=dict(PLAIN, brackets=""),
         candidates={"haml": ["haml-lint (gem)"], "slim": ["slim-lint (gem)"]}.get(_lid, []))
