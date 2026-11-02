"""Unit tests for the engine (stdlib unittest; no external tools needed).

python3 -m unittest discover -s tests/unit -v
"""

import json
import os
import re
import shutil
import sys
import tempfile
import tomllib
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import builtin  # noqa: E402
import changelog  # noqa: E402
import maven  # noqa: E402
import policy  # noqa: E402
import repofiles  # noqa: E402
import rules  # noqa: E402
import runner  # noqa: E402
import semver  # noqa: E402
import writers  # noqa: E402

import registry  # noqa: E402

# why: checked alone, mypy resolves 'registry' to the registry/ data folder, not to
# engine/registry.py (checked with engine files it resolves it right: hence unused-ignore)
REG = registry.Registry(  # type: ignore[attr-defined, unused-ignore]
    os.path.join(ROOT, "registry", "registry.json")
)
rules.bind(REG)


def read(p, mode="r"):
    """Content of a file.

    Args:
        p: the file path.
        mode: 'r' for UTF-8 text, 'rb' for bytes.

    Returns:
        str | bytes: the content.

    Raises:
        OSError: the file cannot be read.
    """
    with open(p, mode, **({} if "b" in mode else {"encoding": "utf-8"})) as fh:
        return fh.read()


def write(d, rel, text, mode="w"):
    """Write a file below a folder, creating the parent folders.

    Args:
        d: the base folder.
        rel: the relative path.
        text: the content (str, or bytes with mode 'wb').
        mode: 'w' for UTF-8 text without newline translation, 'wb' for bytes.

    Returns:
        str: the absolute path written.
    """
    p = os.path.join(d, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, mode, **({} if "b" in mode else {"encoding": "utf-8", "newline": ""})) as fh:
        fh.write(text)
    return p


class Writers(unittest.TestCase):
    def test_toml_round_trip(self):
        data = {
            "line-length": 100,
            "format": {"quote-style": "double"},
            "lint": {"select": ["E", "F"], "pylint": {"max-args": 5}},
        }
        self.assertEqual(tomllib.loads(writers.render_toml(data)), data)

    def test_flags_round_trip_perltidy(self):
        base = read(os.path.join(ROOT, "config", "perl", "perltidyrc"))
        parsed = writers.parse_flags(base)
        self.assertIs(parsed["line-up-parentheses"], True)
        self.assertIs(parsed["space-for-semicolon"], False)
        self.assertNotIn("standard-output", parsed)
        again = writers.parse_flags(writers.render_flags(parsed))
        self.assertEqual(again, parsed)

    def test_ini_round_trip_perlcritic(self):
        base = read(os.path.join(ROOT, "config", "perl", "perlcriticrc"))
        parsed = writers.parse_ini(base)
        self.assertIn("-CodeLayout::RequireTidyCode", parsed)
        self.assertEqual(writers.parse_ini(writers.render_ini(parsed)), parsed)

    def test_checkstyle_merge(self):
        base = read(os.path.join(ROOT, "config", "checkstyle.xml"))
        out = writers.merge_checkstyle(
            base, {"MethodLength": {"max": 120}, "NeedBraces": False, "LineLength": {"max": 100}}
        )
        self.assertIn('name="max" value="120"', out)
        self.assertNotIn('name="NeedBraces"', out)
        self.assertRegex(out, r'<module name="Checker">\s*(<[^>]+>\s*)*<module name="LineLength">')

    def test_pmd_merge(self):
        base = read(os.path.join(ROOT, "config", "pmd-ruleset.xml"))
        out = writers.merge_pmd(
            base,
            {
                "category/java/performance.xml": False,
                "category/java/design.xml/CyclomaticComplexity": {"methodReportLevel": 15},
            },
        )
        self.assertNotIn("performance.xml", out)
        self.assertIn('exclude name="CyclomaticComplexity"', out)
        self.assertIn('name="methodReportLevel" value="15"', out)

    def test_eslint_wrapper_imports_base(self):
        out = writers.build(
            {"format": "eslint", "base_abs": "/opt/npm/eslint.base.mjs"},
            None,
            {"no-console": "warn"},
        )
        self.assertIn('import base from "/opt/npm/eslint.base.mjs"', out)
        self.assertIn('"no-console": "warn"', out)

    def test_merge_keeps_base_and_overrides(self):
        out = writers.build(
            {"format": "json"}, '{"printWidth": 100, "semi": true}', {"printWidth": 120}
        )
        self.assertEqual(json.loads(out), {"printWidth": 120, "semi": True})


