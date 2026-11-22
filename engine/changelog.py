"""Release notes in Common Changelog format (https://common-changelog.org), README version badge,
CITATION.cff version.

  entries(git, tip, base)        changes of a release from the git history (Conventional Commits)
  render(version, date, ...)     the CHANGELOG.md entry of one release
  union(version, date, sections) one entry from several release sections
  merge(text, version, block)    CHANGELOG.md with that entry added or replaced, in semver order
  validate(text)                 (errors, warnings) against the Common Changelog rules
  set_badge / badge_version      the version badge between <!-- qs:version --> markers in README.md
  set_citation                   'version' and 'date-released' of CITATION.cff

Common Changelog in short: '# Changelog'; one '## [x.y.z] - YYYY-MM-DD' per release, newest
(by semver) first, no 'Unreleased'; an optional one-sentence notice; groups '### Changed',
'Added', 'Removed', 'Fixed' in that order, each a list of one-line, imperative changes with
references in parentheses; '**Breaking:**' first; link definitions at the end.
"""

import datetime
import html
import re
import subprocess

import policy
import semver

GROUPS = ("Changed", "Added", "Removed", "Fixed")
TYPE_GROUP = {
    "feat": "Added",
    "fix": "Fixed",
    "perf": "Changed",
    "refactor": "Changed",
    "build": "Changed",
    "revert": "Changed",
}
MIGRATION_OT = "MIGRATION"  # the 'OT' shown for the squash of the version's MIGRATION branch
OMIT_TYPES = {"docs", "test", "tests", "ci", "chore", "style"}
CONVENTIONAL = re.compile(
    r"^(?P<type>[a-z][a-z0-9-]*)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?: (?P<desc>.+)$"
)
BREAKING_FOOTER = re.compile(r"^BREAKING[ -]CHANGE: ", re.M)
RELEASE_SUBJECT = re.compile(r"^(chore\((release|version)\)|docs\((changelog|readme)\))[:!]")
HEADING = re.compile(r"^## (?:\[(?P<v1>[^\]]+)\]|(?P<v2>\S+)) - (?P<date>\S+)\s*$")
LINKDEF = re.compile(r"^\[(?P<label>[^\]]+)\]:\s*(?P<url>\S+)")
BADGE_START, BADGE_END = "<!-- qs:version -->", "<!-- /qs:version -->"
BADGE_RX = re.compile(re.escape(BADGE_START) + r"(.*?)" + re.escape(BADGE_END), re.S)


# ---------------------------------------------------------------- entries from git


def _git(gitcmd, *args):
    """Run git and return its standard output.

    Args:
        gitcmd: the git command line prefix (list of str).
        *args: git arguments.

    Returns:
        str: stdout decoded as UTF-8 (undecodable bytes replaced).

    Raises:
        RuntimeError: git exited with a non-zero status.
        subprocess.TimeoutExpired: git took longer than 120 seconds.
    """
    p = subprocess.run(gitcmd + list(args), capture_output=True, timeout=120, check=False)
    if p.returncode:
        raise RuntimeError(
            f"git {' '.join(args[:2])}: {p.stderr.decode('utf-8', 'replace').strip()}"
        )
    return p.stdout.decode("utf-8", "replace")


def _log(gitcmd, tip, excludes, first_parent=True, merges=None):
    """Commits reachable from tip and not from excludes, oldest first.

    Args:
        gitcmd: the git command line prefix (list of str).
        tip: the revision to start from.
        excludes: revisions whose history is left out.
        first_parent: follow only the first parent of merges.
        merges: True only merges, False no merges, None both.

    Returns:
        list[dict]: {hash, parents, author, subject, body} per commit.

    Raises:
        RuntimeError: git failed.
    """
    args = ["log", "--format=%H%x1f%P%x1f%an%x1f%B%x1e", "--reverse"]
    if first_parent:
        args.append("--first-parent")
    if merges is True:
        args.append("--merges")
    elif merges is False:
        args.append("--no-merges")
    args += [tip] + [f"^{e}" for e in excludes] + ["--"]
    out = []
    for raw in _git(gitcmd, *args).split("\x1e"):
        rec = raw.strip("\n")
        if not rec:
            continue
        h, parents, author, body = rec.split("\x1f", 3)
        out.append(
            {
                "hash": h,
                "parents": parents.split(),
                "author": author,
                "subject": body.split("\n", 1)[0].strip(),
                "body": body,
            }
        )
    return out


