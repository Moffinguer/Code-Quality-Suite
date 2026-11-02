"""Unit tests for the 5.x policy keys, the one-time migration and registry.json.

python3 -m unittest discover -s tests/unit -v

Every subprocess and git call runs in an isolated environment (see isolated_env): HOME,
the git global config and QS_HOME point to temp folders, so the tests never read or write
the user's real git config or ~/.config/code-quality-suite.
"""

import copy
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402
import qs  # noqa: E402

OLD_OT = r"^[0-9]+$"

# environment variables that point the tools at temp folders instead of the user's home
ISOLATED_KEYS = (
    "HOME",
    "USERPROFILE",
    "XDG_CONFIG_HOME",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_NOSYSTEM",
    "QS_HOME",
)


def isolated_env(test, **extra):
    """Build a process environment that never touches the user's git config or QS home.

    The temp folders are removed when the test ends. HOME and USERPROFILE point to an empty
    folder, GIT_CONFIG_GLOBAL to an empty file, GIT_CONFIG_NOSYSTEM is 1 and QS_HOME is a
    temp folder.

    Args:
        test: the unittest.TestCase that owns the temp folders (cleanup is registered on it).
        **extra: more variables to set (they win over the isolation values).

    Returns:
        dict[str, str]: a copy of os.environ with the isolation applied.
    """
    base = tempfile.mkdtemp(prefix="qs-test-")
    test.addCleanup(shutil.rmtree, base, True)
    home = os.path.join(base, "home")
    qs_home = os.path.join(base, "qs-home")
    os.makedirs(home)
    os.makedirs(qs_home)
    cfg = os.path.join(base, "gitconfig")
    with open(cfg, "w", encoding="utf-8"):
        pass
    env = dict(
        os.environ,
        HOME=home,
        USERPROFILE=home,
        XDG_CONFIG_HOME=os.path.join(base, "xdg"),
        GIT_CONFIG_GLOBAL=cfg,
        GIT_CONFIG_NOSYSTEM="1",
        QS_HOME=qs_home,
    )
    env.update(extra)
    return env


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
                [sys.executable, script, "migrate", path],
                check=True,
                capture_output=True,
                env=isolated_env(self),
            )
            with open(path, encoding="utf-8") as fh:
                got = json.load(fh)
            self.assertEqual(got["branches"]["levels"][1], policy.OT_RX)
            self.assertEqual(got["branches"]["model"], 5)


class MigrateFileTest(unittest.TestCase):
    """P5: the on-disk migration keeps line endings, uses a temp file and warns on skips."""

    def run_cli(self, path):
        """Run `policy.py migrate PATH` in an isolated environment.

        Args:
            path: the rules file.

        Returns:
            subprocess.CompletedProcess: the finished process (text output captured).
        """
        script = os.path.join(ROOT, "engine", "policy.py")
        return subprocess.run(
            [sys.executable, script, "migrate", path],
            check=True,
            capture_output=True,
            text=True,
            env=isolated_env(self),
        )

    def test_crlf_kept_no_temp_left(self):
        """A CRLF file stays CRLF and no temp file is left behind."""
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


