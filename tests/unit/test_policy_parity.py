"""Parity of the policy defaults: scripts/git-flow-lib.sh qs_policy_defaults vs engine/policy.py.

Both sides write the built-in defaults (spec 7.1.1 S11). The special-branch table has its own
test in test_special.py; this one covers every other exported QS_* key.
"""

import os
import shutil
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402

LIB = os.path.join(ROOT, "scripts", "git-flow-lib.sh").replace("\\", "/")
DUMP = 'for v in $(compgen -v QS_); do printf "%s=%s\\n" "$v" "${!v}"; done'


def shell_defaults():
    """Run qs_policy_defaults in bash and read back every QS_* variable.

    Returns:
        dict[str, str]: variable name -> value.

    Raises:
        subprocess.CalledProcessError: when bash fails to source the library.
    """
    res = subprocess.run(
        ["bash", "-c", f'. "{LIB}"; qs_policy_defaults; {DUMP}'],
        capture_output=True,
        check=True,
    )
    pairs = (ln.partition("=") for ln in res.stdout.decode("utf-8").splitlines())
    return {k: v for k, _, v in pairs}


def engine_defaults():
    """The defaults exported by engine/policy.py as shell variables.

    Returns:
        dict[str, str]: variable name -> value, parsed from shell_env({}).
    """
    out = {}
    for line in policy.shell_env({}).splitlines():
        key, _, val = line.partition("=")
        out[key] = val[1:-1].replace("'''", "'")
    return out


class PolicyParityTest(unittest.TestCase):
    """qs_policy_defaults equals policy.DEFAULTS for every exported key."""

    @unittest.skipUnless(shutil.which("bash"), "bash is required")
    def test_every_exported_key_matches(self):
        """Each key of policy.shell_env({}) has the same default in the shell library."""
        lib, eng = shell_defaults(), engine_defaults()
        self.assertTrue(eng)
        missing = sorted(k for k in eng if k not in lib)
        self.assertEqual(missing, [], "keys exported by policy.py but unset by the library")
        diff = {k: (lib[k], v) for k, v in eng.items() if lib[k] != v}
        self.assertEqual(diff, {}, "shell default != engine default (shell, engine)")


if __name__ == "__main__":
    unittest.main()
