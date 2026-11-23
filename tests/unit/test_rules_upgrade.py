"""Unit tests of the rules file upgrade on a suite update (6.0.0 `rules_upgrade`, RU1-RU4, RU8).

python3 -m unittest discover -s tests/unit -v

The shell side (RU5-RU7, RU9, RU10: git actualizar-suite, the lazy hook check, git instalar) is in
tests/hooks/cases/rules_upgrade.sh.
"""

import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402

POLICY_PY = os.path.join(ROOT, "engine", "policy.py")
QS_PY = os.path.join(ROOT, "engine", "qs.py")


def suite_version():
    """The VERSION of this suite folder.

    Returns:
        str: the version text.
    """
    with open(os.path.join(ROOT, "VERSION"), encoding="utf-8") as fh:
        return fh.read().strip()


def old_rules():
    """Rules data as a 4.x suite wrote it: no model, no flow, no 5.x or 6.x keys.

    Returns:
        dict: the rules data.
    """
    br = copy.deepcopy(policy.DEFAULTS["branches"])
    for key in ("model", "flow", "ot_tag", "testing_leaf", "special", "publish_on_create"):
        br.pop(key, None)
    return {"branches": br}


def with_publish_default():
    """Patch DEFAULTS so `branches.publish_on_create` (the `autopublish` key) exists.

    The key arrives with the `autopublish` branch; the patch keeps these tests valid before and
    after that branch is integrated.

    Returns:
        unittest.mock._patch_dict: a context manager (the original value is restored on exit).
    """
    return mock.patch.dict(policy.DEFAULTS["branches"], {"publish_on_create": True})


class UpgradeTest(unittest.TestCase):
    """RU1, RU2 and RU3: what `policy.upgrade` adds, never overwrites and repeats."""

    def test_ru1_old_file(self):
        """A 4.x file gets flow merge, model 6, DOCS.on_release and the new keys, notices once."""
        data = old_rules()
        with with_publish_default():
            changes = policy.upgrade(data)
        br = data["branches"]
        self.assertEqual(br["flow"], "merge")
        self.assertEqual(br["model"], 6)
        self.assertEqual(br["special"]["DOCS"]["on_release"], "optional")
        self.assertIs(br["publish_on_create"], True)
        text = "\n".join(changes)
        self.assertIn("added branches.publish_on_create", text)
        self.assertEqual(text.count(policy.FLOW_NOTICE), 1)
        self.assertEqual(text.count(policy.DOCS_NOTICE), 1)

    def test_ru2_never_overwrites(self):
        """Values the project set stay as they are; nothing is written inside a special entry."""
        data = old_rules()
        data["branches"]["flow"] = "squash"
        data["branches"]["model"] = 6
        data["branches"]["publish_on_create"] = False
        data["branches"]["special"] = {"FORMAT": False, "TESTS": {"paths": ["qa/**"]}}
        before = copy.deepcopy(data)
        with with_publish_default():
            policy.upgrade(data)
        br = data["branches"]
        self.assertEqual(br["flow"], "squash")
        self.assertIs(br["publish_on_create"], False)
        self.assertIs(br["special"]["FORMAT"], False)
        self.assertEqual(br["special"]["TESTS"], {"paths": ["qa/**"]})
        self.assertEqual(br["special"], before["branches"]["special"])

    def test_ru2_special_entry_untouched_on_step_6(self):
        """The step 6 migration writes DOCS.on_release only when DOCS is missing or lacks it."""
        data = old_rules()
        data["branches"]["model"] = 5
        data["branches"]["special"] = {"DOCS": {"on_release": "required"}}
        policy.upgrade(data)
        self.assertEqual(data["branches"]["special"], {"DOCS": {"on_release": "required"}})
        self.assertEqual(data["branches"]["model"], 6)

    def test_ru3_second_run_changes_nothing(self):
        """A second upgrade returns no change and leaves the data equal."""
        data = old_rules()
        with with_publish_default():
            self.assertTrue(policy.upgrade(data))
            once = copy.deepcopy(data)
            self.assertEqual(policy.upgrade(data), [])
        self.assertEqual(data, once)

    def test_empty_and_odd_input(self):
        """Not a rules object: only populate runs; a section of another type is kept."""
        data = {"commit": "weird"}
        policy.upgrade(data)
        self.assertEqual(data["commit"], "weird")
        self.assertIn("branches", data)


