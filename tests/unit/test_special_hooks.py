"""Unit tests for the special branch hook rules (6.0.0 `hooks_rules` task).

python3 -m unittest discover -s tests/unit -v

Covers the gate level override of the engine (QS_GATE_LEVEL) and the parity of the shell path
tokens (`special_expand_paths`) with `policy.expand_paths`.
"""

import os
import subprocess
import sys
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402
import qs  # noqa: E402

LIB = os.path.join(ROOT, "scripts", "git-flow-lib.sh").replace("\\", "/")


class GateLevelTest(unittest.TestCase):
    """QS_GATE_LEVEL wins over the language level and the project level."""

    DATA = {
        "level": "format",
        "languages": {"python": {"level": "format"}, "bash": {"enabled": False}},
    }

    def test_no_override(self):
        """Without the variable the usual levels apply."""
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("QS_GATE_LEVEL", None)
            self.assertEqual(qs.gate_override(), "")
            self.assertEqual(qs.GateRules.lang_level(self.DATA, "python"), "format")

    def test_override_wins(self):
        """A known level replaces the language level; a disabled language stays off."""
        with mock.patch.dict(os.environ, {"QS_GATE_LEVEL": "strict"}):
            self.assertEqual(qs.gate_override(), "strict")
            self.assertEqual(qs.GateRules.lang_level(self.DATA, "python"), "strict")
            self.assertEqual(qs.GateRules.lang_level(self.DATA, "bash"), "off")

    def test_unknown_level_ignored(self):
        """An unknown value is no override."""
        with mock.patch.dict(os.environ, {"QS_GATE_LEVEL": "loud"}):
            self.assertEqual(qs.gate_override(), "")

    def test_delegates_other_attributes(self):
        """GateRules behaves as the rules module for everything but lang_level."""
        self.assertTrue(callable(qs.GateRules().validate))


class PathTokensTest(unittest.TestCase):
    """The shell expansion of @tokens equals policy.expand_paths."""

    def shell(self, token):
        """Expand one token with special_expand_paths.

        Args:
            token: the @token or glob.

        Returns:
            list[str]: the globs printed one per line.
        """
        code = f'. "{LIB}"; special_expand_paths "$1"'
        out = subprocess.run(
            ["bash", "-c", code, "_", token], capture_output=True, text=True, check=True
        )
        return out.stdout.split()

    def test_tokens_match_policy(self):
        """Every token of the engine expands to the same globs in shell."""
        for token in policy.PATH_TOKENS:
            self.assertEqual(self.shell(token), policy.expand_paths([token]), token)

    def test_plain_glob_kept(self):
        """A plain glob is kept as is."""
        self.assertEqual(self.shell("qa/**"), ["qa/**"])


if __name__ == "__main__":
    unittest.main()