class Rules(unittest.TestCase):
    def test_language_specific_defaults(self):
        data = rules.skeleton("")
        rules.populate_language(data, REG, "sh")
        self.assertEqual(data["languages"]["sh"]["formatting"]["shfmt"]["rules"]["-ln"], "posix")
        self.assertEqual(
            data["languages"]["sh"]["analysis"]["shellcheck"]["rules"]["--shell"], "sh"
        )
        self.assertEqual(
            data["languages"]["sh"]["formatting"]["qs-marker"]["rules"]["shebang"], "#!/bin/sh"
        )

    def test_fallbacks_listed_only_when_needed(self):
        data = rules.skeleton("")
        rules.populate_language(data, REG, "jsp")
        self.assertIn("qs-basic-format", data["languages"]["jsp"]["formatting"])
        rules.populate_language(data, REG, "python")
        self.assertNotIn("qs-basic-format", data["languages"]["python"].get("formatting", {}))

    def test_version_from_env_is_pinned(self):
        data = rules.skeleton("")
        rules.populate_language(data, REG, "java", ("17", "pom.xml"), "11")
        self.assertEqual(data["languages"]["java"]["version"], "11")

    def test_validate(self):
        data = rules.skeleton("")
        data["level"] = "extreme"
        data["languages"] = {
            "python": {"formatting": {"ruff-format": {"enabled": "yes"}}},
            "klingon": {},
        }
        errors, warnings = rules.validate(data, REG)
        self.assertTrue(any("level" in e for e in errors))
        self.assertTrue(any("enabled" in e for e in errors))
        self.assertTrue(any("klingon" in w for w in warnings))

    def test_diff_paths(self):
        a = {"languages": {"java": {"version": "auto", "analysis": {"pmd": {"enabled": True}}}}}
        b = {"languages": {"java": {"version": "17", "analysis": {"pmd": {"enabled": False}}}}}
        self.assertEqual(
            sorted(p for p, _, _ in rules.diff(a, b)),
            ["languages.java.analysis.pmd.enabled", "languages.java.version"],
        )


class Runner(unittest.TestCase):
    def setUp(self):
        self.ctx = runner.Ctx(
            "/repo", "fix", "/tmp", {("python", "ruff"): "/tmp/c/ruff.toml"}, set()
        )

    def test_optional_groups(self):
        tool = {"id": "ruff", "_lang": "python"}
        self.assertEqual(
            runner.expand(
                ["ruff", ["--config", "{config}"], "{files}"], self.ctx, tool, ["a.py"], [], None
            ),
            ["ruff", "--config", "/tmp/c/ruff.toml", "a.py"],
        )
        tool2 = {"id": "other", "_lang": "python"}
        self.assertEqual(
            runner.expand(
                ["x", ["--config", "{config}"], "{files}"], self.ctx, tool2, ["a.py"], [], None
            ),
            ["x", "a.py"],
        )

    def test_file_tokens(self):
        tool = {"id": "t", "_lang": "x"}
        self.assertEqual(
            runner.expand(
                ["{files_csv}", "{files::}", "{dirs}"], self.ctx, tool, ["a/b.go", "c.go"], [], None
            ),
            ["a/b.go,c.go", ":a/b.go", ":c.go", "./a/", "./"],
        )

    def test_rule_args(self):
        self.assertEqual(
            runner.rule_args(
                {"rule_args": {"joiner": " "}}, {"-ln": "posix", "-s": True, "-x": False}
            ),
            ["-ln", "posix", "-s"],
        )
        self.assertEqual(
            runner.rule_args({"rule_args": {"joiner": "="}}, {"--suppress": ["a", "b"]}),
            ["--suppress=a", "--suppress=b"],
        )
        self.assertEqual(
            runner.rule_args({"rule_args": {"joiner": ""}}, {"-n": [1, 8]}), ["-n1", "-n8"]
        )

    def test_version_rules(self):
        tool = {
            "version_rules": {
                "target-version": "py{v_nodot}",
                "AllCops.TargetRubyVersion": "{float}{v}",
                "parameters.phpVersion": "{int}{v_major}0{v_minor}00",
            }
        }
        out = runner.effective_rules(tool, {"line-length": 100}, "3.11")
        self.assertEqual(out["target-version"], "py311")
        self.assertEqual(out["AllCops"]["TargetRubyVersion"], 3.11)
        self.assertEqual(runner.effective_rules(tool, {}, "8.3")["parameters"]["phpVersion"], 80300)
        self.assertEqual(
            runner.effective_rules(tool, {"target-version": "py38"}, "3.11")["target-version"],
            "py38",
        )


