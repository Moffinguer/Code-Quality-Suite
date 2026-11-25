"""Unit tests for engine/textio.py."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "engine"))
import textio  # noqa: E402 - needs the engine folder on the path


class TextIo(unittest.TestCase):
    """read_text contracts: raise by default, default value on request."""

    def setUp(self):
        """Create a scratch folder with a CRLF text file and a non-UTF-8 file."""
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.txt = os.path.join(self.tmp.name, "a.txt")
        self.bad = os.path.join(self.tmp.name, "b.bin")
        with open(self.txt, "wb") as fh:
            fh.write(b"one\r\ntwo\r\n")
        with open(self.bad, "wb") as fh:
            fh.write(b"\xff\xfeabc")

    def test_newline_kept_or_translated(self):
        self.assertEqual(textio.read_text(self.txt, newline=""), "one\r\ntwo\r\n")
        self.assertEqual(textio.read_text(self.txt), "one\ntwo\n")

    def test_limit(self):
        self.assertEqual(textio.read_text(self.txt, limit=3), "one")

    def test_raises_without_default(self):
        with self.assertRaises(OSError):
            textio.read_text(os.path.join(self.tmp.name, "missing"))
        with self.assertRaises(UnicodeDecodeError):
            textio.read_text(self.bad)

    def test_default_and_replace(self):
        self.assertIsNone(textio.read_text(self.bad, default=None))
        self.assertEqual(textio.read_text(os.path.join(self.tmp.name, "x"), default=""), "")
        self.assertIn("abc", textio.read_text(self.bad, errors="replace"))

    def test_read_bytes(self):
        self.assertEqual(textio.read_bytes(self.txt), b"one\r\ntwo\r\n")


if __name__ == "__main__":
    unittest.main()
