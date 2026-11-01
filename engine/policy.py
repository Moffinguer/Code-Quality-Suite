"""Repository policies kept in the rules file next to the tool rules.

  encoding  charset every text file must use (default UTF-8), BOM policy, overrides, mojibake
  commit    commit-message policy: allowed characters, Conventional Commits types, length
  branches  branch model: <version>/<ot>/<detail>... with '/', parent branches '<folder>/ORIGINAL'

The engine enforces `encoding`; `commit` and `branches` are enforced by the host hooks,
which read them from <state>/policy.env (written here; Git Bash has no JSON parser).
"""

import codecs
import contextlib
import copy
import fnmatch
import os
import re

# level 2 of a branch name: the OT (work order), ASCII letters and digits ('188858', 'ABC123');
# no '-' or '_', so it never collides with the leaf names of the branch model
OT_RX = r"^[A-Za-z0-9]+$"

DEFAULTS = {
    "encoding": {
        "enabled": True,
        "charset": "utf-8",
        "bom": "forbid",  # forbid | allow | require
        "by_language": {"powershell": {"bom": "allow"}},
        "by_glob": {},  # {"legacy/**/*.properties": "iso-8859-1"}
        "mojibake": "block",  # block | warn | off: text damaged by a wrong-encoding save
        "mojibake_ignore": [],  # globs never checked for mojibake (encoding test fixtures)
    },
    "commit": {
        "charset": "ascii",  # ascii | utf-8 | any
        "types": [
            "feat",
            "fix",
            "docs",
            "style",
            "refactor",
            "perf",
            "test",
            "build",
            "ci",
            "chore",
            "revert",
        ],
        "subject_max": 50,
        "conventional": True,
    },
    "branches": {
        "enforce": "block",  # block | warn | off
        "parent_leaf": "ORIGINAL",
        "mainline": "develop",
        "protected": ["main", "master", "develop"],
        # level 1: the version, Semantic Versioning without build metadata (https://semver.org);
        # level 2: the OT (OT_RX)
        "levels": [
            r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
            r"(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?$",
            OT_RX,
        ],
        "segment": r"^[A-Za-z0-9][A-Za-z0-9_-]*$",
        "allow": [],
        "leaf_merge": "merge",  # merge (--no-ff) | squash
        "require_children_merged": True,
        "tag": "{version}",
        "tag_level": 1,  # tag when a level-N ORIGINAL is integrated (0 = never)
        "release_leaf": "RELEASE",  # git release: '<version>/ORIGINAL' becomes '<version>/RELEASE'
        "archive_prefix": "unmerged",  # git release: branches not integrated -> 'unmerged/<name>'
        "version_file": "VERSION",  # committed on '<version>/ORIGINAL' when the tree is created
        "changelog_file": "CHANGELOG.md",  # git changelog --write: Common Changelog release notes
        "readme_file": "README.md",  # git release: version badge
        "pom_version": "update",  # update | snapshot | check | off: pom.xml follows the version
        "tag_url": "",  # changelog links: '' = from origin, '-' = none, or '...{tag}'
        "commit_url": "",  # changelog references: '' = from origin, '-' = none, '...{commit}'
    },
}
SECTIONS = tuple(DEFAULTS)
BOM_UTF8 = codecs.BOM_UTF8


def populate(data):
    """Add missing policy sections/keys with defaults. Never overwrites a value.

    Args:
        data: the parsed rules file (dict), changed in place.

    Returns:
        list[str]: the paths added ('section' or 'section.key').
    """
    added = []
    for sec, defaults in DEFAULTS.items():
        cur = data.get(sec)
        if not isinstance(cur, dict):
            if cur is None:
                data[sec] = copy.deepcopy(defaults)
                added.append(sec)
            continue
        for k, v in defaults.items():
            if k not in cur:
                cur[k] = copy.deepcopy(v)
                added.append(f"{sec}.{k}")
    return added


def get(data, sec):
    out = copy.deepcopy(DEFAULTS[sec])
    cur = (data or {}).get(sec)
    if isinstance(cur, dict):
        out.update(cur)
    return out


def _charset_ok(name):
    try:
        codecs.lookup(name)
        return True
    except LookupError:
        return name.lower() == "ascii"