class Builtins(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.d)

    def test_basic_format_keeps_heredoc_crlf_and_continuations(self):
        p = write(self.d, "a.sh", "echo hi   \r\ncat <<EOF\r\nkeep   \r\nEOF\r\nls \\ \r\n\r\n\r\n")
        builtin.basic_format(p, {"heredoc": True})
        out = read(p, "rb").decode()
        self.assertEqual(out, "echo hi\r\ncat <<EOF\r\nkeep   \r\nEOF\r\nls \\ \r\n")

    def test_basic_format_ws_significant(self):
        p = write(self.d, "a.properties", "key=value   \n")
        self.assertTrue(builtin.basic_format(p, {"ws_significant": True}))

    def test_basic_syntax(self):
        spec = {
            "line_comment": ["//"],
            "block_comment": [["/*", "*/"]],
            "strings": ['"', "'"],
            "escape": "\\",
        }
        self.assertEqual(
            builtin.basic_syntax(
                write(self.d, "ok.c", 'int f(){ char *s = "}"; /* { */ }\n'), spec
            ),
            [],
        )
        self.assertTrue(builtin.basic_syntax(write(self.d, "bad.c", "int f( {\n"), spec))
        self.assertTrue(
            builtin.basic_syntax(
                write(self.d, "conf.c", "<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> b\n"), spec
            )
        )

    def test_properties_duplicates(self):
        self.assertTrue(builtin.check_properties(write(self.d, "a.properties", "a=1\nb=2\na=3\n")))
        self.assertEqual(
            builtin.check_properties(write(self.d, "b.properties", "a=1\\\n  continued\nb=2\n")), []
        )

    def test_python_ast(self):
        self.assertEqual(builtin.python_ast(write(self.d, "ok.py", "x = 1\n"), "3.8"), [])
        self.assertTrue(builtin.python_ast(write(self.d, "bad.py", "def f(:\n  pass\n"), "3.8"))
        # walrus is 3.8+: rejected when the target is 3.7
        self.assertTrue(
            builtin.python_ast(write(self.d, "w.py", "if (n := 1):\n    pass\n"), "3.7")
        )


