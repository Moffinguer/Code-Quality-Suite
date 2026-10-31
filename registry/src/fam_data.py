"""Data, configuration, infrastructure, build files and SQL."""
from core import (A_GO, A_X64, A_X86, A_X86ARM, A_AMDONLY, C_LIKE, HASH, PLAIN, SQL_LIKE, WS_SIGNIFICANT, apt,
                  det, gh, lang, lex, lint_tool, npm, pip, probe, script, subtype, syntax_tool, tool, fmt_tool,
                  url, version)

YAML_LEX = dict(PLAIN, line_comment=["#"])

# ------------------------------------------------------------------ JSON-schema based validators (offline)

CJS = pip("check-jsonschema==0.38.2", "check-jsonschema")
for _sid, _schema in (("meta", None), ("renovate", "vendor.renovate"), ("github-actions", "vendor.github-actions"),
                      ("dependabot", "vendor.dependabot"), ("gitlab-ci", "vendor.gitlab-ci"),
                      ("azure-pipelines", "vendor.azure-pipelines"),
                      ("bitbucket-pipelines", "vendor.bitbucket-pipelines"), ("circle-ci", "vendor.circle-ci"),
                      ("taskfile", "vendor.taskfile"), ("readthedocs", "vendor.readthedocs"),
                      ("travis", "vendor.travis"), ("woodpecker-ci", "vendor.woodpecker-ci"),
                      ("drone-ci", "vendor.drone-ci"), ("cloudbuild", "vendor.cloudbuild"),
                      ("mergify", "vendor.mergify"), ("buildkite", "vendor.buildkite"),
                      ("codecov", "vendor.codecov"), ("citation", "vendor.citation-file-format"),
                      ("github-issue-forms", "vendor.github-issue-forms"),
                      ("github-issue-config", "vendor.github-issue-config"), ("snapcraft", "vendor.snapcraft")):
    cmd = (["check-jsonschema", "--check-metaschema", "--output-format", "text", "{files}"] if _schema is None else
           ["check-jsonschema", "--builtin-schema", _schema, "--output-format", "text", "{files}"])
    lint_tool(f"check-jsonschema-{_sid}", f"check-jsonschema ({_schema or 'metaschema'})", cmd,
              bin="check-jsonschema", install=[CJS], license="Apache-2.0",
              notes="schemas are vendored in the package: works offline")

lint_tool("cfn-lint", "cfn-lint (CloudFormation)", ["cfn-lint", "--format", "parseable", "{args}", "--", "{files}"],
          bin="cfn-lint", install=[pip("cfn-lint==1.57.2", "cfn-lint")], license="MIT-0")

# ------------------------------------------------------------------ YAML

fmt_tool("yamlfmt", "yamlfmt", ["yamlfmt", ["-conf", "{config}"], "{files}"],
         check=["yamlfmt", "-lint", ["-conf", "{config}"], "{files}"], bin="yamlfmt",
         install=[gh("google/yamlfmt", "v0.21.0", "yamlfmt_{ver}_Linux_{arch}.tar.gz", ["yamlfmt"], arch=A_X86ARM)],
         config={"file": ".yamlfmt", "format": "yaml"},
         defaults={"formatter": {"type": "basic", "retain_line_breaks_single": True, "pad_line_comments": 1,
                                 "include_document_start": False, "scan_folded_as_literal": True}},
         homepage="https://github.com/google/yamlfmt", license="Apache-2.0")
lint_tool("yamllint", "yamllint", ["yamllint", "--strict", "--format", "parsable", ["-c", "{config}"], "{files}"],
          bin="yamllint", install=[pip("yamllint==1.38.0", "yamllint")],
          config={"file": ".yamllint.yaml", "format": "yaml"},
          defaults={"extends": "default",
                    "rules": {"document-start": "disable", "line-length": "disable",
                              "indentation": {"spaces": "consistent", "indent-sequences": "whatever"},
                              "comments": {"min-spaces-from-content": 1},
                              "truthy": {"check-keys": False}}},
          license="GPL-3.0", notes="document-start/line-length/indentation left to yamlfmt to avoid clashes")
lint_tool("actionlint", "actionlint", ["actionlint", "-no-color", "-oneline", "{files}"], bin="actionlint",
          install=[pip("actionlint-py==1.7.12.25", "actionlint"), pip("shellcheck-py==0.11.0.1", "shellcheck")],
          license="MIT", notes="also runs ShellCheck on run: blocks")
lint_tool("zizmor", "zizmor (Actions security)", ["zizmor", "--offline", "--no-progress", "--format", "plain",
                                                  "{files}"], bin="zizmor", install=[pip("zizmor==1.30.1", "zizmor")],
          success=[0], license="MIT")
