"""Unit tests for the special branch hook rules (6.0.0 `hooks_rules` task).

python3 -m unittest discover -s tests/unit -v

Covers the gate level override of the engine (QS_GATE_LEVEL) and the parity of the shell path
tokens (exported as QS_SP_<TYPE>_GLOBS) with `policy.expand_paths`.
"""

import os
import shutil
import subprocess
import sys
import tempfile
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
    """The hooks read the expanded globs from the engine export; no second copy of the tokens."""

    def shell_globs(self, data):
        """Load the shell defaults and the engine export, and read QS_SP_*_GLOBS in shell.

        Args:
            data: the rules to export (dict).

        Returns:
            dict[str, str]: type -> the GLOBS value the shell sees after loading policy.env.
        """
        with tempfile.TemporaryDirectory() as d:
            env_file = os.path.join(d, "policy.env").replace("\\", "/")
            with open(env_file, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(policy.shell_env(data))
            code = (
                f'. "{LIB}"; . "$1"; for t in $QS_SP_NAMES; do special_prop "$t" GLOBS; echo; done'
            )
            out = subprocess.run(
                ["bash", "-c", code, "_", env_file], capture_output=True, text=True, check=True
            )
        return dict(zip(policy.special_table(data), out.stdout.split("\n"), strict=False))

    def test_tokens_expanded_in_export(self):
        """GLOBS is PATHS with every @token expanded by policy.expand_paths."""
        data = {"branches": {"special": {"TESTS": {"paths": ["@tests", "qa/**"]}}}}
        env = policy.special_env(data)
        self.assertEqual(
            env["QS_SP_TESTS_GLOBS"], "|".join(policy.expand_paths(["@tests", "qa/**"]))
        )
        self.assertEqual(env["QS_SP_DOCS_GLOBS"], "|".join(policy.expand_paths(["@docs"])))
        self.assertEqual(env["QS_SP_MIGRATION_GLOBS"], "")

    @unittest.skipUnless(shutil.which("bash"), "bash is required")
    def test_shell_sees_expanded_globs(self):
        """The shell reads the same globs, for every @token of the engine."""
        for token in policy.PATH_TOKENS:
            data = {"branches": {"special": {"TESTS": {"paths": [token]}}}}
            got = self.shell_globs(data)["TESTS"]
            self.assertEqual(got.split("|"), policy.expand_paths([token]), token)


if __name__ == "__main__":
    unittest.main()
