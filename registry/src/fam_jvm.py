"""JVM: Java, JSP, Kotlin, Groovy/Gradle, Scala, Clojure, Apex."""
from core import (A_X86, C_LIKE, WS_SIGNIFICANT, det, gh, jar, lang, lex, lint_tool, npm, probe,
                  shebang_marker, tool, fmt_tool, url, version)

# ------------------------------------------------------------------ Java

GJF_ARCH = {"amd64": "x86-64", "arm64": "arm64"}
fmt_tool("google-java-format", "google-java-format",
         ["google-java-format", "--replace", "{args}", "{files}"],
         check=["google-java-format", "--dry-run", "--set-exit-if-changed", "{args}", "{files}"],
         bin="google-java-format",
         install=[gh("google/google-java-format", "v1.37.0", "google-java-format_linux-{arch}",
                     ["google-java-format"], arch=GJF_ARCH)],
         rule_args={"joiner": " "},
         defaults={"--aosp": False, "--skip-sorting-imports": False, "--skip-removing-unused-imports": False,
                   "--skip-javadoc-formatting": False},
         homepage="https://github.com/google/google-java-format", license="Apache-2.0",
         notes="native binary (no JVM needed); --aosp switches to 4-space indentation")
lint_tool("checkstyle", "Checkstyle", ["checkstyle", ["-c", "{config}"], "{args}", "{files}"],
          bin="checkstyle", needs=["java"],
          install=[jar("https://github.com/checkstyle/checkstyle/releases/download/checkstyle-14.3.0/"
                       "checkstyle-14.3.0-all.jar", "checkstyle", java_opts=["-Dfile.encoding=UTF-8"])],
          config={"file": "checkstyle.xml", "format": "checkstyle", "base": "checkstyle.xml"},
          homepage="https://checkstyle.org", license="LGPL-2.1",
          notes="base rules contain no formatting checks (formatting belongs to google-java-format)")
lint_tool("pmd", "PMD", ["pmd", "check", "--no-cache", "--no-progress", "--format", "text",
                         "--use-version", "java-{var:pmd}", ["-R", "{config}"], "{args}", "-d", "{files}"],
          bin="pmd", needs=["java"],
          install=[url("https://github.com/pmd/pmd/releases/download/pmd_releases%2F7.28.0/"
                       "pmd-dist-7.28.0-bin.zip", ["pmd"], arch=None)],
          config={"file": "pmd-ruleset.xml", "format": "pmd", "base": "pmd-ruleset.xml"},
          version_vars={"pmd": {"default": "{v}", "map": {"8": "1.8", "7": "1.7", "6": "1.6", "5": "1.5"}}},
          homepage="https://pmd.github.io", license="BSD-style",
          notes="--use-version follows languages.java.version (legacy env PMD_JAVA_VERSION)")
JAVA_VERSION = version("21", env="PMD_JAVA_VERSION", label="Java version (e.g. 8, 11, 17, 21)", detect=[
    det("pom.xml", r"<maven\.compiler\.release>\s*(\d+(?:\.\d+)?)\s*<"),
    det("pom.xml", r"<java\.version>\s*(\d+(?:\.\d+)?)\s*<"),
    det("pom.xml", r"<maven\.compiler\.source>\s*(\d+(?:\.\d+)?)\s*<"),
    det("pom.xml", r"<release>\s*(\d+)\s*</release>"),
    det("build.gradle", r"JavaLanguageVersion\.of\((\d+)\)"),
    det("build.gradle.kts", r"JavaLanguageVersion\.of\((\d+)\)"),
    det("build.gradle", r"sourceCompatibility\s*=\s*['\"]?(?:JavaVersion\.VERSION_)?(\d+(?:[._]\d+)?)"),
    det("build.gradle.kts", r"sourceCompatibility\s*=\s*JavaVersion\.VERSION_(\d+(?:_\d+)?)"),
    det(".java-version", r"^\s*(\d+(?:\.\d+)?)"),
    det(".sdkmanrc", r"^java=(\d+)"),
    det(".tool-versions", r"^java\s+\D*(\d+)"),
])
lang("java", "Java", ext=[".java"],
     tools=["google-java-format", "checkstyle", "pmd"],
     basic=lex(["//"], [("/*", "*/")], strings=('"""', '"', "'")), version=JAVA_VERSION,
     notes="syntax errors are reported by google-java-format (it refuses to format unparsable code)")

# ------------------------------------------------------------------ JSP / properties

lang("jsp", "JSP", kind="template", ext=[".jsp", ".jspf", ".jspx", ".tag"],
     tools=["qs-check-jsp"], basic=lex([], [("<%--", "--%>"), ("<!--", "-->")], strings=(), brackets=""),
     notes="no maintained JSP linter exists; balanced <% %> check + safe whitespace formatting")