def validate(data):
    """Check the policy sections of a rules file.

    Args:
        data: the parsed rules file (dict).

    Returns:
        list[str]: one message per problem, empty when the policy is valid.
    """
    errors = []
    for sec in SECTIONS:
        cur = data.get(sec)
        if cur is not None and not isinstance(cur, dict):
            errors.append(f"{sec}: must be an object")
    errors += _validate_encoding(get(data, "encoding"))
    errors += _validate_commit(get(data, "commit"))
    errors += _validate_branches(get(data, "branches"))
    return errors


def _validate_encoding(enc):
    """Check the 'encoding' section.

    Args:
        enc: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    if not _charset_ok(str(enc.get("charset"))):
        errors.append(f"encoding.charset: unknown charset '{enc.get('charset')}'")
    if enc.get("bom") not in ("forbid", "allow", "require"):
        errors.append("encoding.bom: must be forbid, allow or require")
    for key in ("by_language", "by_glob"):
        val = enc.get(key)
        if not isinstance(val, dict):
            errors.append(f"encoding.{key}: must be an object")
            continue
        for k, v in val.items():
            cs = (
                v
                if isinstance(v, str)
                else (v or {}).get("charset")
                if isinstance(v, dict)
                else None
            )
            if not isinstance(v, (str, dict)):
                errors.append(f"encoding.{key}.{k}: must be a charset name or {{charset, bom}}")
            elif cs and not _charset_ok(cs):
                errors.append(f"encoding.{key}.{k}: unknown charset '{cs}'")
    if enc.get("mojibake") not in ("block", "warn", "off"):
        errors.append("encoding.mojibake: must be block, warn or off")
    if not (
        isinstance(enc.get("mojibake_ignore"), list)
        and all(isinstance(x, str) for x in enc["mojibake_ignore"])
    ):
        errors.append("encoding.mojibake_ignore: must be a list of globs")
    return errors


def _validate_commit(com):
    """Check the 'commit' section.

    Args:
        com: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    if com.get("charset") not in ("ascii", "utf-8", "any"):
        errors.append("commit.charset: must be ascii, utf-8 or any")
    if not (
        isinstance(com.get("types"), list)
        and all(isinstance(t, str) and re.fullmatch(r"[a-z][a-z0-9-]*", t) for t in com["types"])
    ):
        errors.append("commit.types: must be a list of lowercase words")
    if not isinstance(com.get("subject_max"), int) or com["subject_max"] < 10:
        errors.append("commit.subject_max: must be an integer >= 10")
    return errors


def _validate_branches(br):
    """Check the 'branches' section.

    Args:
        br: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    if br.get("enforce") not in ("block", "warn", "off"):
        errors.append("branches.enforce: must be block, warn or off")
    if br.get("leaf_merge") not in ("merge", "squash"):
        errors.append("branches.leaf_merge: must be merge or squash")
    for key in ("parent_leaf", "release_leaf", "archive_prefix"):
        if not re.fullmatch(r"[A-Za-z0-9_-]+", str(br.get(key, ""))):
            errors.append(f"branches.{key}: letters, digits, '-' or '_' only")
    if len({br.get("parent_leaf"), br.get("release_leaf")}) < 2:
        errors.append("branches.release_leaf: must differ from parent_leaf")
    if br.get("pom_version") not in ("update", "snapshot", "check", "off"):
        errors.append("branches.pom_version: must be update, snapshot, check or off")
    errors += _validate_branch_paths(br)
    errors += _validate_branch_patterns(br)
    if not isinstance(br.get("tag_level"), int) or br["tag_level"] < 0:
        errors.append("branches.tag_level: must be an integer >= 0")
    return errors


def _validate_branch_paths(br):
    """Check the URL templates and file paths of the 'branches' section.

    Args:
        br: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    for key, ph in (("tag_url", "{tag}"), ("commit_url", "{commit}")):
        v = br.get(key)
        if not isinstance(v, str) or (v not in ("", "-") and ph not in v):
            errors.append(f"branches.{key}: '' (from origin), '-' (none) or a URL with {ph}")
    for key in ("version_file", "changelog_file", "readme_file"):
        v = br.get(key)
        if not isinstance(v, str) or v.startswith(("/", "-")) or ".." in v.split("/") or "\\" in v:
            errors.append(f"branches.{key}: a path inside the repository ('' = off)")
    return errors