class Classify(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.d)

    def lang(self, rel, text):
        write(self.d, rel, text)
        c = registry.classify(REG, self.d, [rel], REG.default_excludes)[0]
        return c.lang, c.subtypes, c.confident

    def test_names_beat_extensions(self):
        self.assertEqual(self.lang("CMakeLists.txt", "project(x)\n")[0], "cmake")
        self.assertEqual(self.lang("notes.txt", "hello\n")[0], "text")

    def test_probes(self):
        self.assertEqual(self.lang("a.pl", "use strict;\nmy $x = 1;\n")[0], "perl")
        self.assertEqual(self.lang("b.pl", ":- module(b, []).\nfoo(X) :- bar(X).\n")[0], "prolog")
        self.assertEqual(self.lang("c.h", "namespace n { class A {}; }\n")[0], "cpp")
        self.assertEqual(self.lang("d.h", "int f(void);\n")[0], "c")
        self.assertEqual(
            self.lang("e.m", "#import <Foundation/Foundation.h>\n@interface A\n@end\n")[0],
            "objective-c",
        )
        self.assertEqual(self.lang("f.m", "function y = f(x)\n  y = x;\nend\n")[0], "matlab")

    def test_shebang_and_modeline(self):
        self.assertEqual(self.lang("tool", "#!/usr/bin/env python3\nprint(1)\n")[0], "python")
        self.assertEqual(self.lang("x.sh", "#!/bin/sh\necho\n")[0], "sh")
        self.assertEqual(self.lang("y.inc", "; -*- mode: pascal -*-\nunit a;\n")[0], "pascal")

    def test_subtypes(self):
        _, st, _ = self.lang(".github/workflows/ci.yml", "on: push\njobs: {}\n")
        self.assertIn("github-workflow", st)
        _, st, _ = self.lang("chart/templates/dep.yaml", "kind: {{ .Values.kind }}\n")
        self.assertIn("templated", st)
        _, st, _ = self.lang("k8s/svc.yaml", "apiVersion: v1\nkind: Service\n")
        self.assertIn("kubernetes", st)

    def test_binary_and_excluded(self):
        write(self.d, "img.png", b"\x89PNG\r\n\x1a\n\x00\x00binary", "wb")
        c = registry.classify(REG, self.d, ["img.png"], REG.default_excludes)[0]
        self.assertTrue(c.skip and c.binary)
        write(self.d, "node_modules/x/a.js", "x\n")
        c = registry.classify(REG, self.d, ["node_modules/x/a.js"], REG.default_excludes)[0]
        self.assertEqual(c.reason, "excluded")


