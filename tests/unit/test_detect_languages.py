"""Unit tests for registry.detect_languages (the skip of already-detected languages).

python3 -m unittest discover -s tests/unit -v
"""

import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "engine"))

import registry  # noqa: E402

REG = registry.Registry(  # type: ignore[attr-defined, unused-ignore]
    os.path.join(ROOT, "registry", "registry.json")
)


def full_scan(root, rels):
    """Reference result: classify every file and collect languages and subtypes.

    Args:
        root: the repository root.
        rels: repo-relative paths.

    Returns:
        dict: {language id: set of subtype ids}.
    """
    out = {}
    for c in registry.classify(REG, root, rels, [], {}):
        if not c.skip:
            out.setdefault(c.lang, set()).update(c.subtypes)
    return out


class DetectLanguages(unittest.TestCase):
    """The skip must not change the detected set."""

    def make(self, files):
        """Create files in a temporary repository.

        Args:
            files: {relative path: text}.

        Returns:
            str: the repository root (removed at cleanup).
        """
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        for rel, text in files.items():
            path = os.path.join(tmp.name, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="") as fh:
                fh.write(text)
        return tmp.name

    def test_same_as_full_scan_mixed_repo(self):
        """Many files of 3 languages (more than one chunk) give the full-scan result."""
        files = {}
        for i in range(registry.DETECT_CHUNK * 2 + 10):
            files[f"src/a{i}.java"] = "class A {}\n"
            files[f"py/m{i}.py"] = "x = 1\n"
        files["web/index.html"] = "<p>x</p>\n"
        root = self.make(files)
        rels = sorted(files)
        got = registry.detect_languages(REG, root, rels, [])
        self.assertEqual(got, full_scan(root, rels))
        self.assertTrue({"java", "python", "html"} <= set(got))

    def test_shebang_only_file_is_detected(self):
        """A file without extension is found through its shebang, never skipped."""
        files = {f"lib/f{i}.py": "x = 1\n" for i in range(5)}
        files["bin/tool"] = "#!/usr/bin/env python3\nprint(1)\n"
        files["bin/run"] = "#!/bin/sh\necho hi\n"
        root = self.make(files)
        rels = sorted(files)
        got = registry.detect_languages(REG, root, rels, [])
        self.assertEqual(got, full_scan(root, rels))
        self.assertIn("python", got)
        self.assertTrue({"sh", "bash"} & set(got))

    def test_ambiguous_extension_by_content(self):
        """The same ambiguous extension with different content keeps every language."""
        files = {
            "a/one.sh": "#!/bin/sh\necho 1\n",
            "a/two.sh": "#!/bin/bash\nset -euo pipefail\necho 2\n",
            "a/three.sh": "echo 3\n",
        }
        root = self.make(files)
        rels = sorted(files)
        self.assertEqual(registry.detect_languages(REG, root, rels, []), full_scan(root, rels))

    def test_excluded_and_binary_files_not_counted(self):
        """An excluded file or a binary one does not add its language."""
        root = self.make({"gen/x.java": "class X {}\n", "ok/y.py": "y = 2\n"})
        with open(os.path.join(root, "bin.rb"), "wb") as fh:
            fh.write(b"\x00\x01\x02\xff" * 64)
        rels = ["bin.rb", "gen/x.java", "ok/y.py"]
        got = registry.detect_languages(REG, root, rels, ["gen/*"])
        self.assertEqual(set(got), {"python"})

    def test_empty(self):
        """No files, no languages."""
        self.assertEqual(registry.detect_languages(REG, tempfile.gettempdir(), [], []), {})

    def test_subtypes_not_lost(self):
        """A language with subtypes is still classified until all its subtypes are seen."""
        sub = next(
            (lid, st["id"], st["match"])
            for lid, lang in REG.languages.items()
            for st in lang.get("subtypes", [])
            if st.get("match", {}).get("names") and len(lang["match"].get("ext", [])) == 1
        )
        lid, sid, match = sub
        ext = REG.languages[lid]["match"]["ext"][0]
        files = {f"p/f{i}{ext}": "{}\n" for i in range(5)}
        files[f"q/{match['names'][0]}"] = "{}\n"
        root = self.make(files)
        rels = sorted(files)
        self.assertEqual(registry.detect_languages(REG, root, rels, []), full_scan(root, rels))


if __name__ == "__main__":
    unittest.main()