lint_tool("dclint", "DCLint (Docker Compose)", ["dclint", "--quiet", ["-c", "{config}"], "{files}"], bin="dclint",
          needs=["node"], install=[npm("dclint@3.1.0")], config={"file": ".dclintrc.json", "format": "json"},
          defaults={"rules": {"service-keys-order": 0, "services-alphabetical-order": 0}},
          notes="ordering rules off: they rewrite layout, which yamlfmt owns")
lint_tool("kube-linter", "KubeLinter", ["kube-linter", "lint", "--format", "plain", ["--config", "{config}"],
                                        "{files}"], bin="kube-linter",
          install=[gh("stackrox/kube-linter", "v0.8.3", "kube-linter-linux{arch}.tar.gz", ["kube-linter"],
                      arch={"amd64": "", "arm64": "_arm64"})],
          config={"file": ".kube-linter.yaml", "format": "yaml"}, defaults={"checks": {"addAllBuiltIn": False}},
          license="Apache-2.0")
lint_tool("helm-lint", "helm lint", ["helm", "lint", "--quiet", "{group}"], bin="helm", group_by="Chart.yaml",
          cwd="group", scope="project",
          install=[url("https://get.helm.sh/helm-v4.3.0-linux-{arch}.tar.gz", ["helm"], arch=A_GO)],
          offline_skip=[r"dependencies? .* (missing|not found)", r"no repository definition"])
lint_tool("spectral", "Spectral (OpenAPI/AsyncAPI)", ["spectral", "lint", "--format", "text", "--quiet",
                                                      ["--ruleset", "{config}"], "{files}"],
          bin="spectral", cwd="npm", needs=["node"], install=[npm("@stoplight/spectral-cli@6.17.0")],
          config={"file": ".spectral.json", "format": "json"}, defaults={"extends": ["spectral:oas", "spectral:asyncapi"]},
          license="Apache-2.0", notes="built-in rulesets only: no remote rulesets are fetched")
lint_tool("ansible-lint", "ansible-lint", ["ansible-lint", "--offline", "--nocolor", "-p", "{files}"],
          bin="ansible-lint", install=[pip("ansible-lint==26.9.0", "ansible-lint")], timeout=900,
          offline_skip=[r"couldn't resolve module/action", r"collection .* not found"])
HELM_TEMPLATE = subtype("templated", "Templated YAML (Helm / Jinja)", content=[r"\{\{.*\}\}|\{%.*%\}"],
                        exclude_roles=["syntax", "format", "lint", "deep"])
