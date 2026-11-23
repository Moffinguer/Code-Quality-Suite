"""Docs lint: Markdown that renders wrongly on GitHub, and broken relative links.

DL1: a line that starts with an HTML comment, closes it and has more text after it opens an HTML
block in CommonMark/GFM, so the text after the comment is shown raw and the paragraph above is cut.
Fenced code is ignored; the qs:version badge span is allowed when it holds HTML.
DL2: relative links and anchors of the root docs and docs/ resolve.
Run: python -m unittest discover -s tests/unit
"""

import os
import re
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
GLUED = re.compile(r"^\s*<!--.*?-->\s*\S")
BADGE_HTML = re.compile(r"^<!-- qs:version --><a [^\n]*</a><!-- /qs:version -->\s*$")
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
CODE_SPAN = re.compile(r"`[^`]*`")

sys.path.insert(0, os.path.join(ROOT, "engine"))
import changelog  # noqa: E402


def tracked_markdown():
    """Tracked Markdown files of the repository.

    Returns:
        list[str]: paths relative to the repository root, '/' separated.

    Raises:
        subprocess.CalledProcessError: when git cannot list the files.
    """
    out = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.md"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return [p for p in out.split("\0") if p and os.path.isfile(os.path.join(ROOT, p))]


def prose_lines(text):
    """Lines of a Markdown text that are outside fenced code blocks.

    Args:
        text: the Markdown source.

    Returns:
        list[tuple[int, str]]: (1-based line number, line) pairs.
    """
    out, fence = [], None
    for n, line in enumerate(text.split("\n"), 1):
        m = FENCE.match(line)
        if fence is None and m:
            fence = m.group(1)
        elif (
            fence is not None and m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence)
        ):
            fence = None
        elif fence is None:
            out.append((n, line))
    return out


def glued_comments(text):
    """DL1: lines that start with an HTML comment followed by text.

    Args:
        text: the Markdown source.

    Returns:
        list[int]: line numbers of the offending lines.
    """
    return [n for n, ln in prose_lines(text) if GLUED.match(ln) and not BADGE_HTML.match(ln)]


def slug(heading):
    """GitHub anchor of a heading.

    Args:
        heading: the heading text without the leading '#'.

    Returns:
        str: lowercase text, punctuation removed, spaces as '-'.
    """
    h = re.sub(r"[`*_]", "", heading.strip().lower())
    h = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", h)
    return re.sub(r"[^\w\- ]", "", h).replace(" ", "-")


def anchors(text):
    """Anchors a Markdown text offers (headings, duplicates numbered as GitHub does).

    Args:
        text: the Markdown source.

    Returns:
        set[str]: the anchor names.
    """
    seen, out = {}, set()
    for _, ln in prose_lines(text):
        m = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", ln)
        if m:
            s = slug(m.group(1))
            k = seen.get(s, 0)
            seen[s] = k + 1
            out.add(s if k == 0 else f"{s}-{k}")
    return out


def broken_links(path, text, read):
    """DL2: relative links of one file that do not resolve.

    Args:
        path: repository-relative path of the file ('/' separated).
        text: the Markdown source.
        read: function that returns the text of a repository-relative path or None when absent.

    Returns:
        list[str]: 'file:line: target' for each broken link.
    """
    bad = []
    base = os.path.dirname(path)
    for n, ln in prose_lines(text):
        for target in LINK.findall(CODE_SPAN.sub("", ln)):
            if re.match(r"^([a-z][a-z0-9+.-]*:|/|<)", target, re.I):
                continue
            file, _, frag = target.partition("#")
            dest = os.path.normpath(os.path.join(base, file)).replace("\\", "/") if file else path
            body = read(dest)
            if body is None or (
                frag and dest.endswith(".md") and frag.lower() not in anchors(body)
            ):
                bad.append(f"{path}:{n}: {target}")
    return bad


def read_repo(rel):
    """Text of a repository file.

    Args:
        rel: repository-relative path.

    Returns:
        str | None: the text; '' for a directory (it exists); None when missing.
    """
    full = os.path.join(ROOT, rel)
    if os.path.isdir(full):
        return ""
    if not os.path.isfile(full):
        return None
    if not rel.endswith(".md"):
        return ""
    with open(full, encoding="utf-8") as fh:
        return fh.read()


class DocsLintRules(unittest.TestCase):
    """The lint functions, on small examples."""

    def test_glued_comment_is_found(self):
        self.assertEqual(glued_comments("a\n<!-- x --> text\nb\n"), [2])
        self.assertEqual(glued_comments("<!-- only a comment -->\n- item <!-- x --> ok\n"), [])

    def test_fenced_code_is_skipped(self):
        src = "```md\n<!-- qs:version -->[![v](u)](c)<!-- /qs:version -->\n```\n<!-- a --> b\n"
        self.assertEqual(glued_comments(src), [4])
        self.assertEqual(glued_comments("~~~\n<!-- a --> b\n~~~\n"), [])

    def test_badge_html_is_allowed_markdown_is_not(self):
        ok = (
            '<!-- qs:version --><a href="CHANGELOG.md"><img alt="version 1"></a>'
            "<!-- /qs:version -->"
        )
        bad = "<!-- qs:version -->[![version 1](u)](CHANGELOG.md)<!-- /qs:version -->"
        self.assertEqual(glued_comments(ok), [])
        self.assertEqual(glued_comments(bad), [1])

    def test_badge_written_by_the_engine_passes(self):
        self.assertEqual(
            glued_comments("# T\n\n" + changelog.set_badge("# T\n", "1.2.3-rc.1") + "\n"), []
        )

    def test_links_and_anchors(self):
        files = {"a.md": "# Title\n\n## Two words\n", "d/b.md": "x"}
        read = files.get
        text = "[ok](a.md#two-words) [bad](a.md#nope) [gone](c.md) `[code](zz.md)` [web](https://x.y)\n"
        got = broken_links("t.md", text, read)
        self.assertEqual(got, ["t.md:1: a.md#nope", "t.md:1: c.md"])

    def test_slug(self):
        self.assertEqual(slug("Two `words`, here!"), "two-words-here")


class DocsLint(unittest.TestCase):
    """The tracked documents of this repository."""

    def test_dl1_no_glued_html_comments(self):
        bad = []
        for rel in tracked_markdown():
            with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
                bad += [f"{rel}:{n}" for n in glued_comments(fh.read())]
        self.assertEqual(bad, [], "a line starting with '<!--' must hold nothing after the comment")

    def test_dl2_relative_links_resolve(self):
        bad = []
        for rel in tracked_markdown():
            if "/" in rel and not rel.startswith("docs/"):
                continue
            with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
                bad += broken_links(rel, fh.read(), read_repo)
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
