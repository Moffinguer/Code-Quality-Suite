"""Unit tests for the 5.x changelog: line format, OT, union and 4.x compatibility.

python3 -m unittest discover -s tests/unit -v
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import changelog  # noqa: E402

GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@example.com"]


def _run(cwd, *args):
    """Run git in cwd and return its stripped output.

    Args:
        cwd: the repository folder.
        *args: git arguments.

    Returns:
        str: stdout.
    """
    p = subprocess.run(GIT + list(args), cwd=cwd, capture_output=True, text=True, check=True)
    return p.stdout.strip()


class Lines(unittest.TestCase):
    """render() and validate() with the 5.x line format."""

    def item(self, ot, ref="421994d", group="Fixed", text="Tighten generated-file matching"):
        """One entry dict as entries() returns it."""
        return {"group": group, "breaking": False, "text": text, "ref": ref, "ot": ot, "order": 1}

    def test_line_with_ot_has_no_author_or_prefix(self):
        block = changelog.render("5.0.0", "2026-11-02", [self.item("git")])
        self.assertIn("### Fixed\n\n- Tighten generated-file matching (421994d; git)\n", block)
        self.assertNotIn("OT ", block)

    def test_line_without_ot(self):
        block = changelog.render("5.0.0", "2026-11-02", [self.item(None)])
        self.assertIn("- Tighten generated-file matching (421994d)\n", block)

    def test_link_ref_kept(self):
        ref = "[421994d](https://x/c/421994d)"
        block = changelog.render("5.0.0", "2026-11-02", [self.item("git", ref)])
        self.assertIn(f"({ref}; git)", block)

    def test_validate_accepts_new_and_old_lines(self):
        text = (
            "# Changelog\n\n## 5.0.0 - 2026-11-02\n\n### Added\n\n"
            "- New (421994d; git)\n- Newer (421994d)\n\n"
            "## 4.2.1 - 2026-11-01\n\n### Added\n\n"
            "- Old (3b6f5f0, OT 100; Fernando Mateos)\n- Older (38b35cb; Fernando Mateos)\n"
        )
        self.assertEqual(changelog.validate(text), ([], []))

    def test_validate_warns_without_references(self):
        base = "# Changelog\n\n## 5.0.0 - 2026-11-02\n\n### Added\n\n"
        errs, warns = changelog.validate(base + "- Bare\n")
        self.assertEqual(errs, [])
        self.assertIn("(abc1234; git)", warns[0])

    def test_repo_changelog_still_valid(self):
        with open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8") as fh:
            self.assertEqual(changelog.validate(fh.read()), ([], []))


class Union(unittest.TestCase):
    """union() merges release sections."""

    A = "## 5.0.0/a - 2026-11-01\n\n### Added\n\n- One (aaaaaaa; git)\n- Two (bbbbbbb; git)\n\n"
    B = (
        "### Fixed\n\n- Three (ccccccc; log)\n\n### Added\n\n- One (aaaaaaa; git)\n"
        "- **Breaking:** Four (ddddddd; log)\n\n### Changed\n\n- Five (eeeeeee; log)\n"
    )

    def test_order_dedup_breaking_first(self):
        block = changelog.union("5.0.0", "2026-11-02", [self.A, self.B])
        want = (
            "## 5.0.0 - 2026-11-02\n\n### Changed\n\n- Five (eeeeeee; log)\n\n"
            "### Added\n\n- **Breaking:** Four (ddddddd; log)\n- One (aaaaaaa; git)\n"
            "- Two (bbbbbbb; git)\n\n### Fixed\n\n- Three (ccccccc; log)\n\n"
        )
        self.assertEqual(block, want)
        self.assertEqual(changelog.validate("# Changelog\n\n" + block), ([], []))

    def test_linked_heading_and_empty(self):
        block = changelog.union("5.0.0", "2026-11-02", [""], "https://x/5.0.0")
        self.assertTrue(block.startswith("## [5.0.0] - 2026-11-02\n"))
        self.assertIn("Maintenance release", block)


class FromGit(unittest.TestCase):
    """entries() with and without ot."""

    def setUp(self):
        """Make a repo with a base commit and two squash commits."""
        self.d = tempfile.mkdtemp()
        _run(self.d, "init", "-q", "-b", "main")
        for name, msg in (("a", "chore: base"), ("b", "fix: tighten generated-file matching.")):
            with open(os.path.join(self.d, name), "w", encoding="utf-8") as fh:
                fh.write(name)
            _run(self.d, "add", name)
            _run(self.d, "commit", "-q", "-m", msg)
        self.base = _run(self.d, "rev-parse", "HEAD~1")
        self.tip = _run(self.d, "rev-parse", "HEAD")

    def tearDown(self):
        """Remove the repo."""
        shutil.rmtree(self.d, ignore_errors=True)

    def test_ot_forced(self):
        items, _ = changelog.entries(GIT + ["-C", self.d], self.tip, self.base, ot="git")
        self.assertEqual(changelog.without_ot(items), [])
        block = changelog.render("5.0.0", "2026-11-02", items)
        self.assertIn(f"- Tighten generated-file matching ({self.tip[:7]}; git)", block)
        self.assertIn("### Fixed", block)

    def test_no_ot_is_reported(self):
        items, _ = changelog.entries(GIT + ["-C", self.d], self.tip, self.base)
        self.assertEqual([c["hash"] for c in changelog.without_ot(items)], [self.tip])
        self.assertIsNone(items[0]["ot"])
        self.assertNotIn(";", changelog.render("5.0.0", "2026-11-02", items).split("- ")[1])


if __name__ == "__main__":
    unittest.main()
