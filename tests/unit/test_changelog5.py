"""Unit tests for the 5.x changelog: line format, OT, union and 4.x compatibility.

python3 -m unittest discover -s tests/unit -v
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

import changelog  # noqa: E402
import repofiles  # noqa: E402

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


class OldFormat(unittest.TestCase):
    """validate() warns about 4.x lines only in the new entry."""

    OLD = "- Old (3b6f5f0, OT 100; Fernando Mateos)\n- Older (38b35cb; Fernando Mateos)\n"

    def _text(self, top, low):
        return (
            f"# Changelog\n\n## 5.0.0 - 2026-11-02\n\n### Added\n\n{top}\n"
            f"## 4.2.1 - 2026-11-01\n\n### Added\n\n{low}"
        )

    def test_top_section_warns(self):
        errs, warns = changelog.validate(self._text(self.OLD, "- Ok (abc1234; git)\n"), "5.0.0")
        self.assertEqual(errs, [])
        self.assertEqual(len(warns), 2)
        self.assertIn("(abc1234; OT)", warns[0])
        self.assertIn("Old", warns[0] + self.OLD)

    def test_older_section_silent(self):
        text = self._text("- New (abc1234; git)\n", self.OLD)
        self.assertEqual(changelog.validate(text, "5.0.0"), ([], []))

    def test_new_form_silent(self):
        text = self._text("- New (abc1234, def5678; git)\n- Bare (abc1234)\n", "- X (abc1234)\n")
        self.assertEqual(changelog.validate(text, "5.0.0"), ([], []))

    def test_repo_4_2_1_changelog_silent(self):
        try:
            text = _run(ROOT, "show", "4.2.1:CHANGELOG.md")
        except (OSError, subprocess.CalledProcessError):
            self.skipTest("needs the git repository with tag 4.2.1 (not a git archive export)")
        self.assertEqual(changelog.validate(text), ([], []))


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

    def test_same_subject_and_ot_merge_hashes(self):
        a = "### Fixed\n\n- Fix x (aaa1111; git)\n- Fix x (bbb2222; log)\n- Fix y (ddd4444; git)\n"
        b = "### Fixed\n\n- Fix x (ccc3333; git)\n- Fix x (aaa1111; git)\n"
        block = changelog.union("5.0.0", "2026-11-02", [a, b])
        self.assertIn("- Fix x (aaa1111, ccc3333; git)\n- Fix x (bbb2222; log)\n", block)
        self.assertEqual(block.count("Fix x"), 2)
        self.assertEqual(block.count("aaa1111"), 1)

    def test_linked_hashes_merge(self):
        a = (
            "### Fixed\n\n- Fix x ([aaa1111](http://h/1); git)\n"
            "- Fix x ([bbb2222](http://h/2); log)\n"
        )
        b = (
            "### Fixed\n\n- Fix x ([ccc3333](http://h/3); git)\n"
            "- Fix x ([aaa1111](http://h/1); git)\n"
        )
        block = changelog.union("5.0.0", "2026-11-02", [a, b])
        self.assertIn("- Fix x ([aaa1111](http://h/1), [ccc3333](http://h/3); git)\n", block)
        self.assertIn("- Fix x ([bbb2222](http://h/2); log)\n", block)
        self.assertEqual(block.count("Fix x"), 2)

    def test_linked_and_plain_mix(self):
        a = "### Fixed\n\n- Fix x ([aaa1111](http://h/1); git)\n- Fix x (bbb2222; git)\n"
        block = changelog.union("5.0.0", "2026-11-02", [a])
        self.assertIn("- Fix x ([aaa1111](http://h/1), bbb2222; git)\n", block)

    def test_breaking_never_merges_with_plain(self):
        a = "### Fixed\n\n- Fix x (aaa1111; git)\n- **Breaking:** Fix x (bbb2222; git)\n"
        block = changelog.union("5.0.0", "2026-11-02", [a])
        self.assertIn("- **Breaking:** Fix x (bbb2222; git)\n- Fix x (aaa1111; git)\n", block)

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


class MigrationLine(unittest.TestCase):
    """The squash of '<v>/MIGRATION' is one Changed line whose OT is MIGRATION."""

    def setUp(self):
        """Make a repo: a base commit and two squashes with 'Refs:' lines of MIGRATION."""
        self.d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.d, True)
        _run(self.d, "init", "-q", "-b", "main")
        commits = (
            ("a", "chore: base"),
            ("b", "build: Move to Java 17\n\nRefs: 6.0.0/MIGRATION -> 6.0.0/ORIGINAL"),
            (
                "c",
                "build!: Raise the Java baseline\n\n"
                "Refs: 6.0.0/MIGRATION/ORIGINAL -> 6.0.0/ORIGINAL",
            ),
        )
        for name, msg in commits:
            with open(os.path.join(self.d, name), "w", encoding="utf-8") as fh:
                fh.write(name)
            _run(self.d, "add", name)
            _run(self.d, "commit", "-q", "-m", msg)
        self.base = _run(self.d, "rev-parse", "HEAD~2")
        self.tip = _run(self.d, "rev-parse", "HEAD")

    def test_ot_of_migration(self):
        self.assertEqual(changelog._ot_of("6.0.0/MIGRATION", changelog.policy.OT_RX), "MIGRATION")
        self.assertEqual(
            changelog._ot_of("6.0.0/MIGRATION/ORIGINAL", changelog.policy.OT_RX), "MIGRATION"
        )
        self.assertEqual(changelog._ot_of("6.0.0/ot1/a", changelog.policy.OT_RX), "ot1")
        self.assertIsNone(changelog._ot_of("6.0.0/ORIGINAL", changelog.policy.OT_RX))

    def test_lines_have_ot_migration_breaking_first(self):
        items, _ = changelog.entries(GIT + ["-C", self.d], self.tip, self.base)
        self.assertEqual(changelog.without_ot(items), [])
        block = changelog.render("6.0.0", "2026-11-16", items)
        lines = [ln for ln in block.splitlines() if ln.startswith("- ")]
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[0].startswith("- **Breaking:** Raise the Java baseline ("))
        self.assertTrue(lines[0].endswith("; MIGRATION)"))
        self.assertTrue(lines[1].endswith("; MIGRATION)"))


class GateLevel(unittest.TestCase):
    """repofiles.check() passes the version being written to the changelog validation."""

    def setUp(self):
        """Create a folder with a VERSION file at 4.2.1."""
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir, True)
        with open(os.path.join(self.dir, "VERSION"), "w", encoding="utf-8") as fh:
            fh.write("4.2.1\n")

    def _check(self, top):
        """Write a changelog whose top section is `top` and return check()'s warnings.

        Args:
            top: version of the topmost section.

        Returns:
            list[str]: the warnings of CHANGELOG.md.
        """
        text = (
            f"# Changelog\n\n## {top} - 2026-11-02\n\n### Added\n\n"
            "- Old (3b6f5f0, OT 100; Fernando Mateos)\n"
        )
        with open(os.path.join(self.dir, "CHANGELOG.md"), "w", encoding="utf-8") as fh:
            fh.write(text)
        errs, warns = repofiles.check(self.dir, "CHANGELOG.md")
        self.assertEqual(errs, [])
        return warns

    def _init_repo(self, *tags):
        """Make the folder a git repository with the given tags.

        Args:
            *tags: tag names to create.
        """
        _run(self.dir, "init", "-q")
        _run(self.dir, "add", "VERSION")
        _run(self.dir, "commit", "-q", "-m", "init")
        for t in tags:
            _run(self.dir, "tag", t)

    def test_untagged_top_section_warns(self):
        self._init_repo("4.2.1")
        warns = self._check("5.0.0")
        self.assertTrue(any("4.x format" in w for w in warns), warns)

    def test_untagged_top_equal_to_version_warns(self):
        self._init_repo()
        warns = self._check("4.2.1")
        self.assertTrue(any("4.x format" in w for w in warns), warns)

    def test_tagged_top_section_silent(self):
        self._init_repo("4.2.1")
        self.assertEqual(self._check("4.2.1"), [])

    def test_no_git_silent(self):
        self.assertFalse([w for w in self._check("5.0.0") if "4.x format" in w])

    def test_git_missing_silent(self):
        with mock.patch.object(repofiles.subprocess, "run", side_effect=OSError):
            self.assertFalse([w for w in self._check("5.0.0") if "4.x format" in w])


if __name__ == "__main__":
    unittest.main()