class Policy(unittest.TestCase):
    def test_encoding_utf8(self):
        self.assertEqual(policy.check("Año\n".encode(), "utf-8", "forbid"), [])
        self.assertIn(
            "not valid UTF-8 at line 2", policy.check(b"ok\nA\xf1o\n", "utf-8", "forbid")[0]
        )
        self.assertIn("BOM", policy.check(b"\xef\xbb\xbfx", "utf-8", "forbid")[0])
        self.assertEqual(policy.check(b"\xef\xbb\xbfx", "utf-8", "allow"), [])
        self.assertIn("UTF-16", policy.check("hi".encode("utf-16"), "utf-8", "forbid")[0])

    def test_encoding_mixed_and_ansi(self):
        mixed = 'a = "Canci\u00f3n"\n'.encode() + 'b = "a\u00f1o"\n'.encode("cp1252")
        msg = policy.check(mixed, "utf-8", "forbid")[0]
        self.assertIn("mixed encodings", msg)
        self.assertIn('line 2: "a\u00f1o"', msg)
        self.assertIn(
            "Windows-1252/ISO-8859-1 (ANSI)",
            policy.check("\u00f1".encode("cp1252"), "utf-8", "forbid")[0],
        )
        fixed, notes, left = policy.repair(mixed)
        self.assertEqual(fixed.decode(), 'a = "Canci\u00f3n"\nb = "a\u00f1o"\n')
        self.assertEqual(left, [])

    def test_mojibake_double_encoding(self):
        good = 't = "Canci\u00f3n \u201cs\u00ed\u201d \u20ac";'
        bad = good.encode().decode("cp1252", errors="ignore")  # what VS Code shows and saves
        errs, warns = policy.mojibake("x\n" + bad + "\n")
        self.assertTrue(errs)
        self.assertEqual(errs[0]["line"], 2)
        self.assertEqual(errs[0]["fixed"], "Canci\u00f3n")
        twice = bad.encode().decode("cp1252", errors="ignore")
        self.assertEqual(policy.undo_double_encoding(twice)[0].count("\u00f3"), 1)
        # already present in the previous version: only a warning
        errs, warns = policy.mojibake(bad + "\nnew line\n", bad + "\n")
        self.assertEqual(errs, [])
        self.assertTrue(warns)
        # normal Spanish text, symbols and code are never reported
        clean = (
            "\u00bfQu\u00e9 a\u00f1o? \u00a1S\u00ed! 25\u00ba \u00b7 \u00ab\u00bb \u00e0 \u00c0 "
            "List<?> x = a ? b : c;\n"
        )
        self.assertEqual(policy.mojibake(clean, None), ([], []))
        self.assertEqual(policy.mojibake(bad + " qs-allow-mojibake\n"), ([], []))

    def test_mojibake_lost_accents(self):
        old = 'String t = "Canci\u00f3n";\nint a = 1;\n'
        for new, kind in (
            ('String t = "Canci?n";\nint a = 2;\n', "lost"),
            ('String t = "Canci\ufffdn";\nint a = 2;\n', "replacement"),
        ):
            errs, _ = policy.mojibake(new, old)
            self.assertEqual([(f["line"], f["kind"]) for f in errs], [(1, kind)])
            fixed, _, left = policy.repair(new.encode(), old.encode())
            self.assertEqual(fixed.decode(), old.replace("1;", "2;"))
            self.assertEqual(left, [])
        # without the previous version a U+FFFD is still reported; '?' alone is normal text
        self.assertEqual(policy.mojibake("a\ufffdb\n")[0][0]["kind"], "replacement")
        self.assertEqual(policy.mojibake("a ? b : c\n"), ([], []))

    def test_policy_new_keys(self):
        self.assertEqual(
            policy.validate({"encoding": {"mojibake": "x"}}),
            ["encoding.mojibake: must be block, warn or off"],
        )
        self.assertTrue(policy.validate({"branches": {"version_file": "../V"}}))
        env = policy.shell_env({})
        for k in (
            "QS_BR_VERSION_FILE='VERSION'",
            "QS_BR_CHANGELOG='CHANGELOG.md'",
            "QS_BR_README='README.md'",
        ):
            self.assertIn(k, env)

    def test_encoding_legacy_charset(self):
        self.assertEqual(policy.check(b"A\xf1o", "iso-8859-1", "forbid"), [])
        self.assertIn("looks like UTF-8", policy.check("Año".encode(), "iso-8859-1", "forbid")[0])
        self.assertIn("not valid WINDOWS-1252", policy.check(b"\x81", "windows-1252", "forbid")[0])
        self.assertTrue(policy.needs_protection(b"A\xf1o", "iso-8859-1"))
        self.assertFalse(policy.needs_protection(b"Ano", "iso-8859-1"))

    def test_expected_precedence(self):
        enc = dict(
            policy.DEFAULTS["encoding"],
            by_language={"properties": "iso-8859-1", "powershell": {"bom": "allow"}},
            by_glob={"src/legacy/*": "windows-1252"},
        )
        self.assertEqual(policy.expected(enc, "a.txt", "text"), ("utf-8", "forbid"))
        self.assertEqual(
            policy.expected(enc, "m.properties", "properties"), ("iso-8859-1", "forbid")
        )
        self.assertEqual(
            policy.expected(enc, "src/legacy/m.properties", "properties"),
            ("windows-1252", "forbid"),
        )
        self.assertEqual(policy.expected(enc, "x.ps1", "powershell"), ("utf-8", "allow"))

    def test_populate_and_validate(self):
        d = {"commit": {"charset": "utf-8"}}
        added = policy.populate(d)
        self.assertIn("encoding", added)
        self.assertEqual(d["commit"]["charset"], "utf-8")  # never overwritten
        self.assertEqual(policy.validate(d), [])
        d["branches"]["levels"] = ["("]
        d["encoding"]["charset"] = "klingon"
        errs = policy.validate(d)
        self.assertTrue(any("regular expression" in e for e in errs))
        self.assertTrue(any("klingon" in e for e in errs))

    def test_shell_env(self):
        env = policy.shell_env(
            {"branches": {"parent_leaf": "ORIGINAL", "allow": ["^release/it's$"]}}
        )
        self.assertIn("QS_BR_LEAF='ORIGINAL'", env)
        self.assertIn("QS_BR_LEVEL_2='^[A-Za-z0-9]+$'", env)
        self.assertIn("QS_BR_ALLOW_1='^release/it'\\''s$'", env)