def _refs_src(body):
    """Source branch named by the 'Refs: <branch> -> ' trailer of a commit body.

    Args:
        body: the commit message body.

    Returns:
        str: the branch name, or None when the body has no such trailer.
    """
    m = re.search(r"^Refs: (\S+) -> ", body, re.M)
    return m.group(1) if m else None


def classify(subject, body=""):
    """(group or None when omitted, breaking, text) of a commit subject."""
    m = CONVENTIONAL.match(subject)
    if not m:
        return "Changed", False, subject[:1].upper() + subject[1:]
    typ, desc = m.group("type"), m.group("desc").strip().rstrip(".")
    breaking = bool(m.group("bang")) or bool(BREAKING_FOOTER.search(body or ""))
    text = desc[:1].upper() + desc[1:]
    if typ in OMIT_TYPES and not breaking:
        return None, False, text
    group = TYPE_GROUP.get(typ, "Changed")
    if re.match(r"(?i)(remove|drop|delete|retire)\b", desc) and group != "Fixed":
        group = "Removed"
    return group, breaking, text


def _commit_ref(h, commit_url):
    """Reference to a commit for a changelog entry.

    Args:
        h: the full commit hash.
        commit_url: URL template with '{commit}', or '' for a plain short hash.

    Returns:
        str: the 7-character hash, as a Markdown link when commit_url is set.
    """
    short = h[:7]
    return f"[{short}]({commit_url.replace('{commit}', h)})" if commit_url else short


def _ot_of(src, ot_rx):
    """OT (work order) of a branch name '<version>/<ot>/<detail>...'.

    Args:
        src: the branch name, or None.
        ot_rx: regular expression an OT must match (re.match).

    Returns:
        str | None: 'MIGRATION' for the special branch '<version>/MIGRATION' (or anything
        below it: its change belongs to no OT and is shown as MIGRATION); otherwise the
        second segment when the name has at least three segments and the segment matches
        ot_rx, else None.
    """
    parts = (src or "").split("/")
    if len(parts) > 1 and parts[1] == MIGRATION_OT:
        return MIGRATION_OT
    return parts[1] if len(parts) > 2 and re.match(ot_rx, parts[1]) else None


def _entry_ot(c, src, ot, ot_rx):
    """OT (work order) of one change.

    Args:
        c: the commit (dict from _log).
        src: the integrated branch name, or None to read it from the 'Refs:' line of c.
        ot: the OT forced by the caller, or '' to derive it from the branch name.
        ot_rx: regular expression an OT must match.

    Returns:
        str | None: the OT, or None when the change has none.
    """
    return ot or _ot_of(src or _refs_src(c["body"]), ot_rx)


def entries(gitcmd, tip, base, commit_url="", ot_rx=policy.OT_RX, *, ot=""):  # noqa: PLR0913
    """Changes between base and tip, one per integrated final branch (the 'git integra' merge
    subject) and one per direct commit.

    Args:
        gitcmd: the git command line prefix (list of str).
        tip: the newest revision of the release.
        base: the revision the release starts after ('' = the whole history).
        commit_url: URL template with '{commit}' for the commit references, or ''.
        ot_rx: regular expression of the OT, the second segment of the integrated branch;
            by default the policy default of branches.levels[1] (letters and digits).
        ot: OT given to every change (the tip is the ORIGINAL of that OT, so no 'Refs:'
            line is needed); '' derives it from the 'Refs:' line of each change.

    Returns:
        tuple: (entries, omitted subjects). An entry is {group, breaking, text, ref, ot,
        hash, subject, order}; ot is None when unknown. Authors and norm ids are not kept.

    Raises:
        RuntimeError: git failed.
    """
    out, omitted, seq = [], [], [0]

    def add(c, src=None):
        """Record one change in out, or in omitted when its subject is not classified.

        Skips release commits and duplicates of an entry already in out. Updates the
        closure lists out, omitted and seq; returns nothing.

        Args:
            c: the commit (dict with subject, body, parents).
            src: source branch of the change, or None.
        """
        if RELEASE_SUBJECT.match(c["subject"]):
            return
        group, breaking, text = classify(c["subject"], c["body"])
        if group is None:
            omitted.append(c["subject"])
            return
        found = _entry_ot(c, src, ot, ot_rx)
        seq[0] += 1
        # why: trees combined by 'git combinar' may bring the same integration twice
        for e in out:
            if (e["group"], e["text"], e["ot"]) == (group, text, found):
                return
        out.append(
            {
                "group": group,
                "breaking": breaking,
                "text": text,
                "ref": _commit_ref(c["hash"], commit_url),
                "ot": found,
                "hash": c["hash"],
                "subject": c["subject"],
                "order": seq[0],
            }
        )

    def walk(tip_, excludes):
        """Visit the commits from tip_ not reachable from excludes, calling add for each change.

        A merge that brings nothing new is skipped. A merge of an integrated branch is
        one change; a container merge or a non-conventional merge is descended into.
        Returns nothing; results go to the closure list out.

        Args:
            tip_: the revision to start from.
            excludes: revisions whose history is already counted (list of str).

        Raises:
            RuntimeError: git failed.
        """
        for c in _log(gitcmd, tip_, excludes):
            if len(c["parents"]) < 2:
                add(c)
                continue
            p1, p2 = c["parents"][0], c["parents"][1]
            ex = excludes + [p1]
            inner = _log(gitcmd, p2, ex, first_parent=False)
            if not inner:
                continue  # a sync merge: brings nothing new
            container = any(len(i["parents"]) > 1 and _refs_src(i["body"]) for i in inner)
            if container or not CONVENTIONAL.match(c["subject"]):
                walk(p2, ex)  # the parts are the changes
            else:
                add(c, _refs_src(c["body"]))

    walk(tip, [base] if base else [])
    return out, omitted