def _validate_branch_patterns(br):
    """Check the name lists and regular expressions of the 'branches' section.

    Args:
        br: the section merged with its defaults (dict).

    Returns:
        list[str]: one message per problem.
    """
    errors = []
    for key in ("levels", "allow", "protected"):
        if not (isinstance(br.get(key), list) and all(isinstance(x, str) for x in br[key])):
            errors.append(f"branches.{key}: must be a list of strings")
    patterns = list(br.get("levels") or []) + list(br.get("allow") or [])
    for rx in [*patterns, br.get("segment", "")]:
        try:
            re.compile(rx)
        except (re.error, TypeError):
            errors.append(f"branches: invalid regular expression {rx!r}")
    return errors


# ---------------------------------------------------------------- host export


def _sh(v):
    return "'" + str(v).replace("'", "'\\''") + "'"


def shell_env(data):
    """KEY='value' lines for the host hooks (commit-msg, pre-push, git aliases)."""
    com, br = get(data, "commit"), get(data, "branches")
    lines = {
        "QS_COMMIT_CHARSET": com["charset"],
        "QS_COMMIT_TYPES": "|".join(com["types"]),
        "QS_COMMIT_SUBJECT_MAX": com["subject_max"],
        "QS_COMMIT_CONVENTIONAL": "1" if com.get("conventional", True) else "0",
        "QS_BR_ENFORCE": br["enforce"],
        "QS_BR_LEAF": br["parent_leaf"],
        "QS_BR_MAINLINE": br["mainline"],
        "QS_BR_PROTECTED": " ".join(br["protected"]),
        "QS_BR_SEGMENT": br["segment"],
        "QS_BR_LEAF_MERGE": br["leaf_merge"],
        "QS_BR_REQUIRE_CHILDREN": "1" if br.get("require_children_merged", True) else "0",
        "QS_BR_TAG": br["tag"],
        "QS_BR_TAG_LEVEL": br["tag_level"],
        "QS_BR_RELEASE_LEAF": br["release_leaf"],
        "QS_BR_ARCHIVE": br["archive_prefix"],
        "QS_BR_VERSION_FILE": br["version_file"],
        "QS_BR_CHANGELOG": br["changelog_file"],
        "QS_BR_README": br["readme_file"],
        "QS_BR_POM": br["pom_version"],
        "QS_BR_TAG_URL": br["tag_url"],
        "QS_BR_COMMIT_URL": br["commit_url"],
        "QS_BR_LEVELS": len(br["levels"]),
        "QS_BR_ALLOW": len(br["allow"]),
    }
    for i, rx in enumerate(br["levels"], 1):
        lines[f"QS_BR_LEVEL_{i}"] = rx
    for i, rx in enumerate(br["allow"], 1):
        lines[f"QS_BR_ALLOW_{i}"] = rx
    return "".join(f"{k}={_sh(v)}\n" for k, v in lines.items())


# ---------------------------------------------------------------- encoding


def _norm(cs):
    cs = (cs or "utf-8").lower().replace("_", "-")
    return {
        "utf8": "utf-8",
        "latin1": "iso-8859-1",
        "latin-1": "iso-8859-1",
        "cp1252": "windows-1252",
        "us-ascii": "ascii",
    }.get(cs, cs)


def expected(enc, rel, lang_id):
    """(charset, bom) expected for a file: by_glob (first match) > by_language > global."""
    cs, bom = enc.get("charset", "utf-8"), enc.get("bom", "forbid")
    lv = (enc.get("by_language") or {}).get(lang_id or "")
    if isinstance(lv, str):
        cs = lv
    elif isinstance(lv, dict):
        cs, bom = lv.get("charset", cs), lv.get("bom", bom)
    for pat, gv in (enc.get("by_glob") or {}).items():
        if glob_match(rel, pat):
            if isinstance(gv, str):
                cs = gv
            elif isinstance(gv, dict):
                cs, bom = gv.get("charset", cs), gv.get("bom", bom)
            break
    return _norm(cs), bom


def glob_match(rel, pat):
    """fnmatch for repository paths: 'x/**/y' also matches 'x/y'; a bare name matches any folder."""
    return (
        fnmatch.fnmatch(rel, pat)
        or ("/" not in pat and fnmatch.fnmatch(os.path.basename(rel), pat))
        or (pat.startswith("**/") and fnmatch.fnmatch(rel, pat[3:]))
        or ("/**/" in pat and fnmatch.fnmatch(rel, pat.replace("/**/", "/")))
    )