lang("yaml", "YAML", kind="data", ext=[".yaml", ".yml"],
     names=[".clang-format", ".clang-tidy", ".yamllint", ".prettierrc.yaml", ".gemrc", ".condarc", "pnpm-lock.yaml",
            "pubspec.lock", "CITATION.cff"],
     tools=["qs-check-yaml", "yamlfmt", "yamllint"], basic=YAML_LEX,
     subtypes=[
         subtype("lockfile", "Lockfile", names=["pnpm-lock.yaml", "pubspec.lock"],
                 exclude_roles=["marker", "format", "lint", "deep"]),
         HELM_TEMPLATE,
         subtype("helm-chart", "Helm chart metadata", names=["Chart.yaml"], tools=["helm-lint"]),
         subtype("github-workflow", "GitHub Actions workflow", globs=[".github/workflows/*.yml", ".github/workflows/*.yaml"],
                 tools=["actionlint", "zizmor"]),
         subtype("github-action", "GitHub composite action", names=["action.yml", "action.yaml"],
                 tools=["check-jsonschema-github-actions"]),
         subtype("dependabot", "Dependabot", globs=[".github/dependabot.yml", ".github/dependabot.yaml"],
                 tools=["check-jsonschema-dependabot"]),
         subtype("gitlab-ci", "GitLab CI", names=[".gitlab-ci.yml"], tools=["check-jsonschema-gitlab-ci"]),
         subtype("azure-pipelines", "Azure Pipelines", globs=["azure-pipelines*.yml", "azure-pipelines*.yaml"],
                 tools=["check-jsonschema-azure-pipelines"]),
         subtype("bitbucket", "Bitbucket Pipelines", names=["bitbucket-pipelines.yml"],
                 tools=["check-jsonschema-bitbucket-pipelines"]),
         subtype("circleci", "CircleCI", globs=[".circleci/config.yml"], tools=["check-jsonschema-circle-ci"]),
         subtype("taskfile", "Taskfile", names=["Taskfile.yml", "Taskfile.yaml", "taskfile.yml"],
                 tools=["check-jsonschema-taskfile"]),
         subtype("readthedocs", "Read the Docs", names=[".readthedocs.yml", ".readthedocs.yaml"],
                 tools=["check-jsonschema-readthedocs"]),
         subtype("travis", "Travis CI", names=[".travis.yml"], tools=["check-jsonschema-travis"]),
         subtype("woodpecker", "Woodpecker CI", globs=[".woodpecker.yml", ".woodpecker/*.yml"],
                 tools=["check-jsonschema-woodpecker-ci"]),
         subtype("drone", "Drone CI", names=[".drone.yml"], tools=["check-jsonschema-drone-ci"]),
         subtype("cloudbuild", "Google Cloud Build", names=["cloudbuild.yaml", "cloudbuild.yml"],
                 tools=["check-jsonschema-cloudbuild"]),
         subtype("mergify", "Mergify", names=[".mergify.yml"], tools=["check-jsonschema-mergify"]),
         subtype("buildkite", "Buildkite", globs=[".buildkite/pipeline*.yml"], tools=["check-jsonschema-buildkite"]),
         subtype("codecov", "Codecov", names=["codecov.yml", ".codecov.yml"], tools=["check-jsonschema-codecov"]),
         subtype("citation", "CITATION.cff", names=["CITATION.cff"], tools=["check-jsonschema-citation"]),
         subtype("github-issue-config", "GitHub issue chooser", globs=[".github/ISSUE_TEMPLATE/config.yml"],
                 tools=["check-jsonschema-github-issue-config"]),
         subtype("github-issue-form", "GitHub issue form", globs=[".github/ISSUE_TEMPLATE/*.yml"],
                 content=[r"^body:"], tools=["check-jsonschema-github-issue-forms"]),
         subtype("snapcraft", "Snapcraft", names=["snapcraft.yaml"], tools=["check-jsonschema-snapcraft"]),
         subtype("compose", "Docker Compose", globs=["docker-compose*.yml", "docker-compose*.yaml", "compose*.yml",
                                                     "compose*.yaml"], tools=["dclint"]),
         subtype("kubernetes", "Kubernetes manifest", content=[r"^apiVersion:\s*\S+", r"^kind:\s*[A-Z]\w+"],
                 tools=["kube-linter"]),
         subtype("openapi", "OpenAPI / AsyncAPI", content=[r"^(openapi|swagger|asyncapi):\s*['\"]?\d"],
                 tools=["spectral"]),
         subtype("cloudformation", "CloudFormation", content=[r"AWSTemplateFormatVersion|Type:\s*['\"]?AWS::"],
                 tools=["cfn-lint"]),
         subtype("ansible", "Ansible", globs=["playbooks/*.yml", "playbooks/*.yaml", "roles/*/tasks/*.yml",
                                              "roles/*/handlers/*.yml", "site.yml", "playbook*.yml"],
                 tools=["ansible-lint"]),
     ])
lint_tool("salt-lint", "salt-lint", ["salt-lint", "--nocolor", "{files}"], bin="salt-lint",
          install=[pip("salt-lint==0.9.2", "salt-lint")], license="MIT")
lang("salt", "SaltStack states", kind="config", ext=[".sls"], tools=["salt-lint"], basic=YAML_LEX,
     notes="Jinja + YAML: never parsed as plain YAML")

# ------------------------------------------------------------------ TOML / INI / env / properties-like

TAPLO = pip("taplo==0.9.3", "taplo")
fmt_tool("taplo-fmt", "Taplo (format)", ["taplo", "fmt", ["--config", "{config}"], "{files}"],
         check=["taplo", "fmt", "--check", ["--config", "{config}"], "{files}"], bin="taplo", install=[TAPLO],
         config={"file": ".taplo.toml", "format": "toml"},
         defaults={"formatting": {"align_entries": False, "reorder_keys": False, "array_auto_expand": True,
                                  "column_width": 100}},
         env={"RUST_LOG": "error"}, license="MIT")
lint_tool("taplo-lint", "Taplo (lint)", ["taplo", "lint", "--no-schema", "{files}"], bin="taplo", install=[TAPLO],
          env={"RUST_LOG": "error"}, notes="--no-schema: schema catalogs would need the network")
lang("toml", "TOML", kind="data", ext=[".toml"], names=["Cargo.lock", "poetry.lock", "uv.lock", "Pipfile"],
     tools=["qs-check-toml", "taplo-fmt", "taplo-lint"], basic=YAML_LEX,
     subtypes=[subtype("lockfile", "Lockfile", names=["Cargo.lock", "poetry.lock", "uv.lock", "pdm.lock"],
                       exclude_roles=["marker", "format", "lint", "deep"])])