def without_ot(items):
    """The entries that have no OT, for the 'change without OT' warning.

    Args:
        items: entries from entries().

    Returns:
        list[dict]: the entries whose ot is empty (each has hash and subject).
    """
    return [e for e in items if not e.get("ot")]


# ---------------------------------------------------------------- render / merge


def render(version, date, items, tag_url="", notice=""):
    """The CHANGELOG.md block of one release (ends with a blank line).

    Args:
        version: the release version.
        date: the release date, YYYY-MM-DD.
        items: entries from entries(): {group, breaking, text, ref, ot, ...}.
        tag_url: URL of the release tag; when set the heading links the version.
        notice: optional one-sentence notice under the heading.

    Returns:
        str: the block; each change is '- Text (ref; OT)', or '- Text (ref)' without OT.
    """
    head = f"## [{version}] - {date}" if tag_url else f"## {version} - {date}"
    lines = [head, ""]
    if not items and not notice:
        notice = "_Maintenance release: no user-facing changes._"
    if notice:
        lines += [notice, ""]
    for g in GROUPS:
        its = [e for e in items if e["group"] == g]
        if not its:
            continue
        its.sort(key=lambda e: (not e["breaking"], -e["order"]))
        lines += [f"### {g}", ""]
        for e in its:
            ref = e["ref"] + (f"; {e['ot']}" if e.get("ot") else "")
            lines.append(f"- {'**Breaking:** ' if e['breaking'] else ''}{e['text']} ({ref})")
        lines.append("")
    return "\n".join(lines) + "\n"


# One commit reference: a bare hash or a linked '[hash](url)'.
_REF = r"(?:[0-9a-f]{4,40}|\[[0-9a-f]{4,40}\]\([^()\s]+\))"
_REFS = re.compile(
    r"^(?P<subj>- .*?) \((?P<hashes>" + _REF + r"(?:, " + _REF + r")*)(?P<ot>; [^;()]+)?\)$"
)


def _add_line(items, item):
    """Add one '- Subject (hash; OT)' line to items, merging same subject and OT.

    Args:
        items: the lines of one group so far; modified in place.
        item: the new line.

    Returns:
        None. An identical line is skipped; a line with the same subject (the breaking mark
        is part of it) and OT but other hashes extends the hash list of the existing line.
    """
    if item in items:
        return
    new = _REFS.match(item)
    if new:
        for i, old in enumerate(items):
            m = _REFS.match(old)
            if m and m["subj"] == new["subj"] and m["ot"] == new["ot"]:
                hs = m["hashes"].split(", ")
                hs += [h for h in new["hashes"].split(", ") if h not in hs]
                items[i] = f"{m['subj']} ({', '.join(hs)}{m['ot'] or ''})"
                return
    items.append(item)