def _line_col(raw, pos):
    line = raw.count(b"\n", 0, pos) + 1
    col = pos - (raw.rfind(b"\n", 0, pos) + 1) + 1
    return line, col


def _guess(raw):
    """Best-effort name of the encoding a non-UTF-8 file probably uses."""
    if raw.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)) or raw[1:200:2].count(0) > 20:
        return "UTF-16"
    if any(0x80 <= b <= 0x9F for b in raw):
        return "Windows-1252"
    return "ISO-8859-1 / Windows-1252"


def check(raw, cs, bom):
    """Problems (list of str) for file bytes against the expected charset and BOM policy.

    why: a file whose encoding changed (UTF-8 saved as ANSI, or converted the other way)
    silently corrupts accents for every other developer and tool, so it must not land.

    Args:
        raw: the file bytes.
        cs: the expected charset, normalized (see expected()).
        bom: the BOM policy: forbid, allow or require.

    Returns:
        list[str]: at most one problem; empty when the bytes match.
    """
    if cs in ("utf-16", "utf-16-le", "utf-16-be", "utf-32"):
        return _check_wide(raw, cs)
    if raw.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE, codecs.BOM_UTF32_LE)):
        return [f"file is UTF-16/32 but must be {cs.upper()}; re-save it as {cs.upper()}"]
    if cs == "utf-8":
        return _check_utf8(raw, bom)
    if raw.startswith(BOM_UTF8):
        return [f"starts with a UTF-8 BOM but must be {cs.upper()}"]
    if cs == "ascii":
        return _check_ascii(raw)
    return _check_legacy(raw, cs)


def _check_wide(raw, cs):
    """check() for UTF-16 and UTF-32 charsets.

    Args:
        raw: the file bytes.
        cs: the expected charset.

    Returns:
        list[str]: the decoding problem, or empty.
    """
    try:
        raw.decode(cs)
        return []
    except UnicodeDecodeError as e:
        return [f"not valid {cs.upper()} at byte {e.start}"]


def _check_utf8(raw, bom):
    """check() for UTF-8: valid bytes and the BOM policy.

    Args:
        raw: the file bytes.
        bom: the BOM policy: forbid, allow or require.

    Returns:
        list[str]: the problem found, or empty.
    """
    has_bom = raw.startswith(BOM_UTF8)
    body = raw[3:] if has_bom else raw
    try:
        body.decode("utf-8")
    except UnicodeDecodeError as e:
        return _utf8_damage(body, e)
    if has_bom and bom == "forbid":
        return [
            "starts with a UTF-8 BOM (EF BB BF), which is forbidden here; "
            "save it as 'UTF-8' without BOM"
        ]
    if not has_bom and bom == "require" and any(b >= 0x80 for b in body):
        return ["must start with a UTF-8 BOM (encoding.bom = require)"]
    return []


def _utf8_damage(body, e):
    """Explain why bytes that must be UTF-8 do not decode.

    Args:
        body: the file bytes without BOM.
        e: the UnicodeDecodeError of the UTF-8 decode.

    Returns:
        list[str]: one message with position, likely cause, sample words and the repair.
    """
    if _guess(body) == "UTF-16":
        return ["file looks like UTF-16 without a BOM; save it as 'UTF-8'"]
    line, col = _line_col(body, e.start)
    _, spots, utf8_chars = decode_mixed(body)
    what = (
        f"mixed encodings: {len(spots)} character(s) in Windows-1252 next to "
        f"{utf8_chars} in UTF-8 "
        f"(the editor opened it with the wrong encoding and saved new text in Windows-1252)"
        if utf8_chars
        else f"saved as Windows-1252/ISO-8859-1 (ANSI) instead of UTF-8: {len(spots)} character(s)"
    )
    where = "; ".join(f'line {ln}: "{_show(w)}"' for ln, w in _spot_words(body, spots)[:3])
    more = f" (+{len(spots) - 3} more)" if len(spots) > 3 else ""
    return [
        f"not valid UTF-8 at line {line}, column {col} (byte 0x{body[e.start]:02X}): "
        f"{what}; {where}{more}. Repair: git encoding --fix FILE"
    ]


