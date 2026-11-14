"""Regression tests: a formatter's check mode must agree with its fix mode.

The check formats copies of the files in a temp root and compares them. Tools whose
result depends on the repository layout (ruff's isort tells first-party imports by the
folders under `src`) must still see the real repository, through the {repo} token.

python3 -m unittest discover -s tests/unit -v
"""

import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import runner  # noqa: E402

import registry  # noqa: E402

# why: checked alone, mypy resolves 'registry' to the registry/ data folder, not to
# engine/registry.py (checked with engine files it resolves it right: hence unused-ignore)
REG = registry.Registry(  # type: ignore[attr-defined, unused-ignore]
    os.path.join(ROOT, "registry", "registry.json")
)

# why: a fake formatter whose output is the {repo} it was given, so check == fix only
# when the check passes the same repository as the fix
WRITE_REPO = "import sys\nfor p in sys.argv[2:]:\n    open(p, 'w').write(sys.argv[1])\n"


class FormatCheckAgreesWithFix(unittest.TestCase):
    """Checks that check mode resolves {repo} like fix mode does."""

    def _git_repo(self, d):
        """Create a git repository in d holding a file whose text is the repository path.

        Args:
            d: the folder to initialise.

        Returns:
            str: the repository-relative name of the file.
        """
        subprocess.run(["git", "init", "-q", d], check=True)
        with open(os.path.join(d, "a.py"), "w", encoding="utf-8") as fh:
            fh.write(d)
        return "a.py"

    def test_diff_check_sees_real_repo(self):
        """The temp-copy check passes the real repository as {repo}, so it agrees with fix."""
        tool = {
            "id": "fake-fmt",
            "role": "format",
            "cmd": {
                "fix": [sys.executable, "-c", WRITE_REPO, "{repo}", "{files}"],
                "check": "diff",
            },
        }
        with tempfile.TemporaryDirectory() as d:
            f = self._git_repo(d)
            ctx = runner.Ctx(d, "check", d, {}, set())
            res = runner.run_tool(tool, {}, None, ctx, [f], None, "python")
            self.assertEqual(res.status, {f: "SUCCESS"}, res.output)

    def test_ruff_format_src_is_the_repo_in_both_modes(self):
        """ruff-format's import sort gets the same src (the repository) in check and fix."""
        cfg = {("python", "ruff-format"): "/tmp/c/ruff.toml"}
        fix_ctx = runner.Ctx("/repo", "fix", "/tmp", cfg, set())
        chk_ctx = runner.Ctx("/tmp/chk-ruff-format-x", "fix", "/tmp", cfg, set())
        chk_ctx.repo = fix_ctx.repo
        tool = dict(REG.tools["ruff-format"], _lang="python")
        isort = runner._seqs(tool["cmd"]["fix"])[0]
        cmds = [runner.expand(isort, c, tool, ["a.py"], [], None) for c in (fix_ctx, chk_ctx)]
        self.assertEqual(cmds[0], cmds[1])
        self.assertIn("src = ['/repo']", cmds[0])
        self.assertIn("/tmp/c/ruff.toml", cmds[0])


if __name__ == "__main__":
    unittest.main()