def _seen_hashes(item, seen):
    """Tell whether every commit hash of a line was already listed, and record its hashes.

    Args:
        item: one '- Subject (hash; OT)' line.
        seen: set of the short hashes listed so far; modified in place.

    Returns:
        bool: True when the line has hashes and all of them are in seen (the same commit
        reached the union twice, so the line is dropped); False otherwise.
    """
    m = _REFS.match(item)
    if not m:
        return False
    hs = {h.strip("[]").split("]")[0][:7] for h in m["hashes"].split(", ")}
    if hs <= seen:
        return True
    seen |= hs
    return False


def union(version, date, sections, tag_url=""):
    """One release block from several release sections.

    Args:
        version: the version of the new block.
        date: its date, YYYY-MM-DD.
        sections: section texts (with or without their '## ' heading), in order.
        tag_url: URL of the release tag; when set the heading links the version.

    Returns:
        str: the block like render(); groups in Common Changelog order, items in section
        order, '**Breaking:**' items first, identical lines once,
        a line whose hashes were all listed before dropped.
        Lines of one group with
        the same subject and the same OT but different hashes become one line listing every
        hash in first-seen order, '- Fix x (aaa1111, ccc3333; git)' (linked hashes '[aaa1111](url)'
        merge the same way); a different OT, or a
        breaking against a non-breaking line, stays separate. With no change at all the
        maintenance notice is written.
    """
    found = {g: [] for g in GROUPS}
    seen = set()
    for sec in sections:
        group = None
        for ln in (sec or "").splitlines():
            if ln.startswith("### "):
                group = ln[4:].strip()
            elif group in found and re.match(r"^[-*] \S", ln):
                item = "- " + ln[2:].rstrip()
                if _seen_hashes(item, seen):
                    continue
                _add_line(found[group], item)
    head = f"## [{version}] - {date}" if tag_url else f"## {version} - {date}"
    lines = [head, ""]
    if not any(found.values()):
        lines += ["_Maintenance release: no user-facing changes._", ""]
    for g in GROUPS:
        if found[g]:
            its = sorted(found[g], key=lambda ln: not ln.startswith("- **Breaking:**"))
            lines += [f"### {g}", ""] + its + [""]
    return "\n".join(lines) + "\n"


# 4.x line tail: '(hash, OT 100; Author)' or '(hash; Two Word Author)'.
OLD_LINE = re.compile(r"\([^()]*(?:, OT \w+|; [^;()]*\s[^;()]*|; [^;()]*;[^()]*)\)\s*$")


def _split(text):
    """(header lines, [(version, lines)], [link definition lines]) of a CHANGELOG.md."""
    lines = text.splitlines()
    end = len(lines)
    while end > 0 and (not lines[end - 1].strip() or LINKDEF.match(lines[end - 1])):
        end -= 1
    links = [ln for ln in lines[end:] if ln.strip()]
    header, blocks, cur = [], [], None
    for ln in lines[:end]:
        if ln.startswith("## "):
            m = HEADING.match(ln)
            v = (m.group("v1") or m.group("v2")) if m else ln[3:].strip()
            cur = (v, [ln])
            blocks.append(cur)
        elif cur is None:
            header.append(ln)
        else:
            cur[1].append(ln)
    return header, blocks, links


def merge(text, version, block, tag_link=""):
    """CHANGELOG.md text with the block of 'version' added (or replaced), in semver order."""
    if not (text or "").strip():
        text = "# Changelog\n"
    header, blocks, links = _split(text)
    blocks = [b for b in blocks if b[0] != version]
    new = (version, block.rstrip("\n").split("\n") + [""])
    pos = len(blocks)
    for i, (v, _) in enumerate(blocks):
        if semver.key(v) is None or semver.key(v) < semver.key(version):
            pos = i
            break
    blocks.insert(pos, new)
    links = [ln for ln in links if LINKDEF.match(ln).group("label") != version]
    if tag_link:
        links.append(f"[{version}]: {tag_link}")
    vlinks = sorted(
        (ln for ln in links if semver.key(LINKDEF.match(ln).group("label"))),
        key=lambda ln: semver.key(LINKDEF.match(ln).group("label")),
        reverse=True,
    )
    other = [ln for ln in links if not semver.key(LINKDEF.match(ln).group("label"))]
    while header and not header[-1].strip():
        header.pop()
    out = header + [""]
    for _, bl in blocks:
        end = len(bl)
        while end and not bl[end - 1].strip():
            end -= 1
        out += bl[:end] + [""]
    if vlinks or other:
        out += vlinks + other + [""]
    return "\n".join(out).rstrip("\n") + "\n"


