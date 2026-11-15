"""Unit tests of `qs.py format-check` (FORMAT branch): formatter output of the previous version."""

import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
QS = os.path.join(os.path.dirname(os.path.dirname(HERE)), "engine", "qs.py")

FAKE = (
    "import sys\n"
    "p = sys.argv[1]\n"
    "t = open(p, encoding='utf-8').read()\n"
    "open(p, 'w', encoding='utf-8', newline='\\n').write("
    "'\\n'.join(l.rstrip() for l in t.splitlines()) + '\\n')\n"
)


class FormatCheckTest(unittest.TestCase):
    """format-check against a repository and a fake formatter that trims trailing blanks."""

    def setUp(self):
        """Create a repository with a messy file committed and the fake formatter."""
        self.dir = tempfile.mkdtemp(prefix="qs-fc-")
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.repo = os.path.join(self.dir, "repo")
        os.makedirs(self.repo)
        fake = os.path.join(self.dir, "fake.py")
        with open(fake, "w", encoding="utf-8") as fh:
            fh.write(FAKE)
        self.env = dict(
            os.environ,
            QS_FORMAT_CMD=f"{shlex.quote(sys.executable)} {shlex.quote(fake)}",
            QS_ROOT=self.repo,
        )
        self.env.pop("QS_FILES_FROM", None)
        self.git("init", "-q")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "tester")
        self.write("a.txt", "one   \ntwo\n")
        self.write("b.txt", "clean\n")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "x")

    def git(self, *args):
        """Run git in the repository. Returns the CompletedProcess; raises on failure."""
        return subprocess.run(
            ["git", "-C", self.repo, *args], check=True, capture_output=True, text=True
        )

    def write(self, name, text):
        """Write a file of the repository with LF line ends. Returns None."""
        with open(os.path.join(self.repo, name), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    def check(self, *args):
        """Run `qs.py format-check`. Returns the CompletedProcess (no exception on status 1)."""
        return subprocess.run(
            [sys.executable, QS, "format-check", *args],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_formatter_output_passes(self):
        """The staged file equals the formatter output of its HEAD version."""
        self.write("a.txt", "one\ntwo\n")
        r = self.check("a.txt")
        self.assertEqual((r.returncode, r.stdout), (0, ""))

    def test_hand_edit_is_reported(self):
        """A change the formatter would not make is reported with the file name."""
        self.write("a.txt", "one\ntwo\nthree\n")
        r = self.check("a.txt")
        self.assertEqual(r.returncode, 1)
        self.assertIn("a.txt", r.stdout)

    def test_new_file_is_reported(self):
        """A file that is not in the revision is not formatter output."""
        self.write("c.txt", "new\n")
        r = self.check("c.txt")
        self.assertEqual(r.returncode, 1)
        self.assertIn("is not in HEAD", r.stdout)

    def test_rev_option(self):
        """--rev compares against another revision."""
        self.write("a.txt", "one\ntwo\n")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "y")
        self.write("a.txt", "one\ntwo\nthree\n")
        self.assertEqual(self.check("a.txt").returncode, 1)
        self.assertEqual(self.check("--rev", "HEAD~1", "a.txt").returncode, 1)

    def test_no_files_is_usage_error(self):
        """Without paths check mode refuses (status 2)."""
        self.assertEqual(self.check().returncode, 2)

    def test_fix_formats_in_place(self):
        """--fix rewrites the files of the folder, directories included, and leaves clean ones."""
        r = self.check("--fix")
        self.assertEqual(r.returncode, 0)
        with open(os.path.join(self.repo, "a.txt"), encoding="utf-8") as fh:
            self.assertEqual(fh.read(), "one\ntwo\n")


if __name__ == "__main__":
    unittest.main()