def _check_ascii(raw):
    """check() for ASCII: the first byte >= 0x80.

    Args:
        raw: the file bytes.

    Returns:
        list[str]: the first non-ASCII byte with its position, or empty.
    """
    for i, b in enumerate(raw):
        if b >= 0x80:
            line, col = _line_col(raw, i)
            return [f"non-ASCII byte 0x{b:02X} at line {line}, column {col} (encoding is ascii)"]
    return []


def _check_legacy(raw, cs):
    """check() for single-byte charsets (ISO-8859-1, Windows-1252, ...).

    Args:
        raw: the file bytes (no BOM).
        cs: the expected charset.

    Returns:
        list[str]: an undecodable byte, or a file that looks converted to UTF-8, or empty.
    """
    try:
        raw.decode(cs)
    except (UnicodeDecodeError, LookupError) as e:
        pos = getattr(e, "start", 0)
        line, col = _line_col(raw, pos)
        return [f"byte 0x{raw[pos]:02X} at line {line}, column {col} is not valid {cs.upper()}"]
    if any(b >= 0x80 for b in raw):
        try:
            text = raw.decode("utf-8")
            if any(ord(ch) >= 0x80 for ch in text):
                return [
                    f"looks like UTF-8 but must be {cs.upper()} (the file was converted?); "
                    f"convert it back: iconv -f UTF-8 -t {cs.upper()} FILE > tmp && mv tmp FILE"
                ]
        except UnicodeDecodeError:
            pass
    return []


def needs_protection(raw, cs):
    """True when tools that assume UTF-8 could corrupt this file.

    Args:
        raw: the file bytes.
        cs: the expected charset.

    Returns:
        bool: the charset is neither UTF-8 nor ASCII and the file has non-ASCII bytes.
    """
    return cs not in ("utf-8", "ascii") and any(b >= 0x80 for b in raw)


# ---------------------------------------------------------------- mojibake
#
# Mojibake is text whose bytes were read with one encoding and written back with another. In a
# UTF-8 file it shows up in three ways, all produced by an editor that guessed the wrong encoding
# (VS Code with files.autoGuessEncoding, or files.encoding set to windows1252):
#   double encoding   UTF-8 bytes read as Windows-1252 and saved as UTF-8: "o" acute (C3 B3)
#                     becomes the two characters U+00C3 U+00B3
#   replacement char  a Windows-1252 file read as UTF-8 and saved: each accent becomes U+FFFD
#   question marks    saved in a charset without those letters: each accent becomes "?"
# The first is found in the text alone; the last two need the previous version of the file.


def _cp1252_bytes():
    """Map the characters Windows-1252 shows for bytes 0x80-0xFF back to the bytes.

    ISO-8859-1 fills the holes of Windows-1252.

    Returns:
        dict[str, int]: {character: byte}.
    """
    out = {}
    for b in range(0x80, 0x100):
        out[chr(b)] = b
        with contextlib.suppress(UnicodeDecodeError):
            out[bytes([b]).decode("cp1252")] = b
    return out


BYTE_OF = _cp1252_bytes()


def _cls(lo, hi):
    return "".join(re.escape(ch) for ch, b in sorted(BYTE_OF.items()) if lo <= b <= hi)


_CONT = "[" + _cls(0x80, 0xBF) + "]"
# one UTF-8 multi-byte sequence as it looks after a Windows-1252 decode: lead byte + continuations
MOJIBAKE_RX = re.compile(
    f"[{_cls(0xC2, 0xDF)}]{_CONT}|[{_cls(0xE0, 0xEF)}]{_CONT}{{2}}|[{_cls(0xF0, 0xF4)}]{_CONT}{{3}}"
)
ALLOW_MARK = "qs-allow-mojibake"  # a line containing this text is never reported;
# '...-begin' / '...-end' lines exempt everything between them (documentation examples)


# why: a 2-byte sequence can also be a legitimate pair of Latin-1 characters (a code page table
# in a minified script); only Latin letters and symbols count alone, other scripts (Greek,
# Cyrillic, Hebrew, Arabic) only as two or more letters in a row, like a real word
_LATIN = (0x80, 0x24F)
_SCRIPTS_2 = ((0x370, 0x3FF), (0x400, 0x4FF), (0x5D0, 0x5EA), (0x600, 0x6FF))


