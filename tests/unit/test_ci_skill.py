"""Unit tests for the ci-rules skill and its GitHub template (CS1-CS4).

python3 -m unittest discover -s tests/unit -v
"""

import json
import os
import re
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402

SKILL_DIR = os.path.join(ROOT, "ai-template", ".agents", "skills", "ci-rules")
SKILL = os.path.join(SKILL_DIR, "SKILL.md")
TEMPLATE = os.path.join(SKILL_DIR, "templates", "github.quality-rules.json")
MAX_LINES = 80


def _read(path):
    """Return the text of a UTF-8 file."""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _diff_paths(base, other, prefix=""):
    """List the dotted key paths where `other` differs from `base` (new or changed leaves)."""
    out = []
    for key, val in other.items():
        path = prefix + key
        if isinstance(val, dict) and isinstance(base.get(key), dict):
            out += _diff_paths(base[key], val, path + ".")
        elif base.get(key) != val:
            out.append(path)
    return out


def _has_path(tree, path):
    """True when the dotted `path` exists in the nested dict `tree`."""
    for part in path.split("."):
        if not isinstance(tree, dict) or part not in tree:
            return False
        tree = tree[part]
    return True


class CiSkillTest(unittest.TestCase):
    """The skill file and the GitHub template."""

    def test_frontmatter_and_size(self):
        """CS4: frontmatter with name and description, at most 80 lines."""
        text = _read(SKILL)
        match = re.match(r"---\nname: (\S+)\ndescription: (.+)\n---\n", text)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1), "ci-rules")
        self.assertLessEqual(len(text.splitlines()), MAX_LINES)
        for line in text.splitlines():
            self.assertTrue(len(line) <= 100 or line.startswith("description:"), line)
        self.assertTrue(text.isascii())

    def test_forge_table(self):
        """CS2: GitHub supported, GitLab and Azure DevOps later."""
        text = _read(SKILL)
        self.assertRegex(text, r"GitHub \| `\.github/quality-rules\.json` \| supported")
        self.assertRegex(text, r"GitLab \| `[^`]+` \| later")
        self.assertRegex(text, r"Azure DevOps \| `[^`]+` \| later")
        self.assertFalse(os.path.exists(os.path.join(ROOT, ".gitlab", "quality-rules.json")))

    def test_template_valid(self):
        """CS3: the template validates as shipped."""
        data = json.loads(_read(TEMPLATE))
        self.assertEqual(policy.validate(data), [])

    def test_template_differs_only_in_named_keys(self):
        """CS3: keys differing from DEFAULTS are named in the skill."""
        data = json.loads(_read(TEMPLATE))
        text = _read(SKILL)
        diff = _diff_paths(policy.DEFAULTS, data)
        self.assertTrue(diff)
        for path in diff:
            self.assertIn("`" + path + "`", text)

    def test_named_keys_exist(self):
        """CS4: every key path the skill names exists in DEFAULTS."""
        text = _read(SKILL)
        sections = "|".join(policy.SECTIONS)
        paths = set(re.findall(rf"`((?:{sections})\.[a-z_.]+)`", text))
        self.assertTrue(paths)
        for path in paths:
            self.assertTrue(_has_path(policy.DEFAULTS, path), path)


if __name__ == "__main__":
    unittest.main()