lang("properties", "Java properties", kind="config", ext=[".properties"],
     tools=["qs-check-properties"], basic=dict(WS_SIGNIFICANT, no_format=True),
     notes="trailing whitespace is part of the value: never reformatted")

# ------------------------------------------------------------------ Kotlin

fmt_tool("ktlint", "ktlint (format)",
         ["ktlint", "--format", "--relative", "--log-level=error", ["--editorconfig={config}"], "{args}",
          "{files}"],
         bin="ktlint", needs=["java"], success_fix=[0, 1],
         install=[gh("pinterest/ktlint", "1.8.0", "ktlint", ["ktlint"], arch=None)],
         config={"file": ".editorconfig", "format": "editorconfig", "section": "*.{kt,kts}"},
         defaults={"ktlint_code_style": "ktlint_official", "max_line_length": 120, "indent_size": 4},
         homepage="https://pinterest.github.io/ktlint", license="MIT",
         notes="exit 1 after --format only means unfixable lint findings remain (reported by detekt)")
lint_tool("detekt", "detekt", ["detekt-cli", "--build-upon-default-config", ["--config", "{config}"],
                               "{args}", "--input", "{files_csv}"],
          bin="detekt-cli", needs=["java"],
          install=[url("https://github.com/detekt/detekt/releases/download/v1.23.8/detekt-cli-1.23.8.zip",
                       ["detekt-cli"], arch=None)],
          config={"file": "detekt.yml", "format": "yaml"},
          defaults={"complexity": {"LongMethod": {"threshold": 80},
                                   "LongParameterList": {"functionThreshold": 7},
                                   "CyclomaticComplexMethod": {"threshold": 12}},
                    "style": {"MaxLineLength": {"active": False}, "NewLineAtEndOfFile": {"active": False},
                              "WildcardImport": {"active": True}}},
          homepage="https://detekt.dev", license="Apache-2.0",
          notes="formatting rules off (ktlint owns them); thresholds aligned with Checkstyle")
lang("kotlin", "Kotlin", ext=[".kt", ".kts"], tools=["ktlint", "detekt"],
     basic=lex(["//"], [("/*", "*/")], strings=('"""', '"', "'"), nested=True),
     marker=shebang_marker("#!/usr/bin/env kotlin"), shebang=[r"\bkotlin\b"])

# ------------------------------------------------------------------ Groovy / Gradle / Jenkinsfile

GROOVY_NPM = npm("npm-groovy-lint@18.0.0")
fmt_tool("npm-groovy-lint-format", "npm-groovy-lint (format)",
         ["npm-groovy-lint", "--format", "--noserver", "--failon", "none", "--output", "txt",
          ["--config", "{config}"], "{args}", "{files}"],
         bin="npm-groovy-lint", needs=["node", "java"], install=[GROOVY_NPM], timeout=600,
         config={"file": ".groovylintrc.json", "format": "json"},
         defaults={"extends": "recommended", "rules": {"CompileStatic": "off"}},
         homepage="https://github.com/nvuillam/npm-groovy-lint", license="GPL-3.0")
lint_tool("npm-groovy-lint", "npm-groovy-lint (CodeNarc)",
          ["npm-groovy-lint", "--noserver", "--failon", "error", "--output", "txt",
           ["--config", "{config}"], "{args}", "{files}"],
          bin="npm-groovy-lint", needs=["node", "java"], install=[GROOVY_NPM], timeout=600,
          config={"file": ".groovylintrc.json", "format": "json", "inherit": "npm-groovy-lint-format"})
lang("groovy", "Groovy / Gradle / Jenkinsfile", ext=[".groovy", ".gvy", ".gy", ".gsh", ".gradle"],
     names=["Jenkinsfile"], globs=["Jenkinsfile.*", "*.Jenkinsfile"], shebang=[r"\bgroovy\b"],
     tools=["npm-groovy-lint-format", "npm-groovy-lint"],
     basic=lex(["//"], [("/*", "*/")], strings=('"""', "'''", '"', "'")))

# ------------------------------------------------------------------ Scala

fmt_tool("scalafmt", "scalafmt",
         ["scalafmt", "--non-interactive", "--quiet", ["--config", "{config}"], "{args}", "{files}"],
         check=["scalafmt", "--non-interactive", "--quiet", "--test", ["--config", "{config}"], "{args}",
                "{files}"],
         bin="scalafmt",
         install=[gh("scalameta/scalafmt", "v3.11.5", "scalafmt-{arch}-pc-linux.zip", ["scalafmt"], arch=A_X86)],
         config={"file": ".scalafmt.conf", "format": "hocon"},
         defaults={"version": "3.11.5", "maxColumn": 100},
         version_rules={"runner.dialect": "{var:dialect}"},
         version_vars={"dialect": {"default": "scala213", "map": {"3": "scala3", "2.13": "scala213",
                                                                   "2.12": "scala212", "2.11": "scala211"}}},
         homepage="https://scalameta.org/scalafmt", license="Apache-2.0",
         notes="'version' must match the installed binary (offline: no download of other versions)")
