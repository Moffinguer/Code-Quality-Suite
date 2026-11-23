"""Edge cases of the ruff-format stdin check: it must give the verdict the fix gives.

For each input the check runs on the repository and the fix on the same repository; a check
that passes must mean the fix changes nothing, and a check that fails must mean the fix
changes the bytes.

python3 -m unittest discover -s tests/unit -v
"""

import os
import shutil
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
UNSORTED = b"import mypkg\nimport requests\nimport os\n\nx=1\n"
SORTED = b"import os\n\nimport requests\n\nimport mypkg\n\nx = 1\n"


def _write(path, data):
    """Write bytes to path, creating its folder.

    Args:
        path: the file to write.
        data: the bytes to write.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)


def _read(path):
    """Read a file as bytes.

    Args:
        path: the file to read.

    Returns:
        bytes: the content.
    """
    with open(path, "rb") as fh:
        return fh.read()


@unittest.skipUnless(shutil.which("ruff"), "ruff is not installed (it is in the gate image)")
class RuffPipeEdges(unittest.TestCase):
    """Check and fix agree on odd inputs (empty, CRLF, non-UTF-8, spaces, large, unformatted)."""

    def _verdicts(self, rel, data, extra=None):
        """Check a file in a repository, then fix it.

        Args:
            rel: repository-relative path of the file.
            data: its bytes.
            extra: optional {relative path: bytes} files to add (config, packages).

        Returns:
            tuple: (check StepResult, bytes after the fix).
        """
        tool = REG.tools["ruff-format"]
        with tempfile.TemporaryDirectory() as d:
            _write(os.path.join(d, rel), data)
            for k, v in (extra or {}).items():
                _write(os.path.join(d, k), v)
            chk = runner.run_tool(
                tool, {}, None, runner.Ctx(d, "check", d, {}, set()), [rel], None, "python"
            )
            after_check = _read(os.path.join(d, rel))
            self.assertEqual(after_check, data, "the check must not write")
            runner.run_tool(
                tool, {}, None, runner.Ctx(d, "fix", d, {}, set()), [rel], None, "python"
            )
            return chk, _read(os.path.join(d, rel))

    def _agree(self, rel, data, extra=None):
        """Assert the check says SUCCESS exactly when the fix leaves the bytes alone.

        Args:
            rel: repository-relative path of the file.
            data: its bytes.
            extra: optional extra files, as in _verdicts.

        Returns:
            tuple: (check StepResult, bytes after the fix).
        """
        chk, fixed = self._verdicts(rel, data, extra)
        self.assertEqual(chk.status[rel] == "SUCCESS", fixed == data, (chk.status, chk.output))
        return chk, fixed

    def test_empty_file(self):
        """An empty file is formatted: check passes, fix is a no-op."""
        chk, _ = self._agree("a.py", b"")
        self.assertEqual(chk.status["a.py"], "SUCCESS", chk.output)

    def test_crlf_formatted_file(self):
        """A CRLF file ruff keeps as CRLF passes (bytes are compared, not text)."""
        chk, _ = self._agree("a.py", b"x = 1\r\ny = 2\r\n")
        self.assertEqual(chk.status["a.py"], "SUCCESS", chk.output)

    def test_crlf_unformatted_file(self):
        """A CRLF file that needs formatting is reported."""
        chk, _ = self._agree("a.py", b"x=1\r\ny=2\r\n")
        self.assertEqual(chk.status["a.py"], "ERROR")

    def test_non_utf8_bytes(self):
        """A latin-1 file ruff cannot read is an ERROR with ruff's message; fix leaves it alone."""
        data = b"# caf\xe9\nx = 1\n"
        chk, fixed = self._verdicts("a.py", data)
        self.assertEqual(chk.status["a.py"], "ERROR")
        self.assertTrue(any("UTF-8" in line for line in chk.output), chk.output)
        self.assertEqual(fixed, data)

    def test_path_with_spaces(self):
        """A path with spaces reaches --stdin-filename intact; the src layout still applies."""
        extra = {
            "src dir/mypkg/__init__.py": b"",
            "pyproject.toml": b'[tool.ruff]\nsrc=["src dir"]\n',
        }
        chk, fixed = self._agree("src dir/my mod.py", UNSORTED, extra)
        self.assertEqual(chk.status["src dir/my mod.py"], "ERROR")
        self.assertIn(b"import requests\n\nimport mypkg\n", fixed)

    def test_unformatted_is_reported_and_untouched(self):
        """An unformatted file is ERROR with the usual message."""
        chk, _ = self._agree("a.py", b"x=1\n")
        self.assertEqual(chk.status, {"a.py": "ERROR"})
        self.assertIn("a.py: not formatted (a commit formats it)", chk.output)

    def test_syntax_error_is_not_a_pass(self):
        """A file ruff cannot parse is never reported as formatted."""
        chk, _ = self._verdicts("a.py", b"def (:\n")
        self.assertEqual(chk.status["a.py"], "ERROR", chk.output)

    def test_large_file(self):
        """A 5 MB formatted file passes and an unformatted one is reported."""
        body = b"x = 1\n" * 900000
        chk, _ = self._agree("big.py", body)
        self.assertEqual(chk.status["big.py"], "SUCCESS", chk.output)
        chk, _ = self._agree("big2.py", body + b"y=2\n" * 1 + b"z=3\n")
        self.assertEqual(chk.status["big2.py"], "ERROR")

    def test_ruff_toml_src(self):
        """src in ruff.toml (not pyproject) keeps the project's isort classification."""
        extra = {"src/mypkg/__init__.py": b"", "ruff.toml": b'src = ["src"]\n'}
        chk, fixed = self._agree("app/main.py", UNSORTED, extra)
        self.assertIn(b"import requests\n\nimport mypkg\n", fixed)
        self.assertEqual(chk.status["app/main.py"], "ERROR")

    def test_ruff_toml_src_formatted_passes(self):
        """A file already sorted under the project's src passes the check."""
        extra = {"src/mypkg/__init__.py": b"", "ruff.toml": b'src = ["src"]\n'}
        chk, _ = self._agree("app/main.py", SORTED, extra)
        self.assertEqual(chk.status["app/main.py"], "SUCCESS", chk.output)


if __name__ == "__main__":
    unittest.main()
