"""Unit tests for the CI policy of 8.0.0: tracked rules file, drift tool, dependabot, baseline.

python3 -m unittest discover -s tests/unit -v
"""

import importlib.util
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

TOOL = os.path.join(ROOT, "tools", "ci-rules-drift.py")
RULES = os.path.join(ROOT, ".github", "quality-rules.json")
spec = importlib.util.spec_from_file_location("ci_rules_drift", TOOL)
assert spec is not None and spec.loader is not None
drift = importlib.util.module_from_spec(spec)
spec.loader.exec_module(drift)


def run_tool(data, **env):
    """Run the drift tool on a temporary rules file.

    Args:
        data: the JSON content (dict) or a raw string to write.
        **env: extra environment variables.

    Returns:
        subprocess.CompletedProcess: the finished process (text output).
    """
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "rules.json")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(data if isinstance(data, str) else json.dumps(data, indent=2))
        full = dict(os.environ, **env)
        if "QS_CI_FORMAT" not in env:
            full.pop("QS_CI_FORMAT", None)
        return subprocess.run(
            [sys.executable, TOOL, path], capture_output=True, text=True, env=full, check=False
        )


class TrackedRulesTest(unittest.TestCase):
    """CP1: the tracked .github/quality-rules.json."""

    def setUp(self):
        """Load the tracked rules file."""
        with open(RULES, encoding="utf-8") as fh:
            self.data = json.load(fh)

    def test_validates(self):
        """The file passes the policy validation the hooks use."""
        self.assertEqual(policy.validate(self.data), [])

    def test_project_values(self):
        """Flow squash, the bot branch allow rule and the delivery of this repository."""
        br = self.data["branches"]
        self.assertEqual(br["flow"], "squash")
        self.assertEqual(br["allow"], ["^dependabot/"])
        self.assertEqual(br["delivery"], "pr")

    def test_nothing_weaker_than_defaults(self):
        """No key weakens a default (G8 on the shipped file)."""
        self.assertEqual(drift.check_file(RULES), [])

    def test_no_personal_values(self):
        """Only the policy sections appear; nothing personal such as paths or tool settings."""
        self.assertLessEqual(
            set(self.data), {"branches", "commit", "encoding", "level", "data_class"}
        )


class DriftToolTest(unittest.TestCase):
    """CP2: tools/ci-rules-drift.py."""

    def test_equal_to_default_is_clean(self):
        """A file that restates defaults has no finding."""
        res = run_tool({"commit": {"subject_max": 50, "charset": "ascii"}, "level": "standard"})
        self.assertEqual((res.returncode, res.stdout), (0, ""))

    def test_stricter_is_clean(self):
        """Raising a level or lowering the subject limit is not a weakening."""
        res = run_tool({"level": "strict", "commit": {"subject_max": 40}})
        self.assertEqual(res.returncode, 0)

    def test_weaken_is_a_finding(self):
        """Lowering a level, disabling a check and relaxing a policy each give a finding."""
        data = {
            "level": "syntax",
            "encoding": {"enabled": False},
            "branches": {"enforce": "warn"},
            "commit": {"files": "off", "subject_max": 72, "conventional": False},
        }
        res = run_tool(data)
        self.assertEqual(res.returncode, 1)
        for key in (
            "level",
            "encoding.enabled",
            "branches.enforce",
            "commit.files",
            "commit.subject_max",
        ):
            self.assertIn(f"{key}:", res.stdout)
        self.assertIn("commit.conventional:", res.stdout)

    def test_weaken_with_why_is_clean(self):
        """A sibling `why` (or `<key>_why`) justifies the weakening."""
        data = {
            "commit": {"subject_max": 72, "why": "legacy tool limit"},
            "branches": {"enforce": "warn", "enforce_why": "x"},
        }
        self.assertEqual(run_tool(data).returncode, 0)

    def test_empty_why_does_not_count(self):
        """A blank `why` is no reason."""
        self.assertEqual(run_tool({"commit": {"subject_max": 72, "why": "  "}}).returncode, 1)

    def test_language_level_lowered(self):
        """A tool level lowered below the default is found at any depth."""
        data = {"languages": {"python": {"level": "off"}}}
        res = run_tool(data)
        self.assertEqual(res.returncode, 1)
        self.assertIn("languages.python.level", res.stdout)

    def test_github_annotations(self):
        """QS_CI_FORMAT=github prints ::error annotations with file and line."""
        res = run_tool('{\n  "commit": {\n    "files": "off"\n  }\n}\n', QS_CI_FORMAT="github")
        self.assertEqual(res.returncode, 1)
        self.assertRegex(res.stdout, r"^::error file=.*rules\.json,line=3::commit\.files: ")

    def test_unreadable_file(self):
        """A file that is not JSON exits 2."""
        self.assertEqual(run_tool("{not json").returncode, 2)


class DependabotTest(unittest.TestCase):
    """CP3: .github/dependabot.yml."""

    def setUp(self):
        """Read the file as text (the test needs no YAML parser)."""
        with open(os.path.join(ROOT, ".github", "dependabot.yml"), encoding="utf-8") as fh:
            self.text = fh.read()

    def test_settings(self):
        """Ecosystem github-actions, weekly, target develop."""
        self.assertIn("package-ecosystem: github-actions", self.text)
        self.assertIn("interval: weekly", self.text)
        self.assertIn("target-branch: develop", self.text)

    def test_commit_prefix_fits_policy(self):
        """The commit prefix is ASCII and a valid Conventional Commits type and scope."""
        match = re.search(r'prefix: "([^"]+)"', self.text)
        assert match is not None
        prefix = match.group(1)
        self.assertEqual(prefix, "ci(deps)")
        self.assertTrue(prefix.isascii())
        self.assertRegex(
            prefix + ": x",
            r"^(" + "|".join(policy.DEFAULTS["commit"]["types"]) + r")(\([^)]+\))?!?: .+",
        )
        self.assertLess(len(prefix) + 2, policy.DEFAULTS["commit"]["subject_max"] - 20)


class BaselineTest(unittest.TestCase):
    """CP4: .github/history-baseline.json."""

    def test_shape(self):
        """Every finding is a {sha, check} pair with a full sha and a known check."""
        with open(os.path.join(ROOT, ".github", "history-baseline.json"), encoding="utf-8") as fh:
            data = json.load(fh)
        self.assertTrue(data["findings"])
        for item in data["findings"]:
            self.assertEqual(set(item), {"sha", "check"})
            self.assertRegex(item["sha"], r"^[0-9a-f]{40}$")
            self.assertIn(
                item["check"], {"charset", "conventional", "subject_max", "files", "coauthor"}
            )


if __name__ == "__main__":
    unittest.main()