lang("ini", "INI", kind="config", ext=[".ini", ".cfg", ".cnf", ".prefs", ".inf", ".reg", ".url", ".lnk.ini"],
     names=["setup.cfg", "tox.ini", ".coveragerc", ".flake8", ".pylintrc", "pylintrc", "mypy.ini", "pytest.ini",
            ".npmrc", ".yarnrc", ".pypirc", ".isort.cfg", ".bumpversion.cfg", "alembic.ini", "php.ini",
            ".sqlfluff", ".editorconfig", ".perlcriticrc", ".gitlint", ".pep8", ".pydocstyle"],
     probe=[probe(r"^\s*\[[^\]\n]+\]\s*$", 3), probe(r"^\s*[\w.-]+\s*[=:]", 1)],
     default_for_ambiguous=True, tools=["qs-check-ini"], basic=dict(PLAIN, line_comment=["#", ";"]))
lang("desktop-entry", "Desktop entries / systemd-like INI", kind="config", ext=[".desktop", ".directory"],
     tools=["qs-check-ini-loose"], basic=PLAIN)
lint_tool("systemdlint", "systemdlint", ["systemdlint", "--norootfs", "--messageformat",
                                          "{path}:{line}:{severity}:{id}:{msg}", "{files}"],
          bin="systemdlint", install=[pip("systemdlint==1.4.0", "systemdlint")], level="strict",
          default_enabled=False,
          notes="opt-in: several Security.* checks (Delegate, User=nobody) do not fit ordinary services")
lang("systemd", "systemd units", kind="config",
     ext=[".service", ".socket", ".timer", ".mount", ".automount", ".path", ".target", ".slice", ".scope",
          ".swap", ".network", ".netdev", ".link", ".container", ".volume", ".kube"],
     tools=["qs-check-ini-loose", "systemdlint"], basic=PLAIN)
DOTENV = gh("dotenv-linter/dotenv-linter", "v4.0.0", "dotenv-linter-linux-{arch}.tar.gz", ["dotenv-linter"],
            arch=A_X86)
# why env: v4 checks for updates on every run (the container is offline)
fmt_tool("dotenv-linter-fix", "dotenv-linter fix", ["dotenv-linter", "fix", "--no-backup", "--quiet", "{args}",
                                                    "{files}"],
         check="diff", bin="dotenv-linter", install=[DOTENV], rule_args={"joiner": " ", "aliases": {"--skip": "--ignore-checks"}},
         defaults={"--ignore-checks": ["UnorderedKey"]}, env={"DOTENV_LINTER_SKIP_UPDATES": "1"},
         notes="UnorderedKey skipped: reordering keys can break ${VAR} expansion order (v4: --ignore-checks)")
lint_tool("dotenv-linter", "dotenv-linter", ["dotenv-linter", "check", "--quiet", "{args}", "{files}"],
          bin="dotenv-linter", install=[DOTENV], rule_args={"joiner": " ", "aliases": {"--skip": "--ignore-checks"}},
          config={"inherit": "dotenv-linter-fix"},
          env={"DOTENV_LINTER_SKIP_UPDATES": "1"})
lang("dotenv", "dotenv", kind="config", ext=[".env"], names=[".env"], globs=[".env.*", "*.env", ".envrc"],
     tools=["dotenv-linter-fix", "dotenv-linter"], basic=dict(PLAIN, line_comment=["#"]))
lang("csv", "CSV", kind="data", ext=[".csv"], tools=["qs-check-csv"], basic=dict(WS_SIGNIFICANT, no_format=True))
lang("tsv", "TSV", kind="data", ext=[".tsv", ".tab"], tools=["qs-check-tsv"], basic=dict(WS_SIGNIFICANT, no_format=True))
syntax_tool("git-config-parse", "git config --list (parse)", ["git", "config", "--file", "{file}", "--list"],
            bin="git", batch=False)
lang("gitconfig", "Git config", kind="config", names=[".gitconfig", ".gitmodules", "gitconfig"],
     globs=[".git-config", "*.gitconfig"], tools=["git-config-parse"], basic=dict(PLAIN, line_comment=["#", ";"]))
lang("ignore-list", "Ignore / attribute lists", kind="config",
     names=[".gitignore", ".gitattributes", ".dockerignore", ".npmignore", ".prettierignore", ".eslintignore",
            ".stylelintignore", ".helmignore", ".gcloudignore", ".vscodeignore", "CODEOWNERS", ".mailmap",
            ".hgignore"],
     basic=dict(WS_SIGNIFICANT, no_format=True), notes="escaped trailing spaces are meaningful: never reformatted")

# ------------------------------------------------------------------ XML

syntax_tool("xmllint-wf", "xmllint (well-formed)", ["xmllint", "--noout", "--nonet", "{files}"], bin="xmllint",
            install=[apt("libxml2-utils")])
