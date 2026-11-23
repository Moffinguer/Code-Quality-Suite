"""Regression tests of the formatter check mode and of `qs.py format-check` (FORMAT branch).

The diff check formats copies of the files in a temp root and compares them. Tools whose
result depends on the repository layout (ruff's isort tells first-party imports by the
folders under `src`) must still see the real repository: ruff-format checks by piping the
real file through stdin with its real path (cmd.check = {"pipe": [...]}).

python3 -m unittest discover -s tests/unit -v
"""

import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import runner  # noqa: E402

import registry  # noqa: E402

# why: checked alone, mypy resolves 'registry' to the registry/ data folder, not to
# engine/registry.py (checked with engine files it resolves it right: hence unused-ignore)
REG = registry.Registry(  # type: ignore[attr-defined, unused-ignore]
    os.path.join(ROOT, "registry", "registry.json")
)

# why: a fake formatter whose output is the {repo} it was given, so check == fix only
# when the check passes the same repository as the fix
WRITE_REPO = "import sys\nfor p in sys.argv[2:]:\n    open(p, 'w').write(sys.argv[1])\n"
COPY = "import sys\nsys.stdout.buffer.write(sys.stdin.buffer.read())\n"
UPPER = "import sys\nsys.stdout.buffer.write(sys.stdin.buffer.read().upper())\n"
# why: prints the file's text only when {file} names a file seen from the working directory
SEES_FILE = (
    "import os, sys\nsys.stdout.buffer.write(b'ok\\n' if os.path.isfile(sys.argv[1]) else b'no')\n"
)
GENERATED_CFG = "line-length = 100\n"
SRC_LAYOUT = '[tool.ruff]\nsrc = ["src"]\n'


def _write(path, data):
    """Write bytes to path, creating its folder.

    Args:
        path: the file to write.
        data: bytes or str (written as UTF-8 with LF endings).
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data if isinstance(data, bytes) else data.encode("utf-8"))


class FormatCheckAgreesWithFix(unittest.TestCase):
    """Checks that check mode resolves {repo} like fix mode does."""

    def _git_repo(self, d):
        """Create a git repository in d holding a file whose text is the repository path.

        Args:
            d: the folder to initialise.

        Returns:
            str: the repository-relative name of the file.
        """
        subprocess.run(["git", "init", "-q", d], check=True)
        with open(os.path.join(d, "a.py"), "w", encoding="utf-8") as fh:
            fh.write(d)
        return "a.py"

    def test_diff_check_sees_real_repo(self):
        """The temp-copy check passes the real repository as {repo}, so it agrees with fix."""
        tool = {
            "id": "fake-fmt",
            "role": "format",
            "cmd": {
                "fix": [sys.executable, "-c", WRITE_REPO, "{repo}", "{files}"],
                "check": "diff",
            },
        }
        with tempfile.TemporaryDirectory() as d:
            f = self._git_repo(d)
            ctx = runner.Ctx(d, "check", d, {}, set())
            res = runner.run_tool(tool, {}, None, ctx, [f], None, "python")
            self.assertEqual(res.status, {f: "SUCCESS"}, res.output)

    def test_ruff_format_check_reads_the_real_file_on_stdin(self):
        """ruff-format's check pipes the real path through stdin and never overrides src."""
        cfg = {("python", "ruff-format"): "/tmp/c/ruff.toml"}
        ctx = runner.Ctx("/repo", "check", "/tmp", cfg, set())
        tool = dict(REG.tools["ruff-format"], _lang="python")
        pipe = [
            runner.expand(s, ctx, tool, ["pkg/a.py"], [], None)
            for s in tool["cmd"]["check"]["pipe"]
        ]
        for cmd in pipe:
            self.assertEqual(cmd[cmd.index("--stdin-filename") + 1 :], ["pkg/a.py", "-"])
            self.assertIn("/tmp/c/ruff.toml", cmd)
        flat = [t for s in runner._seqs(tool["cmd"]["fix"]) + pipe for t in s]
        self.assertFalse([t for t in flat if "src" in t], "an inline src overrides the project's")