lang("scala", "Scala", ext=[".scala", ".sc", ".sbt"], tools=["scalafmt"],
     basic=lex(["//"], [("/*", "*/")], strings=('"""', '"'), nested=True),
     version=version("2.13", env="QS_SCALA_VERSION", label="Scala version (2.12, 2.13, 3)", detect=[
         det("build.sbt", r'scalaVersion\s*:=\s*"(\d+\.\d+)'),
         det("build.sc", r'scalaVersion\s*=\s*"(\d+\.\d+)'),
         det("project.scala", r'//>\s*using\s+scala\s+"?(\d+(?:\.\d+)?)')]),
     candidates=["scalafix (needs a SemanticDB build)"])

# ------------------------------------------------------------------ Clojure

fmt_tool("cljfmt", "cljfmt", ["cljfmt", "fix", ["--config", "{config}"], "{args}", "{files}"],
         check=["cljfmt", "check", ["--config", "{config}"], "{args}", "{files}"],
         bin="cljfmt",
         install=[gh("weavejester/cljfmt", "0.16.6", "cljfmt-{tag}-linux-{arch}.tar.gz", ["cljfmt"],
                     arch={"amd64": "amd64", "arm64": "aarch64"})],
         config={"file": ".cljfmt.edn", "format": "edn"}, license="EPL-1.0")
lint_tool("clj-kondo", "clj-kondo", ["clj-kondo", "--parallel", ["--config", "{config}"], "{args}",
                                     "--lint", "{files}"],
          bin="clj-kondo",
          install=[gh("clj-kondo/clj-kondo", "v2026.08.04", "clj-kondo-{ver}-linux-{arch}.zip", ["clj-kondo"],
                      arch={"amd64": "static-amd64", "arm64": "aarch64"})],
          config={"file": "config.edn", "format": "edn"},
          defaults={"output": {"pattern": "{{filename}}:{{row}}:{{col}}: {{level}}: {{message}}"}},
          success=[0, 2], license="EPL-1.0", notes="exit 2 = warnings only; 3 = errors")
lang("clojure", "Clojure / EDN", ext=[".clj", ".cljs", ".cljc", ".cljd", ".edn", ".bb"],
     shebang=[r"\bbb\b", r"\bclojure\b"], tools=["cljfmt", "clj-kondo"],
     basic=lex([";"], [], strings=('"',), char_prefix="\\"))

# ------------------------------------------------------------------ Apex (Salesforce)

fmt_tool("prettier-apex", "Prettier (Apex)",
         ["prettier", "--write", "--log-level", "warn", "--no-editorconfig", "--plugin", "prettier-plugin-apex",
          ["--config", "{config}"], "{args}", "{files}"],
         check=["prettier", "--check", "--log-level", "warn", "--no-editorconfig", "--plugin",
                "prettier-plugin-apex", ["--config", "{config}"], "{args}", "{files}"],
         bin="prettier", cwd="npm", needs=["node", "java"], install=[npm("prettier@3.9.10",
                                                                          "prettier-plugin-apex@2.3.0")],
         config={"file": "prettierrc.json", "format": "json", "base": "web/prettierrc.json"})
lint_tool("pmd-apex", "PMD (Apex rules)", ["pmd", "check", "--no-cache", "--no-progress", "--format", "text",
                                           ["-R", "{config}"], "{args}", "-d", "{files}"],
          bin="pmd", needs=["java"],
          install=[url("https://github.com/pmd/pmd/releases/download/pmd_releases%2F7.28.0/"
                       "pmd-dist-7.28.0-bin.zip", ["pmd"], arch=None)],
          config={"file": "pmd-apex.xml", "format": "pmd", "base": "pmd-apex.xml"})
lang("apex", "Apex (Salesforce)", ext=[".cls", ".trigger", ".apex"],
     probe=[probe(r"\b(public|private|global)\s+(with|without|inherited)\s+sharing\b", 5),
            probe(r"@(AuraEnabled|IsTest|TestVisible|InvocableMethod)\b", 5),
            probe(r"\bSystem\.debug\(|\[\s*SELECT\b", 3)],
     tools=["prettier-apex", "pmd-apex"], basic=C_LIKE,
     marker={"modeline": "// -*- mode: apex -*-"})
