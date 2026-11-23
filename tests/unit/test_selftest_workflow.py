"""Static checks of .github/workflows/selftest.yml (ST1-ST4)."""

import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATH = os.path.join(ROOT, ".github", "workflows", "selftest.yml")


def _text():
    """Return the workflow text.

    Returns:
        The content of selftest.yml.
    Raises:
        OSError: when the file is missing.
    """
    with open(PATH, encoding="utf-8") as handle:
        return handle.read()


class SelftestWorkflow(unittest.TestCase):
    """Checks the contract of the selftest workflow."""

    def test_reusable(self):
        """ST1: the workflow is reusable and runs the three suites."""
        text = _text()
        self.assertRegex(text, r"(?m)^on:\n  workflow_call:")
        for needle in ("unittest discover", "gen.py --check", "tests/hooks/run.sh"):
            self.assertIn(needle, text)

    def test_no_paths_filter(self):
        """ST2: no workflow-level paths filter; a skip summary exists."""
        text = _text()
        self.assertIsNone(re.search(r"(?m)^\s*paths(-ignore)?:", text))
        self.assertIn("skipped: no code change", text)

    def test_hardening(self):
        """ST4: read-only token and a 20 minute timeout."""
        text = _text()
        self.assertRegex(text, r"(?m)^permissions:\n  contents: read")
        self.assertIn("timeout-minutes: 20", text)


if __name__ == "__main__":
    unittest.main()