class Versions(unittest.TestCase):
    def test_semver(self):
        order = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0",
            "1.0.1",
            "1.10.0",
            "2.0.0",
        ]
        self.assertEqual(sorted(reversed(order), key=semver.key), order)
        self.assertFalse(semver.valid("6.22") or semver.valid("06.1.1") or semver.valid("v1.2.3"))
        self.assertEqual(
            [semver.bump("6.22.6", p) for p in ("patch", "minor", "major")],
            ["6.22.7", "6.23.0", "7.0.0"],
        )
        self.assertIn("MINOR", semver.needed_bump("6.22.5", "6.22.6", False, True))
        self.assertIn("MAJOR", semver.needed_bump("6.22.5", "6.23.0", True, False))
        self.assertIsNone(semver.needed_bump("6.22.5", "7.0.0", True, True))
        self.assertTrue(re.match(semver.BRANCH_RX, "6.22.6-SNAPSHOT"))
        self.assertFalse(re.match(semver.BRANCH_RX, "6.22.6+b1"))

    def test_poms(self):
        d = tempfile.mkdtemp()
        try:
            os.makedirs(os.path.join(d, "web"))
            with open(os.path.join(d, "pom.xml"), "w") as fh:
                fh.write(
                    "<project><!-- <version>9</version> -->"
                    "<parent><groupId>org.springframework.boot</groupId>"
                    "<artifactId>p</artifactId><version>3.3.4</version></parent>"
                    "<groupId>es.x</groupId>"
                    "<artifactId>app</artifactId><version>1.0.0</version>"
                    "<dependencies><dependency><version>1.0.0</version></dependency>"
                    "</dependencies></project>"
                )
            with open(os.path.join(d, "web", "pom.xml"), "w") as fh:
                fh.write(
                    "<project><parent><groupId>es.x</groupId><artifactId>app</artifactId>"
                    "<version>1.0.0</version></parent><artifactId>web</artifactId></project>"
                )
            changed, _ = maven.set_versions(d, "1.1.0")
            self.assertEqual(sorted(changed), ["VERSION", "pom.xml", "web/pom.xml"])
            root = read(os.path.join(d, "pom.xml"))
            self.assertIn("<version>3.3.4</version>", root)  # external parent untouched
            self.assertIn("<version>1.0.0</version></dependency>", root)  # dependency untouched
            self.assertEqual(maven.read_versions(d)["pom.xml"], "1.1.0")
            self.assertIn(
                "<version>1.1.0</version></parent>", read(os.path.join(d, "web", "pom.xml"))
            )
            (a,) = maven.align(root.replace("1.1.0", "2.0.0", 1), [root])
            self.assertEqual(maven.pom_info(a)["version"], "2.0.0")
        finally:
            shutil.rmtree(d)