class SafeWriteTest(unittest.TestCase):
    """Atomic write: unique temp names, cleanup on failure, permission bits kept."""

    NAME = ".quality-rules.json"

    def write_old(self, d):
        """Write a 4.x rules file in folder d.

        Args:
            d: the folder.

        Returns:
            str: the path of the rules file.
        """
        path = os.path.join(d, self.NAME)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(old_file(), fh)
        return path

    def read_text(self, path):
        """Read a file as text.

        Args:
            path: the file.

        Returns:
            str: its content (UTF-8).
        """
        with open(path, encoding="utf-8") as fh:
            return fh.read()

    def test_temp_removed_when_replace_fails(self):
        """When os.replace fails the temp file is removed; the error propagates, the file stays."""
        with tempfile.TemporaryDirectory() as d:
            path = self.write_old(d)
            before = self.read_text(path)
            failing = mock.patch.object(os, "replace", side_effect=OSError("replace failed"))
            with failing, self.assertRaises(OSError):
                policy._migrate_file(path)
            self.assertEqual(os.listdir(d), [self.NAME])
            self.assertEqual(self.read_text(path), before)

    def test_temp_removed_when_copymode_fails(self):
        """When the permission copy fails the temp file is deleted and the original stays."""
        with tempfile.TemporaryDirectory() as d:
            path = self.write_old(d)
            before = self.read_text(path)
            failing = mock.patch.object(shutil, "copymode", side_effect=OSError("copymode failed"))
            with failing, self.assertRaises(OSError):
                policy._migrate_file(path)
            self.assertEqual(os.listdir(d), [self.NAME])
            self.assertEqual(self.read_text(path), before)

    def test_stale_tmp_not_used(self):
        """A leftover `<name>.tmp` from an old run is not reused or clobbered."""
        with tempfile.TemporaryDirectory() as d:
            path = self.write_old(d)
            stale = path + ".tmp"
            with open(stale, "w", encoding="utf-8") as fh:
                fh.write("STALE")
            policy._migrate_file(path)
            self.assertEqual(self.read_text(stale), "STALE")
            self.assertEqual(json.loads(self.read_text(path))["branches"]["flow"], "merge")
            self.assertEqual(sorted(os.listdir(d)), sorted([self.NAME, self.NAME + ".tmp"]))

    def test_copymode_before_replace(self):
        """The permission bits are copied from the original before the temp file replaces it."""
        with tempfile.TemporaryDirectory() as d:
            path = self.write_old(d)
            events = []
            real_copymode, real_replace = shutil.copymode, os.replace

            def copymode(src, dst, **kw):
                """Record the call, then do the real copy.

                Args:
                    src: the original file.
                    dst: the temp file.
                    **kw: passed through.
                """
                events.append(("copymode", src))
                real_copymode(src, dst, **kw)

            def replace(src, dst):
                """Record the call, then do the real replace.

                Args:
                    src: the temp file.
                    dst: the original file.
                """
                events.append(("replace", dst))
                real_replace(src, dst)

            with (
                mock.patch.object(shutil, "copymode", side_effect=copymode),
                mock.patch.object(os, "replace", side_effect=replace),
            ):
                policy._migrate_file(path)
            self.assertEqual([e[0] for e in events], ["copymode", "replace"])
            self.assertEqual(events[0][1], path)
            self.assertEqual(events[1][1], path)

    @unittest.skipUnless(
        os.name == "posix", "POSIX permission bits; Windows only has the read-only flag"
    )
    def test_posix_mode_kept(self):
        """A rules file with mode 0640 is still 0640 after the migration."""
        with tempfile.TemporaryDirectory() as d:
            path = self.write_old(d)
            os.chmod(path, 0o640)
            policy._migrate_file(path)
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o640)
            self.assertEqual(json.loads(self.read_text(path))["branches"]["flow"], "merge")


class SyncRulesTest(unittest.TestCase):
    """P5: App.sync_rules migrates existing files and creates new ones with squash."""

    def make_app(self, root):
        """Build an App on a temp repo in persisting fix mode and load its rules.

        Args:
            root: the repository folder.

        Returns:
            qs.App: the engine instance with its rules loaded.
        """
        iso = isolated_env(self)
        keys = {"QS_ROOT": root, "QUALITY_MODE": "fix", "QS_PERSIST": "1", "QS_STATE": ""}
        keys.update({k: iso[k] for k in ISOLATED_KEYS})
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
        """Run install.sh on a repository without building the image, in an isolated environment.

        Args:
            repo: the repository folder.

        Returns:
            subprocess.CompletedProcess: the finished process (text output captured).
        """
        env = isolated_env(self, QS_SKIP_IMAGE="1", QS_REPO_FILES="0")
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
        subprocess.run(
            ["git", "init", "-q", d], check=True, env=isolated_env(self), capture_output=True
        )
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