def versions(text):
    """Release versions of a CHANGELOG.md, in file order."""
    return [
        m.group("v1") or m.group("v2")
        for m in (HEADING.match(ln) for ln in (text or "").splitlines())
        if m
    ]


def section(text, version):
    """The block of one release (without its heading), or ''."""
    _, blocks, _ = _split(text or "")
    for v, bl in blocks:
        if v == version:
            return "\n".join(bl[1:]).strip("\n") + "\n"
    return ""


# ---------------------------------------------------------------- validation


def validate(text, new=None):  # noqa: C901, PLR0912, PLR0915 - one-pass line state machine
    """(errors, warnings): Common Changelog rules, with line numbers.

    Args:
        text: the CHANGELOG.md content.
        new: version of the entry being written (the topmost section, or the one a release
            writes); its lines get a warning when they use the 4.x format (an author after
            ';' or an 'OT <n>' prefix). None checks no section, so released history stays
            silent.

    Returns:
        tuple[list[str], list[str]]: the errors and the warnings.
    """
    errors, warnings = [], []
    lines = (text or "").splitlines()
    first = next(((i, ln) for i, ln in enumerate(lines, 1) if ln.strip()), (1, ""))
    if first[1].strip() != "# Changelog":
        errors.append(f"line {first[0]}: the first line must be '# Changelog'")
    defs = {m.group("label") for m in (LINKDEF.match(ln) for ln in lines) if m}
    seen, prev, rel = set(), None, None
    state = None  # None | head | notice | group
    group_order, group_items, intro_warned, notice_last = [], 0, False, 0

    def close_release(ln_no):
        """Check the release that ends before line ln_no, appending errors to the closure list.

        Reports a release with neither groups nor notice, and a last group left empty.
        Does nothing when no release is open. Returns nothing.

        Args:
            ln_no: line number used in the error messages.
        """
        if rel is None:
            return
        if not rel["groups"] and not rel["notice"]:
            errors.append(
                f"line {rel['line']}: release {rel['version']} has no changes and no notice"
            )
        if state == "group" and group_items == 0:
            errors.append(f"line {ln_no}: group '{group_order[-1]}' of {rel['version']} is empty")

    for n, ln in enumerate(lines, 1):
        s = ln.strip()
        if n == first[0] or not s or LINKDEF.match(ln):
            continue
        if ln.startswith("## "):
            close_release(n)
            if re.match(r"(?i)^## \[?unreleased\]?", ln):
                errors.append(
                    f"line {n}: no 'Unreleased' section in Common Changelog; "
                    "add the release when it is made"
                )
                rel, state = None, None
                continue
            m = HEADING.match(ln)
            if not m:
                errors.append(
                    f"line {n}: release heading must be '## [x.y.z] - YYYY-MM-DD' (got '{s}')"
                )
                rel, state = None, None
                continue
            v, linked, date = m.group("v1") or m.group("v2"), bool(m.group("v1")), m.group("date")
            if not semver.valid(v):
                errors.append(
                    f"line {n}: '{v}' is not a semantic version (https://semver.org; no 'v' prefix)"
                )
            try:
                datetime.date.fromisoformat(date)
                if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
                    raise ValueError
            except ValueError:
                errors.append(f"line {n}: date '{date}' must be YYYY-MM-DD")
            if v in seen:
                errors.append(f"line {n}: release {v} appears twice")
            if prev and semver.valid(v) and semver.valid(prev) and semver.compare(v, prev) > 0:
                errors.append(f"line {n}: {v} must come before {prev} (newest version first)")
            if linked and v not in defs:
                errors.append(f"line {n}: [{v}] has no link definition ('[{v}]: <url>' at the end)")
            seen.add(v)
            prev = v
            rel, state, group_order, group_items = (
                {"version": v, "line": n, "groups": [], "notice": False},
                "head",
                [],
                0,
            )
            continue
        if rel is None:
            if ln.startswith("### ") or ln.startswith("- "):
                errors.append(f"line {n}: content outside a release")
            elif not intro_warned:
                warnings.append(
                    f"line {n}: text before the first release (Common Changelog has none)"
                )
                intro_warned = True
            continue
        if ln.startswith("### "):
            g = s[4:].strip()
            if state == "group" and group_items == 0:
                errors.append(f"line {n}: group '{group_order[-1]}' of {rel['version']} is empty")
            if g not in GROUPS:
                hint = (
                    " (deprecations go under 'Changed')"
                    if g == "Deprecated"
                    else " (use 'Fixed' or 'Changed')"
                    if g == "Security"
                    else ""
                )
                errors.append(
                    f"line {n}: group '{g}' is not allowed: Changed, Added, Removed, Fixed{hint}"
                )
            elif g in group_order:
                errors.append(f"line {n}: group '{g}' appears twice in {rel['version']}")
            elif (
                group_order
                and g in GROUPS
                and any(GROUPS.index(g) < GROUPS.index(x) for x in group_order if x in GROUPS)
            ):
                errors.append(
                    f"line {n}: group '{g}' out of order (Changed, Added, Removed, Fixed)"
                )
            group_order.append(g)
            rel["groups"].append(g)
            state, group_items = "group", 0
            continue
        if state == "group":
            if re.match(r"^[-*] \S", ln):
                group_items += 1
                if not re.search(r" \(.+\)\s*$", s):
                    warnings.append(
                        f"line {n}: change without references; add the commit and the OT, "
                        "e.g. (abc1234; git)"
                    )
                elif rel["version"] == new and OLD_LINE.search(s):
                    warnings.append(
                        f"line {n}: 4.x format (author or 'OT <n>'); use the new form "
                        "'- Subject (abc1234; OT)'"
                    )
            elif re.match(r"^\s+\S", ln):
                errors.append(f"line {n}: a change must fit on one line")
            else:
                errors.append(
                    f"line {n}: only a list of changes is allowed inside '### {group_order[-1]}'"
                )
            continue
        if state == "head":
            rel["notice"] = True
            state, notice_last = "notice", n
            continue
        if state == "notice" and n == notice_last + 1:
            notice_last = n  # the same paragraph, wrapped
            continue
        errors.append(f"line {n}: only one notice is allowed before the groups of {rel['version']}")
    close_release(len(lines))
    return errors, warnings