class Changelog(unittest.TestCase):
    ITEMS = [
        {
            "group": "Added",
            "breaking": False,
            "text": "Add login",
            "refs": ["abc1234", "OT 1"],
            "authors": ["Ana"],
            "order": 1,
        },
        {
            "group": "Fixed",
            "breaking": True,
            "text": "Drop cookie",
            "refs": ["def5678"],
            "authors": [],
            "order": 2,
        },
    ]

    def test_render_merge_validate(self):
        text = changelog.merge(
            "", "1.1.0", changelog.render("1.1.0", "2026-10-26", self.ITEMS, "u"), "https://x/1.1.0"
        )
        text = changelog.merge(
            text, "1.0.0", changelog.render("1.0.0", "2026-01-02", [], "u"), "https://x/1.0.0"
        )
        self.assertEqual(changelog.versions(text), ["1.1.0", "1.0.0"])
        self.assertEqual(changelog.validate(text), ([], []))
        self.assertIn("- **Breaking:** Drop cookie (def5678)", text)
        self.assertIn("- Add login (abc1234, OT 1; Ana)", changelog.section(text, "1.1.0"))
        bad = "# Changelog\n\n## [Unreleased]\n\n## 1.0 - 2020-1-1\n\n### Security\n\n- x\n"
        errs = " ".join(changelog.validate(bad)[0])
        for want in ("Unreleased", "semantic version", "YYYY-MM-DD", "not allowed"):
            self.assertIn(want, errs)

    def test_classify(self):
        self.assertEqual(changelog.classify("feat(x): add y")[0:2], ("Added", False))
        self.assertEqual(changelog.classify("fix!: drop z")[0:2], ("Fixed", True))
        self.assertEqual(changelog.classify("refactor: remove old api")[0], "Removed")
        self.assertIsNone(changelog.classify("docs: typo")[0])
        self.assertTrue(changelog.classify("feat: a", "body\n\nBREAKING CHANGE: b")[1])

    def test_badge_and_citation(self):
        r = changelog.set_badge("# App\n\nText\n", "1.2.3-rc.1")
        self.assertEqual(changelog.badge_version(r), "1.2.3-rc.1")
        self.assertIn("version-1.2.3--rc.1-blue", r)
        self.assertEqual(changelog.badge_version(changelog.set_badge(r, "1.2.3")), "1.2.3")
        c = changelog.set_citation("cff-version: 1.2.0\nversion: 0.1.0\n", "1.2.3", "2026-10-26")
        self.assertIn('version: "1.2.3"', c)
        self.assertIn("date-released: '2026-10-26'", c)


class RepoFiles(unittest.TestCase):
    def test_checks_and_generator(self):
        d = tempfile.mkdtemp()
        try:
            repofiles.generate(d, None, {}, today=__import__("datetime").date(2026, 10, 26))
            for name in repofiles.NAMES:
                self.assertTrue(repofiles._exists(d, name), name)
            for name in os.listdir(d):
                errs, _ = repofiles.check(d, name, {}, "")
                self.assertEqual(errs, [], name)
            with open(os.path.join(d, "VERSION"), "w") as fh:
                fh.write("1.0\n")
            self.assertTrue(repofiles.check(d, "VERSION", {}, "")[0])
            with open(os.path.join(d, "VERSION"), "w") as fh:
                fh.write("0.1.0\n")
            self.assertIn(
                "belongs to version 6.22.6", repofiles.check(d, "VERSION", {}, "6.22.6/1/x")[0][0]
            )
            with open(os.path.join(d, "CODEOWNERS"), "w") as fh:
                fh.write("* bad owner\n/docs/ @team/docs ana@x.es\n")
            self.assertIn("must be @user", repofiles.check(d, "CODEOWNERS", {}, "")[0][0])
        finally:
            shutil.rmtree(d)

    def test_web_urls(self):
        self.assertEqual(
            repofiles.web_url("git@github.com:o/r.git"), ("github", "https://github.com/o/r")
        )
        self.assertEqual(
            repofiles.web_url("https://u@dev.azure.com/org/p/_git/r"),
            ("azure", "https://dev.azure.com/org/p/_git/r"),
        )
        self.assertEqual(
            repofiles.link_templates("git@gitlab.x.es:g/r.git")[0],
            "https://gitlab.x.es/g/r/-/tags/{tag}",
        )
        self.assertEqual(repofiles.link_templates("/tmp/remote.git"), ("", ""))