tool("xmllint-format", "format", "xmllint --format", {"stdout": ["xmllint", "--format", "--nonet", "{file}"]},
     bin="xmllint", install=[apt("libxml2-utils")], env_from_rules={"XMLLINT_INDENT": {"rule": "indent", "repeat": " "}},
         defaults={"indent": 2},
         notes="kept from v1 (XML_FORMAT/XML_INDENT); disable it for XML where whitespace is content")
tool("xmllint-schema", "lint", "xmllint (XSD validation)",
     {"check": ["xmllint", "--noout", "--nonet", "--schema", "{rule:schema}", "{files}"]}, bin="xmllint",
     install=[apt("libxml2-utils")], requires_rule="schema", defaults={"schema": ""},
     notes="set rules.schema to a repository XSD path (v1: XML_SCHEMA)")
lang("xml", "XML", kind="markup",
     ext=[".xml", ".xsd", ".xsl", ".xslt", ".svg", ".pom", ".jrxml", ".xaml", ".csproj", ".vbproj", ".fsproj",
          ".vcxproj", ".props", ".targets", ".resx", ".nuspec", ".wsdl", ".rss", ".atom", ".kml", ".gpx", ".xliff",
          ".xlf", ".tld", ".ui", ".glade", ".launch", ".plist", ".config", ".manifest", ".ts", ".dtd", ".xsl-fo",
          ".fxml", ".mxml", ".storyboard", ".xib", ".iml", ".rdf", ".owl", ".sch", ".bpmn", ".dmn", ".drawio"],
     names=["pom.xml", "web.xml", "persistence.xml", "beans.xml", "log4j2.xml", "logback.xml"],
     probe=[probe(r"\A\s*(<\?xml|<!DOCTYPE|<[A-Za-z][\w:.-]*[\s>])", 10)],
     tools=["xmllint-wf", "xmllint-format", "xmllint-schema"],
     basic=lex([], [("<!--", "-->")], strings=(), brackets=""),
     subtypes=[subtype("drawio", "draw.io diagram", globs=["*.drawio"], exclude_roles=["format"])])

# ------------------------------------------------------------------ SQL

SQLFLUFF = pip("sqlfluff==4.4.0", "sqlfluff")
fmt_tool("sqlfluff-format", "SQLFluff (format)",
         ["sqlfluff", "format", "--dialect", "{v}", "--processes", "1", "--nocolor", ["--config", "{config}"], "{files}"],
         check="diff", bin="sqlfluff", install=[SQLFLUFF], success_fix=[0, 1],
         config={"file": ".sqlfluff", "format": "ini", "base": "sql/sqlfluff.cfg"},
         notes="dialect comes from languages.sql.version (v1: SQL_DIALECT); exit 1 = unfixable layout left")
lint_tool("sqlfluff", "SQLFluff (lint)", ["sqlfluff", "lint", "--dialect", "{v}", "--processes", "1", "--nocolor",
                                          "--disable-progress-bar", ["--config", "{config}"], "{files}"],
          bin="sqlfluff", install=[SQLFLUFF],
          config={"file": ".sqlfluff", "format": "ini", "base": "sql/sqlfluff.cfg", "inherit": "sqlfluff-format"})
lang("sql", "SQL", kind="query", ext=[".sql", ".ddl", ".dml", ".pgsql", ".psql", ".mysql", ".tsql", ".hql", ".bql"],
     tools=["sqlfluff-format", "sqlfluff"], basic=SQL_LIKE,
     version=version("oracle", env="SQL_DIALECT", label="SQL dialect (oracle, postgres, mysql, tsql, ansi, "
                     "sqlite, bigquery, snowflake, db2, ...)",
                     choices=["ansi", "athena", "bigquery", "clickhouse", "databricks", "db2", "duckdb", "exasol",
                              "greenplum", "hive", "impala", "mariadb", "materialize", "mysql", "oracle", "postgres",
                              "redshift", "snowflake", "soql", "sparksql", "sqlite", "starrocks", "teradata", "trino",
                              "tsql", "vertica"]))
lang("plsql", "PL/SQL packages", kind="query",
     ext=[".pks", ".pkb", ".pls", ".plb", ".pck", ".prc", ".fnc", ".trg", ".tps", ".tpb"],
     basic=dict(SQL_LIKE, brackets="()"),
     candidates=["SQLFluff oracle dialect (partial PL/SQL support)", "ZPA (needs SonarQube)"])

# ------------------------------------------------------------------ IDL / config languages

BUF = npm("@bufbuild/buf@1.73.0")
fmt_tool("buf-format", "buf format", ["buf", "format", "-w", "{file}"], check=["buf", "format", "-d", "--exit-code",
                                                                              "{file}"],
         bin="buf", needs=["node"], install=[BUF], batch=False)