def _undo_once(text):
    """Text with every double-encoded sequence decoded back (one level). Returns (text, count)."""
    found = []
    for m in MOJIBAKE_RX.finditer(text):
        try:
            ch = bytes(BYTE_OF[c] for c in m.group()).decode("utf-8")
        except UnicodeDecodeError:
            continue  # why: not a real UTF-8 sequence (overlong, surrogate): leave it
        o = ord(ch)
        kind = (
            "ok"
            if (o >= 0x800 or _LATIN[0] <= o <= _LATIN[1])
            else "word"
            if any(a <= o <= b for a, b in _SCRIPTS_2)
            else None
        )
        if kind:
            found.append([m.start(), m.end(), ch, kind])
    keep = []
    for i, f in enumerate(found):
        if f[3] == "word":
            near = (i > 0 and found[i - 1][1] == f[0] and found[i - 1][3] == "word") or (
                i + 1 < len(found) and found[i + 1][0] == f[1] and found[i + 1][3] == "word"
            )
            if not near:
                continue
        keep.append(f)
    if not keep:
        return text, 0
    out, pos = [], 0
    for a, b, ch, _ in keep:
        out.append(text[pos:a])
        out.append(ch)
        pos = b
    out.append(text[pos:])
    return "".join(out), len(keep)


def undo_double_encoding(text):
    """Repairs text encoded twice or three times. Returns (text, sequences repaired)."""
    total = 0
    for _ in range(3):
        text, n = _undo_once(text)
        total += n
        if not n:
            break
    return text, total


def _show(s):
    """Snippet for a console line: control characters escaped, long text cut."""
    s = "".join(
        ch if (ch >= " " and not "\x7f" <= ch <= "\x9f") else f"\\x{ord(ch):02x}" for ch in s
    )
    return s if len(s) <= 60 else s[:57] + "..."


def _word_at(line, start, end):
    """The word around line[start:end] (up to the nearest blank or quote)."""
    stop = " \t\"'<>()[]{}=,;"
    a, b = start, end
    while a > 0 and line[a - 1] not in stop and start - a < 30:
        a -= 1
    while b < len(line) and line[b] not in stop and b - end < 30:
        b += 1
    return line[a:b]


def decode_mixed(body):
    """Decodes bytes that are UTF-8 except for some Windows-1252 bytes (an editor that saved new
    text in ANSI inside a UTF-8 file). Returns (text, byte offsets decoded as Windows-1252,
    number of genuine multi-byte UTF-8 characters)."""
    spots = []

    def handler(e):
        b = e.object[e.start]
        spots.append(e.start)
        try:
            return bytes([b]).decode("cp1252"), e.start + 1
        except UnicodeDecodeError:
            return chr(b), e.start + 1

    name = f"qs-cp1252-{id(spots)}"
    codecs.register_error(name, handler)
    text = body.decode("utf-8", errors=name)
    utf8_chars = sum(1 for ch in text if ord(ch) >= 0x80) - len(spots)
    return text, spots, utf8_chars


def _spot_words(body, spots):
    """[(line, word)] for byte offsets of a non-UTF-8 file, the word decoded as Windows-1252."""
    out, seen = [], set()
    for pos in spots:
        line, _ = _line_col(body, pos)
        if line in seen:
            continue
        seen.add(line)
        a = body.rfind(b"\n", 0, pos) + 1
        z = body.find(b"\n", pos)
        raw_line = body[a : z if z >= 0 else len(body)]
        text = raw_line.decode("cp1252", errors="replace")
        out.append((line, _word_at(text, pos - a, pos - a + 1)))
    return out


def _lossy(line):
    """The ways an editor writes a line it could not encode.

    Args:
        line: a line of the previous version.

    Returns:
        tuple[str, ...]: the line with '?' and with U+FFFD for each non-ASCII character;
        empty when the line is ASCII.
    """
    if all(ord(c) < 0x80 for c in line):
        return ()
    return (
        "".join(c if ord(c) < 0x80 else "?" for c in line),
        "".join(c if ord(c) < 0x80 else "\ufffd" for c in line),
    )


def decode_any(raw):
    """Text of a previous version whatever its encoding (UTF-8, else Windows-1252)."""
    if raw is None:
        return None
    body = raw[3:] if raw.startswith(BOM_UTF8) else raw
    try:
        return body.decode("utf-8")
    except UnicodeDecodeError:
        return decode_mixed(body)[0]


