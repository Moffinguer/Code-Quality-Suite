"""Unit test: the CONTRIBUTING commit-type table matches the engine defaults.

python3 -m unittest discover -s tests/unit -v
"""

import os
import re
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import policy  # noqa: E402


def table_types(text):
    """Return the commit types listed in the 'Accepted types' table.

    Args:
        text: the content of CONTRIBUTING.md.

    Returns:
        List of type names, in table order (empty when the table is missing).
    """
    section = text.split("### Accepted types", 1)[-1].split("\n### ", 1)[0]
    return re.findall(r"^\| `([a-z][a-z0-9-]*)` \|", section, re.M)


class ContributingTableTest(unittest.TestCase):
    """CONTRIBUTING.md must document exactly the default commit types."""

    def test_table_matches_policy_defaults(self):
        """The table lists the same types, in the same order, as policy.DEFAULTS."""
        with open(os.path.join(ROOT, "CONTRIBUTING.md"), encoding="utf-8") as fh:
            documented = table_types(fh.read())
        self.assertEqual(documented, policy.DEFAULTS["commit"]["types"])

    def test_table_types_detects_a_missing_table(self):
        """A document without the table yields no types, so the comparison fails."""
        self.assertEqual(table_types("# nothing"), [])


if __name__ == "__main__":
    unittest.main()