lint_tool("buf-lint", "buf lint", ["buf", "lint", ["--config", "{config}"], "{file}"], bin="buf", needs=["node"],
          install=[BUF], batch=False, config={"file": "buf.yaml", "format": "yaml"},
          defaults={"version": "v2", "lint": {"use": ["STANDARD"], "except": ["PACKAGE_DIRECTORY_MATCH",
                                                                              "PACKAGE_VERSION_SUFFIX"]}},
          offline_skip=[r"failure to fetch", r"module .* not found", r"could not resolve"],
          skip_on=[r"import .* file does not exist"], skip_why="imports resolved outside the file")
lang("protobuf", "Protocol Buffers", kind="data", ext=[".proto"], tools=["buf-format", "buf-lint"], basic=C_LIKE)
for _lid, _name, _ext in (("thrift", "Thrift", [".thrift"]), ("capnp", "Cap'n Proto", [".capnp"]),
                          ("flatbuffers", "FlatBuffers", [".fbs"]), ("asn1", "ASN.1", [".asn", ".asn1"]),
                          ("wit", "WebAssembly Interface Types", [".wit"]),
                          ("textproto", "Protobuf text format", [".textproto", ".pbtxt", ".txtpb"])):
    lang(_lid, _name, kind="data", ext=_ext, basic=C_LIKE)
JSONNET = gh("google/go-jsonnet", "v0.22.0", "go-jsonnet_{ver}_linux_{arch}.tar.gz",
             ["jsonnet", "jsonnetfmt", "jsonnet-lint"], arch=A_GO)
fmt_tool("jsonnetfmt", "jsonnetfmt", ["jsonnetfmt", "-i", "{files}"], check=["jsonnetfmt", "--test", "{files}"],
         bin="jsonnetfmt", install=[JSONNET])
lint_tool("jsonnet-lint", "jsonnet-lint", ["jsonnet-lint", "-J", "{root}", "{file}"], bin="jsonnet-lint",
          install=[JSONNET], batch=False)
lang("jsonnet", "Jsonnet", kind="data", ext=[".jsonnet", ".libsonnet"], tools=["jsonnetfmt", "jsonnet-lint"],
     basic=lex(["//", "#"], [("/*", "*/")], strings=('"', "'")))
CUE = gh("cue-lang/cue", "v0.17.1", "cue_{tag}_linux_{arch}.tar.gz", ["cue"], arch=A_GO)
fmt_tool("cue-fmt", "cue fmt", ["cue", "fmt", "{files}"], bin="cue", install=[CUE])
lint_tool("cue-vet", "cue vet", ["cue", "vet", "{file}"], bin="cue", install=[CUE], batch=False,
          offline_skip=[r"cannot find package", r"module .* not found", r"cannot fetch"])
lang("cue", "CUE", kind="data", ext=[".cue"], tools=["cue-fmt", "cue-vet"], basic=lex(["//"], [], strings=('"""', '"')))
OPA = gh("open-policy-agent/opa", "v1.21.1", "opa_linux_{arch}_static", ["opa"], arch=A_GO)
syntax_tool("opa-check", "opa check", ["opa", "check", "{files}"], bin="opa", install=[OPA])
fmt_tool("opa-fmt", "opa fmt", ["opa", "fmt", "-w", "{files}"], check=["opa", "fmt", "--fail", "-l", "{files}"],
         bin="opa", install=[OPA])
lint_tool("regal", "Regal", ["regal", "lint", "--format", "compact", "{files}"], bin="regal",
          install=[gh("open-policy-agent/regal", "v0.43.0", "regal_Linux_{arch}", ["regal"], arch=A_X86ARM)],
          license="Apache-2.0")
lang("rego", "Rego (OPA)", kind="config", ext=[".rego"], tools=["opa-check", "opa-fmt", "regal"],
     basic=lex(["#"], [], strings=('"',), raw=[("`", "`")]))
fmt_tool("nixfmt", "nixfmt", ["nixfmt", "{files}"], check=["nixfmt", "--check", "{files}"], bin="nixfmt",
         install=[gh("NixOS/nixfmt", "v1.5.0", "nixfmt", ["nixfmt"], arch=A_AMDONLY)], license="MPL-2.0",
         notes="the official release ships an x86_64 static binary only")
lang("nix", "Nix", kind="config", ext=[".nix"], tools=["nixfmt"], basic=lex(["#"], [("/*", "*/")], strings=('"',)),
     candidates=["statix", "deadnix (no prebuilt binaries outside Nix)"])
BUILDIFIER = gh("bazelbuild/buildtools", "v10.1.0", "buildifier-linux-{arch}", ["buildifier"], arch=A_GO)
fmt_tool("buildifier", "buildifier", ["buildifier", "{files}"], check=["buildifier", "-mode=check", "{files}"],
         bin="buildifier", install=[BUILDIFIER])