# ---------------------------------------------------------------- README badge / CITATION.cff


def _shields(v):
    """Escape a text for a shields.io badge path segment.

    Args:
        v: the text.

    Returns:
        str: '-' and '_' doubled, spaces turned into '_'.
    """
    return v.replace("-", "--").replace("_", "__").replace(" ", "_")


def badge(version, link="CHANGELOG.md"):
    """HTML of the version badge, on one line.

    HTML (not Markdown) so GitHub renders it next to the qs:version markers: Markdown inside a
    line that starts with an HTML comment is shown as literal text.

    Args:
        version: the version shown.
        link: where the badge points to.

    Returns:
        str: the badge as an anchor holding an image.
    """
    img = f"https://img.shields.io/badge/version-{_shields(version)}-blue"
    return (
        f'<a href="{html.escape(link)}"><img alt="version {html.escape(version)}" '
        f'src="{html.escape(img)}"></a>'
    )


def badge_version(text):
    """Version shown by the README version badge.

    Args:
        text: README text; None or '' is accepted.

    Returns:
        str: the version, '' when a badge exists without a readable version, or None
        when there is no badge.
    """
    m = BADGE_RX.search(text or "")
    if not m:
        return None
    v = (
        re.search(r'alt="version ([^"]+)"', m.group(1))
        or re.search(r"!\[version ([^\]]+)\]", m.group(1))
        or re.search(r"version[ :]+(\S+)", m.group(1))
    )
    return html.unescape(v.group(1)) if v else ""


def set_badge(text, version):
    """README text with the version badge set (added under the first '# ' title when missing)."""
    mark = f"{BADGE_START}{badge(version)}{BADGE_END}"
    if BADGE_RX.search(text or ""):
        return BADGE_RX.sub(lambda m: mark, text, count=1)
    lines = (text or "").split("\n")
    pos = next((i + 1 for i, ln in enumerate(lines) if ln.startswith("# ")), 0)
    lines[pos:pos] = ["", mark] if pos else [mark, ""]
    return "\n".join(lines)


def set_citation(text, version, date):
    """CITATION.cff with 'version' and 'date-released' set (top-level keys, text edit)."""
    for key, val in (("version", f'"{version}"'), ("date-released", f"'{date}'")):
        rx = re.compile(rf"^{key}:.*$", re.M)
        if rx.search(text):
            text = rx.sub(f"{key}: {val}", text, count=1)
        else:
            text = text.rstrip("\n") + f"\n{key}: {val}\n"
    return text