class RulesUpgradeCliTest(unittest.TestCase):
    """RU3, RU4 and RU8: `policy.py rules-upgrade` and `qs.py rules-upgrade` on a repository."""

    def setUp(self):
        """Create a git repository in a temp folder (removed at the end of the test)."""
        self.repo = tempfile.mkdtemp(prefix="qs-ru-")
        self.addCleanup(shutil.rmtree, self.repo, True)
        subprocess.run(["git", "init", "-q", self.repo], check=True, capture_output=True)
        self.rules = os.path.join(self.repo, ".quality-rules.json")
        self.stamp = os.path.join(self.repo, ".git", "quality-suite", "suite-version")

    def run_cli(self, script="policy"):
        """Run `<script> rules-upgrade <repo>`.

        Args:
            script: 'policy' (policy.py) or 'qs' (qs.py).

        Returns:
            subprocess.CompletedProcess: the finished process (text output captured).
        """
        path = POLICY_PY if script == "policy" else QS_PY
        return subprocess.run(
            [sys.executable, path, "rules-upgrade", self.repo],
            capture_output=True,
            text=True,
            check=False,
        )

    def write_rules(self, text):
        """Write the rules file as bytes.

        Args:
            text: the content (UTF-8).
        """
        with open(self.rules, "wb") as fh:
            fh.write(text.encode("utf-8"))

    def read_stamp(self):
        """The stamp text.

        Returns:
            str: the stamp content, or None when there is none.
        """
        if not os.path.exists(self.stamp):
            return None
        with open(self.stamp, encoding="utf-8") as fh:
            return fh.read().strip()

    def test_ru4_written_file(self):
        """2-space indent, key order kept, new keys after, no BOM, final newline, stamp written."""
        data = old_rules()
        data["zzz_custom"] = {"b": 1, "a": 2}
        self.write_rules(json.dumps({"zzz_custom": data["zzz_custom"], **data}, indent=4))
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stderr)
        with open(self.rules, "rb") as fh:
            raw = fh.read()
        self.assertFalse(raw.startswith(b"\xef\xbb\xbf"))
        self.assertTrue(raw.endswith(b"}\n"))
        text = raw.decode("utf-8")
        self.assertIn('\n  "branches": {\n    "', text)
        got = json.loads(text)
        keys = list(got)
        self.assertEqual(keys[0], "zzz_custom")
        self.assertEqual(list(got["zzz_custom"]), ["b", "a"])
        self.assertGreater(keys.index("encoding"), keys.index("branches"))
        self.assertIn("migrated branches.model: 6", res.stdout)
        self.assertEqual(self.read_stamp(), suite_version())

    def test_ru3_no_rewrite(self):
        """A second run neither rewrites the file (bytes, mtime) nor prints changes."""
        self.write_rules(json.dumps(old_rules()))
        self.assertEqual(self.run_cli().returncode, 0)
        with open(self.rules, "rb") as fh:
            first = fh.read()
        old = time.time() - 3600
        os.utime(self.rules, (old, old))
        mtime = os.stat(self.rules).st_mtime_ns
        res = self.run_cli("qs")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(res.stdout.strip(), "")
        with open(self.rules, "rb") as fh:
            self.assertEqual(fh.read(), first)
        self.assertEqual(os.stat(self.rules).st_mtime_ns, mtime)

    def test_ru4_invalid_json(self):
        """Invalid JSON: exit non-zero, file and stamp untouched."""
        self.write_rules("{ not json")
        res = self.run_cli()
        self.assertNotEqual(res.returncode, 0)
        with open(self.rules, encoding="utf-8") as fh:
            self.assertEqual(fh.read(), "{ not json")
        self.assertIsNone(self.read_stamp())

    def test_no_rules_file(self):
        """No rules file: a note, no file created, the stamp written."""
        res = self.run_cli()
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn("no rules file (created on the first commit)", res.stdout)
        self.assertFalse(os.path.exists(self.rules))
        self.assertEqual(self.read_stamp(), suite_version())

    def test_ru8_stamp_newer(self):
        """A stamp newer than the suite: a warning, the file and the stamp untouched."""
        self.write_rules(json.dumps(old_rules()))
        os.makedirs(os.path.dirname(self.stamp))
        with open(self.stamp, "w", encoding="utf-8") as fh:
            fh.write("99.0.0\n")
        res = self.run_cli()
        self.assertEqual(res.returncode, 0)
        self.assertIn("newer than the suite", res.stderr)
        with open(self.rules, encoding="utf-8") as fh:
            self.assertEqual(json.load(fh), old_rules())
        self.assertEqual(self.read_stamp(), "99.0.0")

    def test_crlf_kept(self):
        """A CRLF file keeps its line ending when it is rewritten."""
        self.write_rules(json.dumps(old_rules(), indent=2).replace("\n", "\r\n"))
        self.assertEqual(self.run_cli().returncode, 0)
        with open(self.rules, "rb") as fh:
            raw = fh.read()
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""))

    def test_linked_worktree_stamp_in_common_dir(self):
        """In a linked worktree the stamp is written under the git common dir."""
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@e.x")
        env.update(GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@e.x")
        subprocess.run(
            ["git", "-C", self.repo, "commit", "-q", "--allow-empty", "-m", "x"],
            check=True,
            capture_output=True,
            env=env,
        )
        wt = self.repo + "-wt"
        self.addCleanup(shutil.rmtree, wt, True)
        subprocess.run(
            ["git", "-C", self.repo, "worktree", "add", "-q", wt, "-b", "other"],
            check=True,
            capture_output=True,
        )
        res = subprocess.run(
            [sys.executable, POLICY_PY, "rules-upgrade", wt],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(self.read_stamp(), suite_version())


if __name__ == "__main__":
    unittest.main()