lint_tool("buildifier-lint", "buildifier -lint", ["buildifier", "-lint=warn", "-mode=check", "{files}"],
          bin="buildifier", install=[BUILDIFIER])
lang("starlark", "Starlark / Bazel", kind="build", ext=[".bzl", ".bazel", ".star", ".sky"],
     names=["BUILD", "WORKSPACE", "MODULE.bazel", "WORKSPACE.bazel", "Tiltfile", "BUCK"],
     tools=["buildifier", "buildifier-lint"], basic=lex(["#"], [], strings=('"""', "'''", '"', "'")))

# ------------------------------------------------------------------ infrastructure as code

TOFU = gh("opentofu/opentofu", "v1.13.1", "tofu_{ver}_linux_{arch}.tar.gz", ["tofu"], arch=A_GO)
fmt_tool("tofu-fmt", "tofu fmt (OpenTofu)", ["tofu", "fmt", "-no-color", "{files}"],
         check=["tofu", "fmt", "-check", "-diff", "-no-color", "{files}"], bin="tofu", install=[TOFU],
         license="MPL-2.0", notes="OpenTofu: same formatter as terraform fmt, open-source licence")
lint_tool("tflint", "TFLint", ["tflint", "--no-color", "--format", "compact", ["--config", "{config}"]],
          bin="tflint", group_by="*.tf", cwd="group", scope="project",
          install=[gh("terraform-linters/tflint", "v0.64.0", "tflint_linux_{arch}.zip", ["tflint"], arch=A_GO)],
          config={"file": ".tflint.hcl", "format": "hcl"},
          defaults={"plugin": {"terraform": {"enabled": True, "preset": "recommended"}}},
          offline_skip=[r"plugin .* not found", r"Failed to initialize plugins"],
          notes="bundled terraform ruleset only (no plugin downloads)")
lang("terraform", "Terraform / OpenTofu", kind="infra", ext=[".tf", ".tfvars", ".tftest.hcl", ".tofu"],
     tools=["tofu-fmt", "tflint"], basic=lex(["#", "//"], [("/*", "*/")], strings=('"',), heredoc=True))
lang("hcl", "HCL (Packer, Nomad, Terragrunt, ...)", kind="config", ext=[".hcl", ".nomad", ".pkr.hcl"],
     basic=lex(["#", "//"], [("/*", "*/")], strings=('"',), heredoc=True), candidates=["hclfmt", "packer fmt"])
BICEP = gh("Azure/bicep", "v0.48.1", "bicep-linux-{arch}", ["bicep"], arch=A_X64)
fmt_tool("bicep-format", "bicep format", ["bicep", "format", "{file}"], bin="bicep", install=[BICEP], batch=False,
         env={"DOTNET_SYSTEM_GLOBALIZATION_INVARIANT": "1"})
lint_tool("bicep-lint", "bicep lint", ["bicep", "lint", "{file}"], bin="bicep", install=[BICEP], batch=False,
          env={"DOTNET_SYSTEM_GLOBALIZATION_INVARIANT": "1"},
          offline_skip=[r"Unable to restore", r"could not be restored"])
lang("bicep", "Azure Bicep", kind="infra", ext=[".bicep", ".bicepparam"], tools=["bicep-format", "bicep-lint"],
     basic=C_LIKE)
lint_tool("hadolint", "hadolint", ["hadolint", "--no-color", ["--config", "{config}"], "{files}"], bin="hadolint",
          install=[pip("hadolint-py==2.15.1.2", "hadolint"), pip("shellcheck-py==0.11.0.1", "shellcheck")],
          config={"file": ".hadolint.yaml", "format": "yaml", "base": "docker/hadolint.yaml"}, license="GPL-3.0")
fmt_tool("dockerfmt", "dockerfmt", ["dockerfmt", "--write", "{files}"], bin="dockerfmt", default_enabled=False,
         install=[gh("reteps/dockerfmt", "v0.5.4", "dockerfmt-{tag}-linux-{arch}.tar.gz", ["dockerfmt"], arch=A_GO)],
         notes="opt-in (young project): enable it in the rules file; until then the safe built-in formatting runs")
lang("dockerfile", "Dockerfile", kind="infra", ext=[".dockerfile", ".containerfile"],
     names=["Dockerfile", "Containerfile"], globs=["Dockerfile.*", "Containerfile.*", "*.Dockerfile"],
     tools=["dockerfmt", "hadolint"], basic=dict(HASH, brackets="", heredoc=True))

# ------------------------------------------------------------------ build files