def mojibake(text, old_text=None):
    """(errors, warnings) for UTF-8 text that holds encoding damage. Findings on lines that are
    identical in old_text (the previous version) are only warnings: they were already there.

    Each finding is a dict: line, col, kind (double|replacement|lost), found, fixed (or None).
    """
    errors, warnings = [], []
    old_lines = set(old_text.splitlines()) if old_text else set()
    lossy = {}
    if old_text:
        for ol in old_text.splitlines():
            for v in _lossy(ol):
                lossy.setdefault(v, ol)
    allowed = False
    for n, line in enumerate(text.splitlines(), 1):
        if ALLOW_MARK in line:
            allowed = (allowed or line.find(ALLOW_MARK + "-begin") >= 0) and line.find(
                ALLOW_MARK + "-end"
            ) < 0
            continue
        if allowed or (all(ord(c) < 0x80 for c in line) and "?" not in line):
            continue
        found = []
        if line in lossy and line not in old_lines:
            kind = "replacement" if "\ufffd" in line else "lost"
            col = (
                next(i for i, (a, b) in enumerate(zip(line, lossy[line], strict=True)) if a != b)
                + 1
            )
            found.append(
                {
                    "line": n,
                    "col": col,
                    "kind": kind,
                    "found": line.strip(),
                    "fixed": lossy[line].strip(),
                }
            )
        else:
            for m in MOJIBAKE_RX.finditer(line):
                fixed, k = undo_double_encoding(m.group())
                if not k:
                    continue
                word = _word_at(line, m.start(), m.end())
                if found and found[-1]["kind"] == "double" and found[-1]["found"] == word:
                    continue
                found.append(
                    {
                        "line": n,
                        "col": m.start() + 1,
                        "kind": "double",
                        "found": word,
                        "fixed": undo_double_encoding(word)[0],
                    }
                )
            i = line.find("\ufffd")
            if i >= 0:
                found.append(
                    {
                        "line": n,
                        "col": i + 1,
                        "kind": "replacement",
                        "found": _word_at(line, i, i + 1),
                        "fixed": None,
                    }
                )
        (warnings if line in old_lines else errors).extend(found)
    return errors, warnings


MOJIBAKE_WHY = {
    "double": "UTF-8 text read as Windows-1252 and saved again",
    "replacement": "characters lost: a Windows-1252 file was opened as UTF-8 and saved",
    "lost": "accents replaced by '?': saved in a charset without them",
}


def describe(f):
    """One line for a mojibake finding."""
    head = f'line {f["line"]}, column {f["col"]}: "{_show(f["found"])}"'
    if f["fixed"]:
        head += f' should be "{_show(f["fixed"])}"'
    return f"{head} ({MOJIBAKE_WHY[f['kind']]})"


def repair(raw, old_raw=None):
    """Repaired bytes of a file that must be UTF-8, and notes on what changed.

    Windows-1252 bytes become UTF-8, double-encoded sequences are decoded back, and lines whose
    accents became '?' or U+FFFD take the accents of the previous version (old_raw) back.
    Returns (bytes, [notes], [problems left]).
    """
    bom = raw.startswith(BOM_UTF8)
    body = raw[3:] if bom else raw
    notes = []
    text, spots, _ = decode_mixed(body)
    if spots:
        notes.append(f"{len(spots)} Windows-1252 character(s) converted to UTF-8")
    text, n = undo_double_encoding(text)
    if n:
        notes.append(f"{n} double-encoded character(s) decoded back")
    old_text = decode_any(old_raw)
    if old_text:
        lossy = {}
        for ol in old_text.splitlines():
            for v in _lossy(ol):
                lossy.setdefault(v, ol)
        old_lines = set(old_text.splitlines())
        restored = 0
        lines = text.split("\n")
        for i, ln in enumerate(lines):
            core = ln[:-1] if ln.endswith("\r") else ln
            if core in lossy and core not in old_lines:
                lines[i] = lossy[core] + ("\r" if ln.endswith("\r") else "")
                restored += 1
        if restored:
            text = "\n".join(lines)
            notes.append(f"{restored} line(s) took their accents back from the previous version")
    left = [describe(f) for f in mojibake(text)[0]]
    return (BOM_UTF8 if bom else b"") + text.encode("utf-8"), notes, left
