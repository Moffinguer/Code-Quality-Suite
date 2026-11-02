"""Unit tests for the 5.x policy keys, the one-time migration and registry.json.

python3 -m unittest discover -s tests/unit -v
"""

import copy
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402
import qs  # noqa: E402

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
        self.assertEqual(data["branches"]["flow"], "merge")
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
        data["branches"]["flow"] = "squash"
        msgs = policy.migrate(data)
        self.assertEqual(data["branches"]["flow"], "squash")
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


class MigrateFileTest(unittest.TestCase):
    """P5: the on-disk migration keeps line endings, uses a temp file and warns on skips."""

    def run_cli(self, path):
        """Run `policy.py migrate PATH`.

        Args:
            path: the rules file.

        Returns:
            subprocess.CompletedProcess: the finished process (text output captured).
        """
        script = os.path.join(ROOT, "engine", "policy.py")
        return subprocess.run(
            [sys.executable, script, "migrate", path], check=True, capture_output=True, text=True
        )

    def test_crlf_kept_no_temp_left(self):
        """A CRLF file stays CRLF and no .tmp file is left behind."""
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, ".quality-rules.json")
            text = json.dumps(old_file(), indent=2).replace("\n", "\r\n")
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(text)
            self.run_cli(path)
            with open(path, "rb") as fh:
                raw = fh.read()
            self.assertEqual(raw.count(b"\n"), raw.count(b"\r\n"))
            self.assertEqual(os.listdir(d), [".quality-rules.json"])

    def test_bom_skipped_with_warning(self):
        """A BOM file is not touched and the reason goes to stderr."""
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, ".quality-rules.json")
            raw = policy.BOM_UTF8 + json.dumps(old_file()).encode("utf-8")
            with open(path, "wb") as fh:
                fh.write(raw)
            res = self.run_cli(path)
            self.assertIn("BOM", res.stderr)
            with open(path, "rb") as fh:
                self.assertEqual(fh.read(), raw)

    def test_non_utf8_skipped_with_warning(self):
        """A non-UTF-8 file is not touched and the reason goes to stderr."""
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, ".quality-rules.json")
            raw = b'{"x": "\xe9"}'
            with open(path, "wb") as fh:
                fh.write(raw)
            res = self.run_cli(path)
            self.assertIn("not UTF-8", res.stderr)
            with open(path, "rb") as fh:
                self.assertEqual(fh.read(), raw)


class SyncRulesTest(unittest.TestCase):
    """P5: App.sync_rules migrates existing files and creates new ones with squash."""

    def make_app(self, root):
        """Build an App on a temp repo in persisting fix mode and load its rules.

        Args:
            root: the repository folder.

        Returns:
            qs.App: the engine instance with its rules loaded.
        """
        keys = {"QS_ROOT": root, "QUALITY_MODE": "fix", "QS_PERSIST": "1", "QS_STATE": ""}
        saved = {k: os.environ.get(k) for k in keys}
        os.environ.update(keys)
        self.addCleanup(self.restore_env, saved)
        app = qs.App()
        self.assertTrue(app.load_rules())
        return app

    @staticmethod
    def restore_env(saved):
        """Put back the environment variables changed by make_app.

        Args:
            saved: {name: previous value or None}.
        """
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def test_existing_file_gets_merge(self):
        """An existing 4.x file is migrated to flow merge and reports 'policy'."""
        with tempfile.TemporaryDirectory() as d:
            data = old_file()
            data["version"] = 1
            with open(os.path.join(d, ".quality-rules.json"), "w", encoding="utf-8") as fh:
                json.dump(data, fh)
            app = self.make_app(d)
            changed = app.sync_rules([], {})
            self.assertIn("policy", changed)
            self.assertEqual(app.data["branches"]["flow"], "merge")
            self.assertEqual(app.data["branches"]["model"], 5)

    def test_new_file_gets_squash(self):
        """A rules file created by the engine skips the migration and defaults to squash."""
        with tempfile.TemporaryDirectory() as d:
            app = self.make_app(d)
            self.assertNotIn("policy", app.sync_rules([], {}))
            self.assertEqual(app.data["branches"]["flow"], "squash")


class InstallE2ETest(unittest.TestCase):
    """P5: install.sh migrates the rules file of a real git repository (end to end)."""

    def install(self, repo):
        """Run install.sh on a repository without building the image.

        Args:
            repo: the repository folder.

        Returns:
            subprocess.CompletedProcess: the finished process (text output captured).
        """
        home = tempfile.mkdtemp(prefix="qs-home-")
        self.addCleanup(shutil.rmtree, home, True)
        env = dict(os.environ, QS_SKIP_IMAGE="1", QS_REPO_FILES="0", QS_HOME=home)
        return subprocess.run(
            ["bash", os.path.join(ROOT, "install.sh"), repo],
            capture_output=True,
            text=True,
            env=env,
            check=False,
        )

    def make_repo(self, d, data):
        """Create a git repository with a rules file.

        Args:
            d: the folder.
            data: the rules data to write.

        Returns:
            str: the path of the rules file.
        """
        subprocess.run(["git", "init", "-q", d], check=True)
        path = os.path.join(d, ".quality-rules.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
        return path

    def test_install_migrates_once(self):
        """flow merge, model 5, levels[1] rewritten, notice shown; 2nd run is a no-op."""
        if not shutil.which("bash") or not shutil.which("git"):
            self.skipTest("bash and git are required")
        with tempfile.TemporaryDirectory() as d:
            path = self.make_repo(d, old_file())
            res = self.install(d)
            self.assertEqual(res.returncode, 0, res.stderr)
            with open(path, encoding="utf-8") as fh:
                got = json.load(fh)
            self.assertEqual(got["branches"]["flow"], "merge")
            self.assertEqual(got["branches"]["model"], 5)
            self.assertEqual(got["branches"]["levels"][1], policy.OT_RX)
            self.assertIn("squash", res.stdout + res.stderr)
            with open(path, "rb") as fh:
                first = fh.read()
            self.assertEqual(self.install(d).returncode, 0)
            with open(path, "rb") as fh:
                self.assertEqual(fh.read(), first)

    def test_custom_level_untouched(self):
        """A custom levels[1] survives the migration."""
        if not shutil.which("bash") or not shutil.which("git"):
            self.skipTest("bash and git are required")
        with tempfile.TemporaryDirectory() as d:
            path = self.make_repo(d, old_file(r"^[A-Z]+-[0-9]+$"))
            self.assertEqual(self.install(d).returncode, 0)
            with open(path, encoding="utf-8") as fh:
                self.assertEqual(json.load(fh)["branches"]["levels"][1], r"^[A-Z]+-[0-9]+$")


class SchemaTest(unittest.TestCase):
    """P7: the schema says which keys apply to flow = merge."""

    def test_descriptions(self):
        """leaf_merge and tag_level descriptions mention flow = merge."""
        path = os.path.join(ROOT, "schema", "quality-rules.schema.json")
        with open(path, encoding="utf-8") as fh:
            schema = json.load(fh)
        props = schema["properties"]["branches"]["properties"]
        for key in ("leaf_merge", "tag_level"):
            self.assertIn("flow = merge", props[key]["description"])


class RegistryTest(unittest.TestCase):
    """P6: registry.json carries no version."""

    def test_no_version(self):
        """registry.json has no top-level version key."""
        with open(os.path.join(ROOT, "registry", "registry.json"), encoding="utf-8") as fh:
            self.assertNotIn("version", json.load(fh))


if __name__ == "__main__":
    unittest.main()