fmt_tool("mbake", "mbake", ["mbake", "format", ["--config", "{config}"], "{files}"],
         check=["mbake", "format", "--check", ["--config", "{config}"], "{files}"], bin="mbake",
         install=[pip("mbake==1.4.6", "mbake")], config={"file": "bake.toml", "format": "toml", "base": "make/bake.toml"},
         license="MIT", notes="phony auto-insertion off: formatting never changes what make does")
lint_tool("checkmake", "checkmake", ["checkmake", ["--config={config}"], "{files}"], bin="checkmake",
          install=[gh("mrtazz/checkmake", "v0.3.2", "checkmake-{tag}.linux.{arch}", ["checkmake"], arch=A_GO)],
          config={"file": "checkmake.ini", "format": "ini"},
          defaults={"minphony": {"disabled": "true"}, "maxbodylength": {"maxBodyLength": "20"}})
lang("makefile", "Makefile", kind="build", ext=[".mk", ".mak", ".make"],
     names=["Makefile", "makefile", "GNUmakefile", "BSDmakefile"], globs=["Makefile.*", "*.Makefile"],
     tools=["mbake", "checkmake"], basic=dict(HASH, brackets="", strings=()))
fmt_tool("gersemi", "gersemi", ["gersemi", "-i", "{args}", "{files}"], check=["gersemi", "--check", "{args}", "{files}"],
         bin="gersemi", install=[pip("gersemi==0.29.2", "gersemi")], rule_args={"joiner": " "},
         defaults={"--line-length": 100, "--indent": 4}, license="MPL-2.0")
lang("cmake", "CMake", kind="build", ext=[".cmake"], names=["CMakeLists.txt"], tools=["gersemi"],
     basic=lex(["#"], [("#[[", "]]")], strings=('"',), brackets="()"), candidates=["cmake-lint (clashes with gersemi)"])
MESON = pip("meson==1.12.1", "meson")
fmt_tool("meson-format", "meson format", ["meson", "format", "--inplace", "{files}"],
         check=["meson", "format", "--check-only", "{files}"], bin="meson", install=[MESON])
lang("meson", "Meson", kind="build", names=["meson.build", "meson_options.txt", "meson.options"], tools=["meson-format"],
     basic=lex(["#"], [], strings=("'''", "'")))
JUST = pip("rust-just==1.58.0", "just")
syntax_tool("just-parse", "just --summary (parse)", ["just", "--justfile", "{file}", "--summary"], bin="just",
            install=[JUST], batch=False)
fmt_tool("just-fmt", "just --fmt", ["just", "--unstable", "--fmt", "--justfile", "{file}"],
         check=["just", "--unstable", "--fmt", "--check", "--justfile", "{file}"], bin="just", install=[JUST], batch=False)
lang("justfile", "justfile", kind="build", ext=[".just"], names=["justfile", "Justfile", ".justfile"],
     tools=["just-parse", "just-fmt"], basic=dict(HASH, brackets=""))

# ------------------------------------------------------------------ servers

fmt_tool("nginxfmt", "nginx-config-formatter", ["nginxfmt", "{args}", "{files}"], bin="nginxfmt",
         install=[pip("nginxfmt==1.4.0", "nginxfmt")], rule_args={"joiner": " "}, defaults={"--indent": 4})
lint_tool("gixy", "gixy (nginx security)", ["gixy", "--format", "text", "{file}"], bin="gixy", batch=False,
          install=[pip("gixy-ng==0.2.55", "gixy")], license="MPL-2.0")
NGINX_PROBE = [probe(r"^\s*(server|http|location|upstream|events|stream)\s*[^;]*\{", 5),
               probe(r"^\s*(listen|server_name|proxy_pass|root|worker_processes)\s", 3)]
lang("nginx", "nginx config", kind="config", ext=[".conf", ".nginx"], names=["nginx.conf"],
     globs=["nginx/**/*.conf", "sites-available/*", "sites-enabled/*", "conf.d/*.conf"], probe=NGINX_PROBE,
     tools=["nginxfmt", "gixy"], basic=dict(HASH, brackets="{}"), marker={"modeline": "# -*- mode: nginx -*-"})
lang("apache", "Apache httpd config", kind="config", ext=[".conf", ".htaccess"], names=[".htaccess", "httpd.conf"],
     probe=[probe(r"^\s*<(VirtualHost|Directory|IfModule|Location)\b", 5),
            probe(r"^\s*(ServerName|DocumentRoot|LoadModule|RewriteRule|RewriteEngine)\s", 3)],
     basic=dict(HASH, brackets=""))
lang("conf", "Generic .conf", kind="config", ext=[".conf"], default_for_ambiguous=True,
     basic=dict(HASH, brackets="", strings=()), notes="unknown .conf dialect: encoding/conflict checks + safe whitespace")
