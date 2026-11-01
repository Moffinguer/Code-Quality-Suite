"""Unit tests for the generated-file exemption of the size check.

python3 -m unittest discover -s tests/unit -v
"""

import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import generated  # noqa: E402
import runner  # noqa: E402


class IsGeneratedTest(unittest.TestCase):
    """Checks generated.is_generated against a throwaway repository."""

    def test_attribute_marks_only_listed_files(self):
        """Files with qs-generated or linguist-generated are exempt; others are not."""
        with tempfile.TemporaryDirectory() as d:
            subprocess.run(["git", "init", "-q", d], check=True)
            with open(os.path.join(d, ".gitattributes"), "w", encoding="utf-8") as fh:
                fh.write("a.json qs-generated\nb.json linguist-generated\n")
            self.assertTrue(generated.is_generated(d, "a.json"))
            self.assertTrue(generated.is_generated(d, "b.json"))
            self.assertFalse(generated.is_generated(d, "c.json"))

    def test_missing_repo_is_not_generated(self):
        """Outside a repository the lookup fails closed (the check stays strict)."""
        with tempfile.TemporaryDirectory() as d:
            self.assertFalse(generated.is_generated(d, "a.json"))


class AttributeFileFallbackTest(unittest.TestCase):
    """Checks the direct .gitattributes reading used when git cannot answer."""

    def test_fallback_reads_attributes_file(self):
        """Without a usable git, the root .gitattributes decides."""
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, ".gitattributes"), "w", encoding="utf-8") as fh:
                fh.write(
                    "schema/x.json qs-generated\n*.gen linguist-generated\nkeep.gen -qs-generated\n"
                )
            self.assertTrue(generated._file_says(d, "schema/x.json"))
            self.assertTrue(generated._file_says(d, "sub/a.gen"))
            self.assertFalse(generated._file_says(d, "other.json"))


class RunToolSkipTest(unittest.TestCase):
    """Checks that run_tool skips generated files for style tools but not for secret scanners."""

    def _run(self, tool_id, role):
        """Run a failing external tool on a generated and a normal file; return the result."""
        with tempfile.TemporaryDirectory() as d:
            subprocess.run(["git", "init", "-q", d], check=True)
            with open(os.path.join(d, ".gitattributes"), "w", encoding="utf-8") as fh:
                fh.write("gen.json qs-generated\n")
            tool = {"id": tool_id, "role": role, "cmd": {"builtin": "private_key"}}
            ctx = runner.Ctx(d, "check", d, {}, set())
            for name in ("gen.json", "plain.json"):
                with open(os.path.join(d, name), "w", encoding="utf-8") as fh:
                    fh.write("-----BEGIN " + "PRIVATE KEY-----\n")
            return runner.run_tool(tool, {}, None, ctx, ["gen.json", "plain.json"], None, "t")

    def test_lint_skips_generated(self):
        """A lint tool only sees the file that is not generated."""
        self.assertEqual(set(self._run("some-lint", "lint").status), {"plain.json"})

    def test_secret_scanner_sees_generated(self):
        """Secret scanners still scan generated files."""
        self.assertEqual(
            set(self._run("qs-private-key", "lint").status), {"gen.json", "plain.json"}
        )


if __name__ == "__main__":
    unittest.main()
