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

    def setUp(self):
        """Clear the per-run cache so temporary repositories do not leak results."""
        generated.clear_cache()

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


class MatcherSemanticsTest(unittest.TestCase):
    """Checks gitattributes pattern semantics of the fallback matcher."""

    def _says(self, text, rel):
        """Return _file_says for a temporary .gitattributes with the given text."""
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, ".gitattributes"), "w", encoding="utf-8") as fh:
                fh.write(text)
            return generated._file_says(d, rel)

    def test_star_does_not_cross_slash(self):
        """A pattern with a slash is anchored and `*` stays in one directory."""
        text = "a/*.json qs-generated\n"
        self.assertTrue(self._says(text, "a/x.json"))
        self.assertFalse(self._says(text, "a/b/c.json"))
        self.assertFalse(self._says(text, "z/a/x.json"))

    def test_double_star_crosses_directories(self):
        """`**` matches any depth."""
        text = "a/**/*.json qs-generated\n"
        self.assertTrue(self._says(text, "a/b/c.json"))
        self.assertTrue(self._says(text, "a/x.json"))

    def test_bracket_class_pattern(self):
        """A bracket class matches like git; only [attr] macros are rejected."""
        self.assertTrue(self._says("[ab]x.txt qs-generated\n", "bx.txt"))
        self.assertFalse(self._says("[ab]x.txt qs-generated\n", "cx.txt"))
        self.assertFalse(self._says("[attr]m qs-generated\n", "m"))

    def test_basename_pattern_any_depth(self):
        """A pattern without slash matches the basename anywhere."""
        self.assertTrue(self._says("*.gen qs-generated\n", "x/y/z.gen"))

    def test_negation_and_unsupported_forms(self):
        """Later unset wins; quoted, macro and bang patterns fail closed."""
        self.assertFalse(self._says("*.gen qs-generated\nk.gen -qs-generated\n", "k.gen"))
        self.assertFalse(self._says('"a b.gen" qs-generated\n', "a b.gen"))
        self.assertFalse(self._says("[attr]m qs-generated\n", "m"))
        self.assertFalse(self._says("!a.gen qs-generated\n", "a.gen"))

    def test_explicit_unset_beats_linguist(self):
        """-qs-generated wins over linguist-generated, in both git and fallback paths."""
        text = "a.json linguist-generated -qs-generated\n"
        self.assertFalse(self._says(text, "a.json"))
        with tempfile.TemporaryDirectory() as d:
            subprocess.run(["git", "init", "-q", d], check=True)
            with open(os.path.join(d, ".gitattributes"), "w", encoding="utf-8") as fh:
                fh.write(text)
            generated.clear_cache()
            self.assertFalse(generated.is_generated(d, "a.json"))


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
