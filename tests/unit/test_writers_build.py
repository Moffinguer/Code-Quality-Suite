"""Unit tests for writers.build fallbacks.

python3 -m unittest discover -s tests/unit -v
"""

import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import writers  # noqa: E402


class BuildFallbackTest(unittest.TestCase):
    """Checks writers.build for formats that wrap the base file."""

    def test_checkstyle_pmd_without_base_or_rules(self):
        """Without base and rules, checkstyle and pmd return the (absent) base text."""
        for fmt in ("checkstyle", "pmd"):
            self.assertIsNone(writers.build({"format": fmt}, None, {}))

    def test_checkstyle_pmd_with_base_and_no_rules(self):
        """Without rules, the base text is returned untouched."""
        for fmt in ("checkstyle", "pmd"):
            self.assertEqual(writers.build({"format": fmt}, "<x/>", {}), "<x/>")


if __name__ == "__main__":
    unittest.main()
