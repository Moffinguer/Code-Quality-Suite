"""Unit tests of the generated-rules marker (7.1.1 flow_guard, FG3).

python3 -m unittest discover -s tests/unit -v

The engine records the sha256 of a rules file it creates in `<state>/rules.generated`; `git integra`
(tests/hooks/cases/flow_guard.sh) refuses a linked worktree whose file still has that hash.
"""

import hashlib
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import qs  # noqa: E402


def make_app(root, state):
    """An engine App with only the fields the rules file code reads.

    Args:
        root: folder that holds the rules file.
        state: the state folder (the marker goes there).

    Returns:
        qs.App: an instance built without running its constructor.
    """
    app = qs.App.__new__(qs.App)
    app.rules_path = os.path.join(root, ".quality-rules.json")
    app.state = state
    app.persist = True
    app.reg = None
    app.data = {"branches": {}}
    app._loaded = {}
    app._created = True
    return app


class MarkerTest(unittest.TestCase):
    """FG3: the marker is written for a generated file and follows it, never for a real one."""

    def setUp(self):
        """Create a root folder and a state folder (removed at the end of the test)."""
        self.root = tempfile.mkdtemp(prefix="qs-mk-")
        self.addCleanup(shutil.rmtree, self.root, True)
        self.state = os.path.join(self.root, "state")
        os.mkdir(self.state)
        self.app = make_app(self.root, self.state)
        self.marker = os.path.join(self.state, "rules.generated")

    def sha(self):
        """The sha256 of the rules file on disk.

        Returns:
            str: the hex digest.
        """
        with open(self.app.rules_path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()

    def sync(self):
        """Run sync_rules with the policy and the languages stubbed out.

        Returns:
            list[str]: what sync_rules reports.
        """
        with (
            mock.patch.object(qs.App, "_migrate", return_value=[]),
            mock.patch.object(
                qs.policy, "populate", side_effect=lambda d: d.setdefault("p", 1) and []
            ),
            mock.patch.object(qs.rules, "populate_global", return_value=False),
        ):
            return self.app.sync_rules([], {})

    def test_creation_writes_the_hash(self):
        """A rules file created by the engine gets a marker with its sha256."""
        self.sync()
        self.assertTrue(os.path.isfile(self.app.rules_path))
        with open(self.marker, encoding="utf-8") as fh:
            self.assertEqual(fh.read().strip(), self.sha())
        self.assertTrue(self.app._is_generated())

    def test_update_follows_a_generated_file(self):
        """When the engine changes a file that still is the generated one, the marker follows."""
        self.sync()
        self.app._created = False
        self.app._loaded = {}
        self.app.data = {"branches": {"flow": "merge", "x": 1}}
        self.sync()
        with open(self.marker, encoding="utf-8") as fh:
            self.assertEqual(fh.read().strip(), self.sha())

    def test_edited_file_is_no_longer_generated(self):
        """A file the project edited (another hash) is real: it is not marked again."""
        self.sync()
        with open(self.app.rules_path, "w", encoding="utf-8") as fh:
            json.dump({"branches": {"flow": "squash"}}, fh)
        self.assertFalse(self.app._is_generated())
        self.app._created = False
        self.app._loaded = {}
        self.app.data = {"branches": {"flow": "squash", "y": 2}}
        self.sync()
        with open(self.marker, encoding="utf-8") as fh:
            self.assertNotEqual(fh.read().strip(), self.sha())

    def test_existing_real_file_gets_no_marker(self):
        """A rules file that existed before the run never gets a marker."""
        with open(self.app.rules_path, "w", encoding="utf-8") as fh:
            json.dump({"branches": {"flow": "squash"}}, fh)
        self.app._created = False
        self.app._loaded = {"branches": {"flow": "squash"}}
        self.app.data = {"branches": {"flow": "squash", "z": 3}}
        self.sync()
        self.assertFalse(os.path.exists(self.marker))

    def test_no_state_folder_is_fine(self):
        """Without a writable state folder the file is saved and no marker is written."""
        self.app.state = ""
        self.sync()
        self.assertTrue(os.path.isfile(self.app.rules_path))
        self.assertFalse(self.app._is_generated())


if __name__ == "__main__":
    unittest.main()
