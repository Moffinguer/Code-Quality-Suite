"""Unit tests for engine/gitio.py."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "engine"))
import gitio  # noqa: E402 - needs the engine folder on the path

PY = [sys.executable, "-c"]


class GitIo(unittest.TestCase):
    """git_out / git_strict contracts, driven with the Python interpreter as the command."""

    def test_ok_returns_stdout(self):
        self.assertEqual(gitio.git_out(PY, "print('hi')").strip(), "hi")

    def test_failure_quiet_is_empty(self):
        self.assertEqual(gitio.git_out(PY, "import sys; sys.exit(3)"), "")

    def test_failure_strict_raises(self):
        with self.assertRaises(RuntimeError):
            gitio.git_strict(PY, "import sys; sys.exit(3)")

    def test_missing_binary(self):
        self.assertEqual(gitio.git_out(["no-such-binary-qs"]), "")
        with self.assertRaises(OSError):
            gitio.git_strict(["no-such-binary-qs"])


if __name__ == "__main__":
    unittest.main()
