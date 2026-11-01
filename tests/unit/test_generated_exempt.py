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


if __name__ == "__main__":
    unittest.main()