class AlphanumericOt(unittest.TestCase):
    """The OT (level 2 of a branch name) is ASCII letters and digits; numeric OTs keep working."""

    GOOD = ("188858", "ABC123", "abc", "RF001", "7")
    BAD = ("AB-12", "AB_12", "AB 12", " ABC", "ABC ", "AÑO1", "café", "", "AB/12")

    def test_default_level_is_the_ot_rule(self):
        self.assertEqual(policy.OT_RX, "^[A-Za-z0-9]+$")
        self.assertEqual(policy.DEFAULTS["branches"]["levels"][1], policy.OT_RX)
        self.assertEqual(policy.get({}, "branches")["levels"][1], policy.OT_RX)
        self.assertEqual(policy.validate({}), [])

    def test_accepted(self):
        for ot in self.GOOD:
            with self.subTest(ot=ot):
                self.assertTrue(re.match(policy.OT_RX, ot))

    def test_refused(self):
        for ot in self.BAD:
            with self.subTest(ot=ot):
                self.assertFalse(re.match(policy.OT_RX, ot))

    def test_exported_to_the_hooks(self):
        self.assertIn("QS_BR_LEVEL_2='^[A-Za-z0-9]+$'\n", policy.shell_env({}))

    def test_rules_file_level_kept(self):
        data = {"branches": {"levels": [policy.DEFAULTS["branches"]["levels"][0], "^[0-9]+$"]}}
        self.assertEqual(policy.get(data, "branches")["levels"][1], "^[0-9]+$")
        # why: existing rules files are never rewritten; a numeric-only OT rule stays
        self.assertNotIn("branches.levels", policy.populate(data))
        self.assertEqual(data["branches"]["levels"][1], "^[0-9]+$")

    def test_changelog_default_is_the_policy(self):
        default = changelog.entries.__defaults__[-1]
        self.assertEqual(default, policy.OT_RX)

    def test_changelog_ot_reference(self):
        self.assertEqual(changelog._ot_of("4.0.2/188858/login", policy.OT_RX), "188858")
        self.assertEqual(changelog._ot_of("4.0.2/ABC123/login", policy.OT_RX), "ABC123")
        self.assertEqual(changelog._ot_of("4.0.2/ABC123/ORIGINAL", policy.OT_RX), "ABC123")
        for src in ("4.0.2/AB-12/login", "4.0.2/AB 12/login", "4.0.2//login", "4.0.2/ABC123"):
            with self.subTest(src=src):
                self.assertIsNone(changelog._ot_of(src, policy.OT_RX))
        self.assertIsNone(changelog._ot_of("4.0.2/ABC123/login", "^[0-9]+$"))

    def test_changelog_entry_refs(self):
        c = {"hash": "a" * 40, "body": "feat: x\n\nNorms: N1\n"}
        refs = changelog._entry_refs(c, "4.0.2/ABC123/login", (), "", policy.OT_RX)
        self.assertEqual(refs, ["aaaaaaa", "OT ABC123", "N1"])


class RegistryIntegrity(unittest.TestCase):
    def test_every_language_tool_exists(self):
        for lang in REG.languages.values():
            for t in REG.section_tools(lang["id"]):
                self.assertIn(t, REG.tools, f"{lang['id']} -> {t}")

    def test_one_formatter_per_file_type(self):
        for lang in REG.languages.values():
            base = [t for t in lang["tools"] if REG.tools[t]["role"] == "format"]
            self.assertLessEqual(len(base), 1, f"{lang['id']} has several formatters: {base}")
            for st in lang.get("subtypes", []):
                tids = REG.tools_for(lang["id"], [st["id"]])
                fm = [t for t in tids if REG.tools[t]["role"] == "format"]
                self.assertLessEqual(
                    len(fm), 1, f"{lang['id']}/{st['id']} has several formatters: {fm}"
                )


def load_tests(loader, tests, pattern):
    """Add every sibling tests/unit/test_*.py module when this file is run directly.

    Parameters: loader (unittest loader), tests (suite to extend), pattern (None when the
    file is run directly; a discovery pattern such as "test*.py" under discover).
    Returns the extended suite. Under discover the siblings are already found, so nothing
    is added there (otherwise they would run twice).
    """
    if pattern is not None:
        return tests
    here = os.path.dirname(os.path.abspath(__file__))
    own = os.path.basename(__file__)
    for name in sorted(os.listdir(here)):
        if name.startswith("test_") and name.endswith(".py") and name != own:
            tests.addTests(loader.loadTestsFromName(name[:-3]))
    return tests


if __name__ == "__main__":
    unittest.main()
