"""Unit tests for the 5.x policy keys, the one-time migration and registry.json.

python3 -m unittest discover -s tests/unit -v
"""

import copy
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402

OLD_OT = r"^[0-9]+$"


def old_file(levels1=OLD_OT):
    """Rules data as written by 4.x: no model, no flow, levels[1] set.

    Args:
        levels1: value of branches.levels[1].

    Returns:
        dict: the rules data.
    """
    br = copy.deepcopy(policy.DEFAULTS["branches"])
    for k in ("model", "flow", "ot_tag", "testing_leaf"):
        del br[k]
    br["levels"][1] = levels1
    return {"branches": br}


class DefaultsTest(unittest.TestCase):
    """P1/P2: defaults, validation and the shell export."""

    def test_defaults(self):
        """The new keys have the documented defaults."""
        br, com = policy.DEFAULTS["branches"], policy.DEFAULTS["commit"]
        self.assertEqual(br["flow"], "squash")
        self.assertEqual(br["ot_tag"], "ot/{version}/{ot}")
        self.assertEqual(br["model"], 5)
        self.assertEqual(br["testing_leaf"], "TESTING")
        self.assertEqual(com["files"], "block")
        self.assertEqual(policy.validate({}), [])

    def test_validate_rejects(self):
        """Bad flow, files, ot_tag and testing_leaf are reported."""
        bad = {
            "branches": {"flow": "rebase", "ot_tag": "ot/{version}", "testing_leaf": "ORIGINAL"},
            "commit": {"files": "maybe"},
        }
        text = "\n".join(policy.validate(bad))
        for key in ("branches.flow", "branches.ot_tag", "branches.testing_leaf", "commit.files"):
            self.assertIn(key, text)

    def test_validate_accepts_empty_ot_tag(self):
        """An empty ot_tag means no tag and is valid."""
        self.assertEqual(policy.validate({"branches": {"ot_tag": ""}}), [])

    def test_shell_env(self):
        """The shell export has the new variables."""
        env = policy.shell_env({})
        self.assertIn("QS_BR_FLOW='squash'\n", env)
        self.assertIn("QS_BR_OT_TAG='ot/{version}/{ot}'\n", env)
        self.assertIn("QS_BR_TESTING='TESTING'\n", env)
        self.assertIn("QS_COMMIT_FILES='block'\n", env)

    def test_shell_defaults_match(self):
        """qs_policy_defaults in git-flow-lib.sh sets the same values."""
        with open(os.path.join(ROOT, "scripts", "git-flow-lib.sh"), encoding="utf-8") as fh:
            lib = fh.read()
        for frag in (
            "QS_BR_FLOW=squash",
            "QS_BR_OT_TAG='ot/{version}/{ot}'",
            "QS_BR_TESTING=TESTING",
            "QS_COMMIT_FILES=block",
        ):
            self.assertIn(frag, lib)


class MigrateTest(unittest.TestCase):
    """P3/P4/P5: the one-time migration."""

    def test_old_default_rewritten(self):
        """levels[1] == ^[0-9]+$ becomes the alphanumeric default; model and flow are set."""
        data = old_file()
        msgs = policy.migrate(data)
        self.assertEqual(data["branches"]["levels"][1], policy.OT_RX)
        self.assertEqual(data["branches"]["model"], 5)
        self.assertEqual(data["branches"]["flow"], "squash")
        self.assertTrue(any("migrated branches.levels[1]" in m for m in msgs))
        self.assertTrue(any(policy.FLOW_NOTICE in m for m in msgs))
        levels = data["branches"]["levels"]
        self.assertRegex("5.0.0-RC1", re.compile(levels[0]))
        self.assertRegex("git", re.compile(levels[1]))

    def test_custom_level_kept_and_idempotent(self):
        """A deliberate levels[1] is kept; a second run changes nothing."""
        data = old_file(r"^[A-Z]+-[0-9]+$")
        policy.migrate(data)
        self.assertEqual(data["branches"]["levels"][1], r"^[A-Z]+-[0-9]+$")
        before = copy.deepcopy(data)
        self.assertEqual(policy.migrate(data), [])
        self.assertEqual(data, before)

    def test_existing_flow_kept(self):
        """A flow already chosen is not overwritten and gives no notice."""
        data = old_file()
        data["branches"]["flow"] = "merge"
        msgs = policy.migrate(data)
        self.assertEqual(data["branches"]["flow"], "merge")
        self.assertFalse(any(policy.FLOW_NOTICE in m for m in msgs))

    def test_no_branches_section(self):
        """Without a branches section there is nothing to migrate."""
        data = {}
        self.assertEqual(policy.migrate(data), [])
        self.assertEqual(data, {})

    def test_file_cli(self):
        """`policy.py migrate FILE` rewrites the file (git instalar / actualizar-suite)."""
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, ".quality-rules.json")
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(old_file(), fh)
            script = os.path.join(ROOT, "engine", "policy.py")
            subprocess.run(
                [sys.executable, script, "migrate", path], check=True, capture_output=True
            )
            with open(path, encoding="utf-8") as fh:
                got = json.load(fh)
            self.assertEqual(got["branches"]["levels"][1], policy.OT_RX)
            self.assertEqual(got["branches"]["model"], 5)


class RegistryTest(unittest.TestCase):
    """P6: registry.json carries no version."""

    def test_no_version(self):
        """registry.json has no top-level version key."""
        with open(os.path.join(ROOT, "registry", "registry.json"), encoding="utf-8") as fh:
            self.assertNotIn("version", json.load(fh))


if __name__ == "__main__":
    unittest.main()