class PipeCheck(unittest.TestCase):
    """Checks the stdin pipeline check of formatters (cmd.check = {"pipe": [...]})."""

    def _check(self, d, files, *filters):
        """Run a pipe check of fake formatters on files of the repository d.

        Args:
            d: the repository root.
            files: repository-relative files.
            *filters: Python sources; each reads stdin and writes stdout.

        Returns:
            StepResult: the check result.
        """
        pipe = [[sys.executable, "-c", src, "{file}"] for src in filters]
        tool = {
            "id": "fake-pipe",
            "role": "format",
            "cmd": {"fix": ["true"], "check": {"pipe": pipe}},
        }
        ctx = runner.Ctx(d, "check", d, {}, set())
        return runner.run_tool(tool, {}, None, ctx, files, None, "python")

    def test_identity_keeps_bytes_and_crlf(self):
        """A filter that changes nothing passes, CRLF files included (bytes, not text mode)."""
        with tempfile.TemporaryDirectory() as d:
            _write(os.path.join(d, "a.py"), b"x = 1\r\ny = 2\r\n")
            res = self._check(d, ["a.py"], COPY, COPY)
            self.assertEqual(res.status, {"a.py": "SUCCESS"}, res.output)

    def test_change_is_reported_and_file_left_alone(self):
        """A filter that changes the text fails the check; the file is not rewritten."""
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "a.py")
            _write(p, b"x\n")
            res = self._check(d, ["a.py"], COPY, UPPER)
            self.assertEqual(res.status, {"a.py": "ERROR"})
            self.assertIn("a.py: not formatted (a commit formats it)", res.output)
            with open(p, "rb") as fh:
                self.assertEqual(fh.read(), b"x\n")

    def test_failing_filter_is_an_error_with_its_message(self):
        """A filter that exits non-zero marks the file ERROR and keeps its stderr."""
        with tempfile.TemporaryDirectory() as d:
            _write(os.path.join(d, "a.py"), b"x\n")
            res = self._check(d, ["a.py"], "import sys\nsys.exit('boom')\n")
            self.assertEqual(res.status, {"a.py": "ERROR"})
            self.assertIn("a.py: boom", res.output)

    def test_runs_in_the_real_repository(self):
        """The filters run with the fix mode's working directory and the real file path."""
        with tempfile.TemporaryDirectory() as d:
            _write(os.path.join(d, "sub", "a.py"), b"ok\n")
            res = self._check(d, ["sub/a.py"], SEES_FILE)
            self.assertEqual(res.status, {"sub/a.py": "SUCCESS"}, res.output)


@unittest.skipUnless(shutil.which("ruff"), "ruff is not installed (it is in the gate image)")
class RuffCheckAgreesWithFix(unittest.TestCase):
    """With real ruff: a file the fix formats passes the check, whatever the project layout."""

    UNSORTED = "import mypkg\nimport requests\nimport os\n\nx=1\n"

    def _roundtrip(self, d, f, cfg=None):
        """Fix f in the repository d, then check it.

        Args:
            d: the repository root.
            f: the repository-relative file.
            cfg: generated ruff.toml path, or None to let ruff find the project's config.

        Returns:
            tuple: (fixed text, check StepResult).
        """
        cfgs = {("python", "ruff-format"): cfg} if cfg else {}
        tool = REG.tools["ruff-format"]
        fix = runner.Ctx(d, "fix", d, cfgs, set())
        runner.run_tool(tool, {}, None, fix, [f], None, "python")
        with open(os.path.join(d, f), encoding="utf-8") as fh:
            text = fh.read()
        check = runner.Ctx(d, "check", d, cfgs, set())
        return text, runner.run_tool(tool, {}, None, check, [f], None, "python")

    def _layout(self, d, pkg_dir, f, pyproject=None):
        """Write a package mypkg under pkg_dir and an unsorted module f.

        Args:
            d: the repository root.
            pkg_dir: folder holding mypkg ("" for the root).
            f: the repository-relative module to write.
            pyproject: text of pyproject.toml, or None for none.
        """
        _write(os.path.join(d, pkg_dir, "mypkg", "__init__.py"), b"")
        _write(os.path.join(d, f), self.UNSORTED)
        if pyproject:
            _write(os.path.join(d, "pyproject.toml"), pyproject)

    def _assert_first_party(self, text, res):
        """The fix put mypkg in its own (first-party) block and the check agrees.

        Args:
            text: the fixed module.
            res: the check result.
        """
        self.assertIn("import requests\n\nimport mypkg\n", text)
        self.assertEqual(set(res.status.values()), {"SUCCESS"}, res.output)

    def test_project_src_layout(self):
        """A project with src = ["src"] keeps its own packages first-party in both modes."""
        with tempfile.TemporaryDirectory() as d:
            self._layout(d, "src", "app/main.py", SRC_LAYOUT)
            self._assert_first_party(*self._roundtrip(d, "app/main.py"))

    def test_project_src_layout_with_generated_config(self):
        """With the gate's generated ruff.toml, src/ packages stay first-party in both modes."""
        with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as c:
            cfg = os.path.join(c, "ruff.toml")
            _write(cfg, GENERATED_CFG)
            self._layout(d, "src", "app/main.py", SRC_LAYOUT)
            self._assert_first_party(*self._roundtrip(d, "app/main.py", cfg))

    def test_root_package_like_registry(self):
        """The original case: a package at the repository root (registry/) is first-party."""
        with tempfile.TemporaryDirectory() as d, tempfile.TemporaryDirectory() as c:
            cfg = os.path.join(c, "ruff.toml")
            _write(cfg, GENERATED_CFG)
            self._layout(d, "", "engine/qs.py")
            self._assert_first_party(*self._roundtrip(d, "engine/qs.py", cfg))


QS = os.path.join(ROOT, "engine", "qs.py")

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
