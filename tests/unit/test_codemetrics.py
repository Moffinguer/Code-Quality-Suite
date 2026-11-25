"""Tests for tools/codemetrics.py: clone detection, docstring false positives, doc counter.

M1: windows of 6 normalized lines; blanks, comments, docstrings and block closers are ignored.
M2: shell doc = comment line above the function (or on the same line); Python = docstring.
M3: the real .codemetrics.json parses and names areas.
Run: python -m unittest discover -s tests/unit
"""

import json
import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import codemetrics as cm  # noqa: E402

BLOCK = "".join(f"echo line{n}\n" for n in range(1, 8))


class MetricsCase(unittest.TestCase):
    """Base case: runs codemetrics against a temporary tree."""

    def setUp(self):
        """Point codemetrics at a fresh temporary root."""
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.old_root = cm.ROOT
        cm.ROOT = self.tmp.name
        self.addCleanup(setattr, cm, "ROOT", self.old_root)

    def put(self, rel, text):
        """Write a file under the temporary root.

        Args:
            rel: relative path.
            text: file content.
        """
        path = os.path.join(self.tmp.name, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)

    def dup(self, *rels):
        """Run the duplication report on one area.

        Args:
            rels: files of the area.
        Returns:
            The report of the area.
        """
        return cm.run_dup({"a": list(rels)}, 6)["a"]


class DupTests(MetricsCase):
    """Clone detection."""

    def test_clone_between_files(self):
        """Seven identical lines in two files are one clone of 7 lines."""
        self.put("x.sh", "#!/bin/bash\n" + BLOCK)
        self.put("y.sh", "#!/bin/bash\nfoo\n" + BLOCK)
        report = self.dup("x.sh", "y.sh")
        self.assertEqual(len(report["clones"]), 1)
        self.assertEqual(report["clones"][0]["lines"], 7)
        self.assertEqual(report["clones"][0]["locations"], ["x.sh:2", "y.sh:3"])
        self.assertEqual(report["dup_lines"], 14)

    def test_five_lines_is_not_a_clone(self):
        """A shared run shorter than the window is not reported."""
        self.put("x.sh", "#!/bin/bash\n" + "".join(f"echo l{n}\n" for n in range(5)))
        self.put("y.sh", "#!/bin/bash\n" + "".join(f"echo l{n}\n" for n in range(5)))
        self.assertEqual(self.dup("x.sh", "y.sh")["clones"], [])

    def test_noise_is_ignored(self):
        """Blanks, comments and closers between lines do not break or fake a clone."""
        noisy = "".join(f"echo line{n}\n\n# note {n}\nfi\n" for n in range(1, 8))
        self.put("x.sh", "#!/bin/bash\n" + BLOCK)
        self.put("y.sh", "#!/bin/bash\n" + noisy)
        self.assertEqual(len(self.dup("x.sh", "y.sh")["clones"]), 1)

    def test_python_docstrings_are_not_clones(self):
        """Identical docstrings are not duplication; identical code is."""
        doc = '    """' + "\n".join(f"line {n}" for n in range(8)) + '\n    """\n'
        self.put("a.py", "def f():\n" + doc + "    return 1\n")
        self.put("b.py", "def g():\n" + doc + "    return 2\n")
        self.assertEqual(self.dup("a.py", "b.py")["clones"], [])
        body = "".join(f"    v{n} = {n}\n" for n in range(7))
        self.put("c.py", "def f():\n" + body)
        self.put("d.py", "def g():\n" + body)
        self.assertEqual(len(self.dup("c.py", "d.py")["clones"]), 1)

    def test_deterministic_and_share(self):
        """Two runs give the same JSON and the share is a percentage of normalized lines."""
        self.put("x.sh", "#!/bin/bash\n" + BLOCK + "uniq1\nuniq2\nuniq3\n")
        self.put("y.sh", "#!/bin/bash\n" + BLOCK)
        first = json.dumps(self.dup("x.sh", "y.sh"), sort_keys=True)
        second = json.dumps(self.dup("x.sh", "y.sh"), sort_keys=True)
        self.assertEqual(first, second)
        report = json.loads(first)
        self.assertEqual(report["lines"], 17)
        self.assertEqual(report["share"], round(100.0 * 14 / 17, 2))


class DocTests(MetricsCase):
    """Doc comment counter."""

    def test_shell_rule(self):
        """A comment above or on the function line counts; a blank gap or none does not."""
        self.put(
            "f.sh",
            "#!/bin/bash\n"
            "# documented\n"
            "a() {\n  :\n}\n"
            "b() { :; } # same line doc\n"
            "c() {\n  :\n}\n"
            "# separated\n\n"
            "d() {\n  :\n}\n"
            "function e {\n  :\n}\n",
        )
        names = [name for _, name in cm.sh_missing("f.sh")]
        self.assertEqual(names, ["c", "d", "e"])

    def test_python_rule(self):
        """Only functions with a docstring are documented; a comment is not enough."""
        self.put(
            "m.py",
            'def a():\n    """Doc."""\n\n\n# comment\ndef b():\n    pass\n\n\nclass K:\n'
            "    def c(self):\n        pass\n",
        )
        self.assertEqual([n for _, n in cm.py_missing("m.py")], ["b", "c"])

    def test_report_counts(self):
        """run_doc splits counts by language."""
        self.put("f.sh", "#!/bin/bash\nc() {\n  :\n}\n")
        self.put("m.py", "def b():\n    pass\n")
        report = cm.run_doc({"a": ["f.sh", "m.py"]})["a"]
        self.assertEqual((report["shell"], report["python"]), (1, 1))


class ConfigTests(unittest.TestCase):
    """The shipped configuration."""

    def test_config_has_areas_and_thresholds(self):
        """M3: areas and thresholds exist and refer to the same areas."""
        config = cm.load_config(os.path.join(ROOT, ".codemetrics.json"))
        self.assertEqual(config["window"], 6)
        self.assertTrue(config["areas"])
        for key in ("dup_share_max", "missing_docs_max"):
            self.assertEqual(set(config["thresholds"][key]), set(config["areas"]))

    def test_breaches(self):
        """Breach messages appear only above the threshold."""
        report = {"a": {"share": 2.0, "shell": 1, "python": 1}}
        self.assertEqual(cm.breaches("dup", report, {"dup_share_max": {"a": 2.0}}), [])
        self.assertEqual(len(cm.breaches("dup", report, {"dup_share_max": {"a": 1.0}})), 1)
        self.assertEqual(len(cm.breaches("doc", report, {"missing_docs_max": {"a": 1}})), 1)

    def test_repo_within_thresholds(self):
        """RT1: duplication (D1, D2) and missing doc comments (D3) do not grow past the config."""
        self.addCleanup(setattr, cm, "ROOT", cm.ROOT)
        cm.ROOT = ROOT
        config = cm.load_config(os.path.join(ROOT, ".codemetrics.json"))
        self.assertEqual(config.get("mode"), "enforce")
        areas = config["areas"]
        found = cm.breaches("dup", cm.run_dup(areas, config["window"]), config["thresholds"])
        found += cm.breaches("doc", cm.run_doc(areas), config["thresholds"])
        self.assertEqual(found, [])


if __name__ == "__main__":
    unittest.main()
