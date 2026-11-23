"""KNOWN_BUGS.md generation (7.1.1 known_bugs, AC KB1 and KB6)."""

import datetime
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "engine"))
import repofiles  # noqa: E402 - needs the engine folder on the path

NAME = "KNOWN_BUGS.md"
ROW = "| 2026-11-23 | `git x` | it breaks | open |\n"


class KnownBugsFile(unittest.TestCase):
    """Creation, idempotence and rows that are never overwritten."""

    def setUp(self):
        """Create an empty repository folder."""
        self.d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.d)
        self.path = os.path.join(self.d, NAME)

    def gen(self, **kw):
        """Run the generator for KNOWN_BUGS.md only.

        Args:
            **kw: extra arguments of repofiles.generate.

        Returns:
            list: the generator result.
        """
        return repofiles.generate(
            self.d, None, {}, names=[NAME], today=datetime.date(2026, 11, 23), **kw
        )

    def test_known(self):
        """The file is part of the standard set, with a convention and a purpose."""
        row = next(r for r in repofiles.SPEC if r[0] == NAME)
        self.assertTrue(row[1] and row[3])

    def test_creates_skeleton(self):
        """A missing file is created with the legend and the table header."""
        self.assertEqual(self.gen(), [(NAME, "created")])
        with open(self.path, encoding="utf-8") as fh:
            text = fh.read()
        self.assertIn("# Known bugs", text)
        self.assertIn(repofiles.GENERATED, text)
        self.assertIn("`fixing: <branch>`", text)
        self.assertIn("| Date | Where | Symptom | Status |", text)
        self.assertEqual(repofiles.check(self.d, NAME, {}, ""), ([], []))

    def test_idempotent_and_keeps_rows(self):
        """A second run reports it exists and leaves the added rows untouched."""
        self.gen()
        with open(self.path, "a", encoding="utf-8", newline="") as fh:
            fh.write(ROW)
        with open(self.path, encoding="utf-8") as fh:
            before = fh.read()
        self.assertEqual(self.gen(), [(NAME, f"exists: {NAME}")])
        with open(self.path, encoding="utf-8") as fh:
            self.assertEqual(fh.read(), before)
        self.assertIn(ROW, before)

    def test_readme_links_it(self):
        """The generated README documentation list links to the file."""
        repofiles.generate(self.d, None, {}, names=["README.md"], today=datetime.date(2026, 11, 23))
        with open(os.path.join(self.d, "README.md"), encoding="utf-8") as fh:
            self.assertIn("[KNOWN_BUGS.md](KNOWN_BUGS.md)", fh.read())


if __name__ == "__main__":
    unittest.main()
