#!/usr/bin/env python3
"""qs - code-quality-suite engine.

  qs.py [run] <files...>   classify, sync rules, generate configs, run pipelines
  qs.py explain <files...> show classification and planned tools (no changes)
  qs.py langs <files...>   print detected language ids (space separated)
  qs.py sync <files...>    only create/populate/diff the rules file
  qs.py ask <files...>     TSV of new languages whose version must be asked
                           (lang, env, default, label)
  qs.py policy             commit/branch policy as shell KEY='value' lines (for the host hooks)
  qs.py encoding [--fix] <files...>  encoding and mojibake report; --fix repairs the files in place
  qs.py version-set <v> [--pom update|snapshot|check|off]   VERSION, pom.xml modules, package.json
  qs.py version-get        versions declared in VERSION / pom.xml / package.json (JSON)
  qs.py version-align WINNER FILE...   give FILEs the version of WINNER
                           (pom.xml / package.json merge driver)
  qs.py release-notes --version V --tip REV --base REV [--date D] [--previous V] [--write]
                           Common Changelog entry of a release (stdout);
                           --write merges it into CHANGELOG.md
  qs.py release-docs --version V [--date D]   README version badge and CITATION.cff
  qs.py repo-files [--force] [--dry-run] [NAME...]   create the missing standard repository files

Env: QUALITY_MODE fix|check, QUALITY_LEVEL, QS_ROOT, QS_STATE, QS_RULES, QS_PERSIST=1,
     QS_EXEC_FILES (file listing executable paths), QUALITY_LOG_LEVEL/FORMAT/FILE.
"""

import argparse
import concurrent.futures as cf
import datetime
import json
import os
import shutil
import subprocess
import sys
import tempfile
import traceback
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import builtin  # noqa: E402
import changelog  # noqa: E402
import maven  # noqa: E402
import policy  # noqa: E402
import qslog  # noqa: E402
import repofiles  # noqa: E402
import rules  # noqa: E402
import runner  # noqa: E402
import semver  # noqa: E402
import versions  # noqa: E402
import writers  # noqa: E402

import registry  # noqa: E402

SUITE = os.path.dirname(HERE)
SKIP_REASONS = ("excluded", "not a regular file")


def env(name, default):
    """Value of an environment variable, or a default when it is unset or empty.

    Args:
        name: the variable name.
        default: the value used when the variable is unset or empty.

    Returns:
        str: the variable value or the default.
    """
    return os.environ.get(name) or default


def read_text(path):
    """Content of a UTF-8 text file.

    Args:
        path: the file path.

    Returns:
        str: the decoded text.

    Raises:
        OSError: the file cannot be read.
        UnicodeDecodeError: the file is not UTF-8.
    """
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def read_bytes(path):
    """Content of a file as bytes.

    Args:
        path: the file path.

    Returns:
        bytes: the raw content.

    Raises:
        OSError: the file cannot be read.
    """
    with open(path, "rb") as fh:
        return fh.read()


def write_if_changed(path, text):
    """Write a UTF-8 text file (LF line ends) only when its content differs.

    Args:
        path: the file path.
        text: the wanted content.

    Returns:
        None. An OSError is ignored: the export is best effort.
    """
    try:
        if not os.path.exists(path) or read_text(path) != text:
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
    except OSError:
        pass


def load_runtime_env(path="/opt/qs/runtime.env"):
    """PATH and variables of the runtimes installed in the image (written by qs-install).

    Args:
        path: the KEY=value file; a missing file is ignored.

    Returns:
        None. PATH_PREPEND is put in front of PATH; other keys are set when unset.
    """
    try:
        lines = read_text(path).splitlines()
    except OSError:
        return
    for line in lines:
        k, _, v = line.partition("=")
        if k == "PATH_PREPEND" and v:
            os.environ["PATH"] = v + ":" + os.environ.get("PATH", "")
        elif k and k not in os.environ:
            os.environ[k] = v


def _is_checked(c):
    """True when a classified file is a text file the encoding gate looks at.

    Args:
        c: a classification from registry.classify.

    Returns:
        bool: the file is not binary, not excluded and a regular file.
    """
    return not (c.binary or c.reason in SKIP_REASONS)


def _drop_files(by_lang, failed):
    """Remove files from the per-language lists, and languages left without files.

    Args:
        by_lang: {language id: [paths]}, changed in place.
        failed: the paths to remove.

    Returns:
        None.
    """
    for lid in list(by_lang):
        by_lang[lid] = [f for f in by_lang[lid] if f not in failed]
        if not by_lang[lid]:
            del by_lang[lid]


def _exec_files():
    """Paths listed as executable by the host in the file named by QS_EXEC_FILES.

    Returns:
        set[str]: one entry per line; empty when QS_EXEC_FILES is unset or missing.

    Raises:
        OSError: the file exists but cannot be read.
    """
    path = os.environ.get("QS_EXEC_FILES")
    if path and os.path.exists(path):
        return set(read_text(path).split("\n"))
    return set()


class App:
    """One engine run: the rules file, the registry and the state folder of a repository."""

    def __init__(self):
        """Read the environment (QS_*, QUALITY_*) and load the tool registry."""
        load_runtime_env(os.environ.get("QS_RUNTIME_ENV", "/opt/qs/runtime.env"))
        self.root = os.path.abspath(env("QS_ROOT", os.getcwd()))
        self.mode = env("QUALITY_MODE", "fix")
        self.state = env("QS_STATE", "/qs-state" if os.path.isdir("/qs-state") else "")
        self.persist = os.environ.get("QS_PERSIST") == "1" and self.mode == "fix"
        self.rules_path = env("QS_RULES", os.path.join(self.root, ".quality-rules.json"))
        self.config_dir = env("QS_CONFIG", os.path.join(SUITE, "config"))
        self.npm_dir = env("QS_NPM", "/opt/npm")
        self.reg = registry.Registry(
            env("QS_REGISTRY", os.path.join(SUITE, "registry", "registry.json"))
        )
        rules.bind(self.reg)
        self.tmp = tempfile.mkdtemp(prefix="qs-")
        if self.state and not os.environ.get("QUALITY_LOG_FILE") and os.access(self.state, os.W_OK):
            os.environ["QUALITY_LOG_FILE"] = os.path.join(self.state, "quality-suite.log")
        self.data = None
        self.exit = 0

    # ---------- rules file ----------
    def load_rules(self):
        """Load and validate the rules file (a skeleton when it does not exist).

        Returns:
            bool: True when the rules are valid; problems are logged.
        """
        schema_ref = env(
            "QS_SCHEMA_REF", os.path.join(SUITE, "schema", "quality-rules.schema.json")
        )
        created = False
        try:
            self.data = rules.load(self.rules_path) if os.path.exists(self.rules_path) else None
        except json.JSONDecodeError as e:
            qslog.log(
                "ERROR",
                "rules",
                f"invalid JSON at line {e.lineno} col {e.colno}: {e.msg}",
                os.path.basename(self.rules_path),
                "load",
                "ERROR",
            )
            return False
        if self.data is None:
            self.data = rules.skeleton(schema_ref)
            created = True
        errors, warnings = rules.validate(self.data, self.reg)
        for warn in warnings:
            qslog.log("WARN", "rules", warn, os.path.basename(self.rules_path), "validate", "WARN")
        for err in errors:
            qslog.log("ERROR", "rules", err, os.path.basename(self.rules_path), "validate", "ERROR")
        if errors:
            return False
        self._loaded = json.loads(json.dumps(self.data))
        self._created = created
        return True

    def sync_rules(self, langs, vers):
        """Add policy defaults, global tools and new languages to the rules file.

        Args:
            langs: the language ids found in this run.
            vers: {language id: (version, source)} detected.

        Returns:
            list[str]: what the suite changed (policy, global, language ids, detected versions).
        """
        changed_by_suite = []
        added = policy.populate(self.data)
        if added and not getattr(self, "_created", False):
            changed_by_suite.append("policy")
            qslog.log(
                "INFO",
                "rules",
                f"added policy defaults: {', '.join(added)}",
                os.path.basename(self.rules_path),
                "populate",
                "SUCCESS",
            )
        if rules.populate_global(self.data, self.reg):
            changed_by_suite.append("global")
        for lid in sorted(langs):
            lang = self.reg.languages[lid]
            env_v = os.environ.get((lang.get("version") or {}).get("env") or "_none_")
            if rules.populate_language(self.data, self.reg, lid, vers.get(lid), env_v):
                changed_by_suite.append(lid)
                qslog.log(
                    "INFO",
                    "rules",
                    f"added language '{lid}' with base rules"
                    + (
                        f" (version pinned from env {lang['version']['env']}={env_v})"
                        if env_v
                        else ""
                    ),
                    os.path.basename(self.rules_path),
                    "populate",
                    "SUCCESS",
                )
            sec = self.data["languages"].get(lid, {})
            v, src = vers.get(lid, (None, None))
            if sec.get("version", "auto") == "auto" and v and src not in ("rules",):
                det = f"{v} ({src})"
                if sec.get("detected_version") != det:
                    sec["detected_version"] = det
                    changed_by_suite.append(f"{lid}.detected_version")
        if self.persist and (self.data != self._loaded or getattr(self, "_created", False)):
            rules.save(self.rules_path, self.data)
            if getattr(self, "_created", False):
                qslog.log(
                    "INFO",
                    "rules",
                    "created rules file (languages are added as they are detected)",
                    os.path.basename(self.rules_path),
                    "create",
                    "SUCCESS",
                )
                self._created = False
        return changed_by_suite

    def export_tests(self):
        """Plain list of test commands for the host hook (it has no JSON parser on Git Bash)."""
        if not self.state or not os.access(self.state, os.W_OK):
            return
        t = self.data.get("tests") or {}
        lines = [c for c in t.get("commands", []) if isinstance(c, str) and c.strip()]
        if t.get("autodetect"):
            lines.append("@autodetect")
        write_if_changed(
            os.path.join(self.state, "tests.txt"), "".join(line + "\n" for line in lines)
        )

    def export_policy(self):
        """Commit/branch policy for the host hooks: <state>/policy.env (shell syntax)."""
        if not self.state or not os.access(self.state, os.W_OK):
            return
        write_if_changed(os.path.join(self.state, "policy.env"), policy.shell_env(self.data))

    def encoding_gate(self, cls):
        """Check every text file against the encoding policy before any tool touches it.

        Also fills self.enc_errors / self.enc_warnings ({path: [lines]}) for the console.
        why: formatters assume UTF-8; running them on a file in another charset corrupts accents.

        Args:
            cls: the classifications of the files of this run.

        Returns:
            tuple: (StepResult or None, failed paths, {path: charset} of files to protect).
        """
        enc = policy.get(self.data, "encoding")
        self.enc_errors, self.enc_warnings = {}, {}
        if not enc.get("enabled", True):
            return None, set(), {}
        res = runner.StepResult("qs-encoding", "syntax")
        failed, protect, texts = self._check_charsets(cls, enc)
        self._check_mojibake(texts, enc.get("mojibake", "block"), failed)
        for c in cls:
            if c.path in failed:
                res.status[c.path] = "ERROR"
                res.output += [f"{c.path}: {x}" for x in self.enc_errors[c.path]]
            elif _is_checked(c) and os.path.isfile(os.path.join(self.root, c.path)):
                res.status[c.path] = "SUCCESS"
        for path, lines in sorted(self.enc_warnings.items()):
            for x in lines:
                qslog.log("WARN", "encoding", x, path, "mojibake", "WARN", console=False)
        return (res if res.status else None), failed, protect

    def _check_charsets(self, cls, enc):
        """Charset and BOM check of every text file (first half of the encoding gate).

        Args:
            cls: the classifications of the files of this run.
            enc: the encoding policy.

        Returns:
            tuple: (failed paths, {path: charset} to protect, {path: text} to check for
            mojibake). Problems are stored in self.enc_errors.
        """
        failed, protect, texts = set(), {}, {}
        mode = enc.get("mojibake", "block")
        for c in cls:
            if not _is_checked(c):
                continue
            try:
                raw = read_bytes(os.path.join(self.root, c.path))
            except OSError:
                continue
            cs, bom = policy.expected(enc, c.path, c.lang)
            probs = policy.check(raw, cs, bom)
            if probs:
                failed.add(c.path)
                self.enc_errors[c.path] = probs
                continue
            if policy.needs_protection(raw, cs):
                protect[c.path] = cs
            if (
                cs == "utf-8"
                and mode != "off"
                and not any(policy.glob_match(c.path, g) for g in enc.get("mojibake_ignore") or [])
            ):
                text = (raw[3:] if raw.startswith(policy.BOM_UTF8) else raw).decode("utf-8")
                if "?" in text or any(ord(ch) >= 0x80 for ch in text):
                    texts[c.path] = text
        return failed, protect, texts

    def _check_mojibake(self, texts, mode, failed):
        """Mojibake check of UTF-8 texts against their previous version (QS_BASE_REV).

        why: the previous version tells new damage from old, and gives back accents turned
        into '?'.

        Args:
            texts: {path: text} to check.
            mode: block or warn (encoding.mojibake).
            failed: the failed paths, extended in place.

        Returns:
            None. Findings go to self.enc_errors and self.enc_warnings.
        """
        rev = os.environ.get("QS_BASE_REV", "")
        olds = old_blobs(self.root, rev, sorted(texts))
        for path, text in sorted(texts.items()):
            errs, warns = policy.mojibake(text, policy.decode_any(olds.get(path)))
            if mode == "warn":
                errs, warns = [], errs + warns
            if errs:
                failed.add(path)
                self.enc_errors[path] = [policy.describe(f) for f in errs]
            if warns:
                self.enc_warnings[path] = [
                    policy.describe(f)
                    + (f" [already in {rev}]" if f in warns and rev and mode != "warn" else "")
                    for f in warns
                ]

    def encoding_report(self, stopped=True):
        """Console block listing every file with an encoding problem (and the warnings).

        Args:
            stopped: say that nothing else ran.

        Returns:
            None.
        """
        n = len(self.enc_errors)
        if n:
            tail = " Nothing was formatted or analysed." if stopped else ""
            print(
                f"[quality-suite] ENCODING: {n} file(s) with encoding problems.{tail}", flush=True
            )
            for path in sorted(self.enc_errors):
                print(f"[quality-suite]   {path}")
                for x in self.enc_errors[path][:8]:
                    print(f"[quality-suite]       {x}")
                if len(self.enc_errors[path]) > 8:
                    print(f"[quality-suite]       ... {len(self.enc_errors[path]) - 8} more")
                qslog.log(
                    "ERROR",
                    "encoding",
                    "; ".join(self.enc_errors[path][:3]),
                    path,
                    "check",
                    "ERROR",
                    console=False,
                )
            print(
                "[quality-suite] Repair: git encoding --fix <file>   "
                "(or reopen it in VS Code with the right "
                "encoding, then 'Save with Encoding' -> UTF-8)",
                flush=True,
            )
            print("[quality-suite] Guide: docs/QUALITY-RULES.md, section 'Encoding'", flush=True)
        for path in sorted(self.enc_warnings):
            for x in self.enc_warnings[path][:3]:
                print(f"[quality-suite] WARN encoding {path}: {x}", flush=True)

    def encoding_cmd(self, files, fix=False):
        """qs.py encoding [--fix]: report (and repair) the encoding of the given files.

        Args:
            files: the paths to check.
            fix: repair UTF-8 files in place.

        Returns:
            int: 0 clean, 1 problems left, 2 invalid rules file.
        """
        if not self.load_rules():
            return 2
        policy.populate(self.data)
        cls = self.classify(files)
        self.encoding_gate(cls)
        if fix:
            self._repair_files(cls)
            self.encoding_gate(cls)
        self.encoding_report(stopped=False)
        if not self.enc_errors:
            checked = len([c for c in cls if not c.binary])
            print(f"[quality-suite] encoding OK: {checked} file(s) checked", flush=True)
        return 1 if self.enc_errors else 0

    def _repair_files(self, cls):
        """Repair the encoding of the UTF-8 files among cls (git encoding --fix).

        Args:
            cls: the classifications of the files to repair.

        Returns:
            None. What changed, and what could not be repaired, is printed.

        Raises:
            OSError: a file cannot be read or written.
        """
        enc = policy.get(self.data, "encoding")
        targets = [
            c for c in cls if _is_checked(c) and os.path.isfile(os.path.join(self.root, c.path))
        ]
        olds = old_blobs(self.root, os.environ.get("QS_BASE_REV", ""), [c.path for c in targets])
        for c in targets:
            cs, bom = policy.expected(enc, c.path, c.lang)
            ap = os.path.join(self.root, c.path)
            raw = read_bytes(ap)
            if cs != "utf-8":
                if c.path in self.enc_errors:
                    print(
                        f"[quality-suite] {c.path}: must be {cs.upper()}; "
                        f"not repaired automatically (see the message above)"
                    )
                continue
            new, notes, left = policy.repair(raw, olds.get(c.path))
            if bom == "forbid" and new.startswith(policy.BOM_UTF8):
                new, notes = new[3:], notes + ["BOM removed"]
            if new != raw:
                with open(ap, "wb") as fh:
                    fh.write(new)
                print(f"[quality-suite] repaired {c.path}: {'; '.join(notes)}")
            for x in left:
                print(f"[quality-suite] {c.path}: NOT repaired, fix it by hand: {x}")

    def snapshot_diff(self):
        """Log the changes of the rules since the last applied snapshot, and record it.

        Returns:
            list[tuple]: (path, old value, new value) per change; empty without a state folder.
        """
        if not self.state:
            return []
        snap = os.path.join(self.state, "rules.applied.json")
        try:
            old = json.loads(read_text(snap))
        except (OSError, json.JSONDecodeError):
            old = None
        changes = rules.diff(old or {}, self.data) if old is not None else []
        for path, a, b in changes:
            kind = "added" if a is None else "removed" if b is None else "modified"
            qslog.log(
                "INFO",
                "rules",
                f"{kind} {path}: {rules.short(a)} -> {rules.short(b)}",
                os.path.basename(self.rules_path),
                "change",
                "SUCCESS",
            )
        if self.persist and (old is None or changes) and os.access(self.state, os.W_OK):
            with open(snap, "w", encoding="utf-8") as fh:
                json.dump(self.data, fh, indent=2, ensure_ascii=False)
            if old is None:
                qslog.log(
                    "INFO",
                    "rules",
                    "baseline snapshot recorded",
                    os.path.basename(self.rules_path),
                    "snapshot",
                    "SUCCESS",
                )
        return changes

    # ---------- configs ----------
    def tool_rules(self, lid, tid, version, seen=()):
        """Rules for a tool: inherited tool's rules (shared config), own rules, version values.

        Args:
            lid: the language id ('_global' for repository checks).
            tid: the tool id.
            version: the language version, or None.
            seen: tool ids already visited (stops inheritance cycles).

        Returns:
            dict: the effective rules.
        """
        tool = self.reg.tools[tid]
        own = rules.tool_settings(self.data, lid, tid, tool["role"])["rules"]
        parent = (tool.get("config") or {}).get("inherit")
        merged = {}
        if parent and parent in self.reg.tools and parent not in seen:
            merged = self.tool_rules(lid, parent, version, (*seen, tid))
        merged = writers.deep_merge(merged, own)
        return runner.effective_rules(tool, merged, version)

    def _base_config(self, cfg):
        """Path and text of the base config file a tool config extends.

        Args:
            cfg: the 'config' entry of the tool.

        Returns:
            tuple: (absolute path or None, text or None when missing or unreadable).
        """
        base_rel = cfg.get("base")
        if not base_rel:
            return None, None
        base_abs = base_rel.replace("{npm}", self.npm_dir).replace("{config}", self.config_dir)
        if not os.path.isabs(base_abs):
            base_abs = os.path.join(self.config_dir, base_abs)
        try:
            return base_abs, read_text(base_abs)
        except OSError:
            return base_abs, None

    def generate_configs(self, pairs, out_dir, vers=None):
        """Write the native config file of every (language, tool) pair.

        Args:
            pairs: iterable of (lang_id, tool_id).
            out_dir: folder for the generated files.
            vers: {language id: (version, source)}.

        Returns:
            tuple: ({(lid, tid): path}, ok); ok is False when a config could not be built.
        """
        paths, ok = {}, True
        vers = vers or {}
        for lid, tid in sorted(set(pairs)):
            tool = self.reg.tools[tid]
            cfg = tool.get("config")
            if not cfg or not cfg.get("format"):
                # why: {"inherit": ...} only shares rules (rendered as flags), no file to write
                continue
            trules = self.tool_rules(lid, tid, (vers.get(lid) or (None,))[0])
            base_abs, base_text = self._base_config(cfg)
            if (
                base_text is None
                and not trules
                and cfg.get("format") not in ("eslint", "php-cs-fixer")
            ):
                if base_abs and os.path.exists(base_abs):
                    paths[(lid, tid)] = base_abs
                continue
            # why: a broken rule must block with a clear message, not run unconfigured
            try:
                text = writers.build(dict(cfg, base_abs=base_abs), base_text, trules)
            except Exception as e:
                qslog.log(
                    "ERROR",
                    "rules",
                    f"cannot generate config for '{lid}.{tid}': {e}",
                    cfg.get("file", ""),
                    "generate",
                    "ERROR",
                )
                ok = False
                continue
            dst = os.path.join(out_dir, lid, tid, cfg["file"])
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
            paths[(lid, tid)] = dst
        return paths, ok

    def all_rule_tools(self):
        """Every (language, tool) pair the rules file configures.

        Returns:
            set[tuple]: (lid, tid) pairs, with '_global' for repository checks.
        """
        out = set()
        for lid, sec in (self.data.get("languages") or {}).items():
            if lid not in self.reg.languages:
                continue
            for cat in rules.CATEGORIES:
                for tid in sec.get(cat) or {}:
                    if tid in self.reg.tools:
                        out.add((lid, tid))
        for tid in self.data.get("global") or {}:
            if tid in self.reg.tools:
                out.add(("_global", tid))
        return out

    # ---------- main ----------
    def classify(self, files):
        """Classify files by language, with the excludes and extensions of the rules file.

        Args:
            files: the paths, relative to the repository root.

        Returns:
            list: one classification per file (see registry.classify).
        """
        excludes, extra = self._classify_args()
        return registry.classify(self.reg, self.root, files, excludes, extra)

    def detect_languages(self, files):
        """Which languages (and subtypes) exist among the files; skips redundant files.

        Args:
            files: the paths, relative to the repository root.

        Returns:
            dict: {language id: set of subtype ids} (see registry.detect_languages).
        """
        excludes, extra = self._classify_args()
        return registry.detect_languages(self.reg, self.root, files, excludes, extra)

    def _classify_args(self):
        """Excludes and extra extensions shared by classify and detect_languages.

        Returns:
            tuple: (exclude globs, {extension: language id}).
        """
        excludes = (
            list(self.reg.default_excludes)
            + list((self.data or {}).get("exclude", []))
            + [os.path.basename(self.rules_path)]
        )
        extra = {}
        for lid, sec in ((self.data or {}).get("languages") or {}).items():
            for e in sec.get("extensions", []) or []:
                extra[e] = lid
        return excludes, extra

    def _group(self, cls):
        """Group classified files by language and note the ambiguous extensions.

        Args:
            cls: the classifications.

        Returns:
            tuple: ({lid: [paths]}, {path: subtypes}, set of confidently resolved ambiguous paths).
        """
        by_lang, subtypes, ambiguous = {}, {}, set()
        for c in cls:
            if c.skip:
                qslog.log("DEBUG", "classify", c.reason, c.path, "classify", "SKIP")
                continue
            by_lang.setdefault(c.lang, []).append(c.path)
            subtypes[c.path] = c.subtypes
            low = os.path.basename(c.path).lower()
            exts = [e for e in self.reg.by_ext if low.endswith(e)]
            if exts and len(self.reg.by_ext[max(exts, key=len)]) > 1:
                mk = self.reg.languages[c.lang].get("marker") or {}
                if c.confident:
                    ambiguous.add(c.path)
                elif mk.get("always") and mk.get("shebang"):
                    pass  # why: the marker step adds the shebang, which pins the language next time
                else:
                    qslog.log(
                        "WARN",
                        c.lang,
                        "ambiguous extension resolved by guess; add a modeline to pin it",
                        c.path,
                        "classify",
                        "WARN",
                    )
        return by_lang, subtypes, ambiguous

    def _apply_rule_changes(self, vers):
        """Regenerate the native configs in the state folder when the rules changed.

        Args:
            vers: {language id: (version, source)}.

        Returns:
            None.
        """
        changes = self.snapshot_diff()
        if not (self.persist and changes and self.state and os.access(self.state, os.W_OK)):
            return
        gen_dir = os.path.join(self.state, "generated")
        shutil.rmtree(gen_dir, ignore_errors=True)
        _, gok = self.generate_configs(self.all_rule_tools(), gen_dir, vers)
        qslog.log(
            "INFO" if gok else "ERROR",
            "rules",
            f"{len(changes)} change(s) applied; "
            "native configs regenerated in .git/quality-suite/generated",
            os.path.basename(self.rules_path),
            "apply",
            "SUCCESS" if gok else "ERROR",
        )

    def _plans(self, by_lang, subtypes):
        """Tool plan of every language.

        Args:
            by_lang: {lid: [paths]}.
            subtypes: {path: subtypes}.

        Returns:
            tuple: ({lid: (steps, level)}, set of (lid, tid) pairs used).
        """
        plans, pairs = {}, set()
        for lid, lfiles in sorted(by_lang.items()):
            steps, lvl = runner.plan(
                self.reg, self.data, lid, lfiles, subtypes, os.environ.get("QUALITY_LEVEL"), rules
            )
            plans[lid] = (steps, lvl)
            pairs |= {(lid, t["id"]) for t, _, _ in steps}
        return plans, pairs

    def _context(self, cfg_paths, exec_files, ambiguous, protect, plans):
        """The runner context of this run.

        Args:
            cfg_paths: {(lid, tid): generated config path}.
            exec_files: paths the host marks executable.
            ambiguous: paths of ambiguous extensions resolved with confidence.
            protect: {path: charset} of files tools must not re-encode.
            plans: {lid: (steps, level)}.

        Returns:
            runner.Ctx: the context (builtin.CHARSET_OF is set as a side effect).
        """
        ctx = runner.Ctx(self.root, self.mode, self.tmp, cfg_paths, exec_files, ambiguous)
        ctx.protect = protect
        ctx.policy = self.data
        enc = policy.get(self.data, "encoding")
        ctx.charsets = {
            lid: policy.expected(enc, "", lid)[0].upper().replace("WINDOWS-", "windows-")
            for lid in plans
        }
        builtin.CHARSET_OF = {os.path.join(self.root, f): cs for f, cs in protect.items()}
        return ctx

    def _internal_error(self, lid, e, by_lang):
        """Log an unexpected pipeline failure and turn it into an ERROR result.

        Call it from inside the 'except' block (the traceback is logged).

        Args:
            lid: the language id of the pipeline.
            e: the exception.
            by_lang: {lid: [paths]}.

        Returns:
            runner.StepResult: every file of the language marked ERROR.
        """
        qslog.log(
            "ERROR",
            lid,
            f"internal error: {e!r}; see the log for the traceback",
            action="run",
            status="ERROR",
        )
        qslog.log("DEBUG", lid, traceback.format_exc(), action="run", status="ERROR")
        err = runner.StepResult("engine", "syntax")
        err.status = {f: "ERROR" for f in (by_lang.get(lid) or [])}
        err.output = [f"internal error in the {lid} pipeline: {e!r}"]
        return err

    def _execute(self, plans, gsteps, ctx, by_lang, vers):
        """Run every language pipeline in parallel, and the repository checks.

        Args:
            plans: {lid: (steps, level)}.
            gsteps: the repository check steps.
            ctx: the runner context.
            by_lang: {lid: [paths]}.
            vers: {lid: (version, source)}.

        Returns:
            dict: {lid or '_global': [StepResult]}.
        """
        jobs = {}
        with cf.ThreadPoolExecutor(max_workers=max(2, os.cpu_count() or 2)) as ex:
            for lid, (steps, _) in plans.items():
                jobs[ex.submit(runner.run_language, self.reg, lid, steps, ctx, vers[lid][0])] = lid
            if gsteps and self.mode != "fix":
                jobs[ex.submit(self._run_global, gsteps, ctx)] = "_global"
            done = {}
            for fut in cf.as_completed(jobs):
                lid = jobs[fut]
                # why: one broken tool definition must not hide every other result
                try:
                    done[lid] = fut.result()
                except Exception as e:
                    done[lid] = [self._internal_error(lid, e, by_lang)]
            if gsteps and self.mode == "fix":
                # why: formatters rewrite files in place; repository checks must read the final
                # content
                done["_global"] = self._run_global(gsteps, ctx)
        return done

    def run(self, files, sync_only=False):
        """qs.py run / sync: the whole quality gate over the given files.

        Args:
            files: the paths, relative to the repository root.
            sync_only: only update the rules file and the state folder.

        Returns:
            int: 0 clean, 1 findings, 2 invalid rules or configs.
        """
        if not self.load_rules():
            return 2
        cls = self.classify(files)
        by_lang, subtypes, ambiguous = self._group(cls)
        langs = self.data.get("languages") or {}
        vers = {
            lid: versions.resolve(self.reg.languages[lid], langs.get(lid), self.root)
            for lid in by_lang
        }
        self.sync_rules(by_lang.keys(), vers)
        self.export_tests()
        self.export_policy()
        enc_res, enc_failed, protect = self.encoding_gate(cls)
        if enc_failed and not sync_only:
            # why: an encoding problem stops everything: formatters would rewrite the damaged text
            # and the real cause would drown in findings about the other files
            self.encoding_report(stopped=True)
            return 1
        if self.enc_warnings and not sync_only:
            self.encoding_report(stopped=False)
        # why: a file in the wrong encoding is reported once, and no tool rewrites it
        _drop_files(by_lang, enc_failed)
        self._apply_rule_changes(vers)
        if sync_only:
            return 0
        exec_files = _exec_files()
        plans, pairs = self._plans(by_lang, subtypes)
        gfiles = [
            c.path
            for c in cls
            if not c.binary
            and os.path.isfile(os.path.join(self.root, c.path))
            and c.reason != "excluded"
            and c.path not in enc_failed
        ]
        gsteps = self._global_steps(gfiles)
        if not by_lang and not gsteps and not enc_res:
            qslog.log("INFO", "engine", "nothing to analyze", action="run", status="SUCCESS")
            return 0
        pairs |= {("_global", t["id"]) for t, _, _ in gsteps}
        cfg_paths, ok = self.generate_configs(pairs, os.path.join(self.tmp, "config"), vers)
        if not ok:
            return 2
        for lid, (steps, _) in plans.items():
            for tool, st, _ in steps:
                st["rules"] = self.tool_rules(lid, tool["id"], (vers.get(lid) or (None,))[0])
        ctx = self._context(cfg_paths, exec_files, ambiguous, protect, plans)
        qslog.log(
            "INFO",
            "engine",
            f"run start mode={self.mode} files={len(files)} languages={len(plans)}",
            action="run",
            status="SUCCESS",
        )
        done = self._execute(plans, gsteps, ctx, by_lang, vers)
        if enc_res and (
            enc_failed or os.environ.get("QUALITY_LOG_LEVEL") == "DEBUG" or "_global" in done
        ):
            done["_global"] = [enc_res, *done.get("_global", [])]
        self._report_all(done, plans, vers, by_lang, gfiles)
        status = "ERROR" if self.exit else "SUCCESS"
        qslog.log(
            "ERROR" if self.exit else "INFO",
            "engine",
            f"run end status={status}",
            action="run",
            status=status,
        )
        return self.exit

    def _report_all(self, done, plans, vers, by_lang, gfiles):
        """Report the results of every pipeline, languages first, repository checks last.

        Args:
            done: {lid or '_global': [StepResult]}.
            plans: {lid: (steps, level)}.
            vers: {lid: (version, source)}.
            by_lang: {lid: [paths]}.
            gfiles: the paths of the repository checks.

        Returns:
            None. self.exit becomes 1 on any ERROR.
        """
        glevel = os.environ.get("QUALITY_LEVEL") or self.data.get("level", "standard")
        order = [lid for lid in sorted(plans) if lid in done]
        if "_global" in done:
            order.append("_global")
        for lid in order:
            self._report(
                lid,
                done[lid],
                plans.get(lid, ([], glevel))[1],
                vers.get(lid),
                by_lang.get(lid, gfiles),
            )

    def _global_steps(self, files):
        """Repository check steps enabled at the current level.

        Args:
            files: the paths the checks receive.

        Returns:
            list[tuple]: (tool, settings, files) per step.
        """
        steps = []
        lvl = os.environ.get("QUALITY_LEVEL") or self.data.get("level", "standard")
        for tid in self.reg.global_tools:
            tool = self.reg.tools.get(tid)
            if not tool:
                continue
            st = rules.tool_settings(self.data, "_global", tid, tool["role"])
            tlevel = st.get("level") or tool.get("level") or registry.ROLE_LEVEL[tool["role"]]
            if (
                not st["enabled"]
                or registry.level_rank(lvl) < registry.level_rank(tlevel)
                or not runner.available(tool)
            ):
                continue
            req = (tool.get("requires") or {}).get("any_file")
            if req and not any(os.path.exists(os.path.join(self.root, r)) for r in req):
                continue
            steps.append((tool, st, files))
        return steps

    def _run_global(self, steps, ctx):
        """Run the repository check steps that have files.

        Args:
            steps: (tool, settings, files) per step.
            ctx: the runner context.

        Returns:
            list: one StepResult per step run.
        """
        return [
            runner.run_tool(t, st, None, ctx, files, None, "_global")
            for t, st, files in steps
            if files
        ]

    def _report(self, lid, results, lvl, ver, files):
        """Print and log the results of one pipeline.

        Args:
            lid: the language id, or '_global'.
            results: its StepResults.
            lvl: the quality level used.
            ver: (version, source) or None.
            files: the paths it checked.

        Returns:
            None. self.exit becomes 1 on any ERROR.
        """
        name = self.reg.languages[lid]["name"] if lid in self.reg.languages else "Repository checks"
        vtxt = f", version={ver[0]} ({ver[1]})" if ver and ver[0] else ""
        print(
            f"[quality-suite] {name}: {len(files)} file(s) (level={lvl or 'standard'}{vtxt})",
            flush=True,
        )
        for r in results:
            # why: successful steps stay quiet (fix chatter is noise); the log file keeps the
            # per-file result
            if (
                any(st == "ERROR" for st in r.status.values())
                or os.environ.get("QUALITY_LOG_LEVEL") == "DEBUG"
            ):
                for line in r.output[:400]:
                    print(f"[qs:{lid}:{r.tool_id}] {line}")
            if r.note:
                qslog.log("WARN", lid, r.note, action=r.tool_id, status="SKIP")
            errs = sorted(f for f, s in r.status.items() if s == "ERROR")
            oks = sorted(f for f, s in r.status.items() if s == "SUCCESS")
            for f in oks:
                qslog.log("INFO", lid, f"{r.role} by {r.tool_id}", f, r.tool_id, "SUCCESS")
            for f in errs:
                qslog.log("ERROR", lid, f"{r.role} by {r.tool_id} failed", f, r.tool_id, "ERROR")
            if errs:
                self.exit = 1

    def explain(self, files):
        """qs.py explain: classification and planned tools of each file, without changes.

        Args:
            files: the paths.

        Returns:
            int: 0, or 2 for an invalid rules file.
        """
        if not self.load_rules():
            return 2
        for c in self.classify(files):
            if c.skip:
                print(f"{c.path}: skipped ({c.reason})")
                continue
            steps, lvl = runner.plan(
                self.reg,
                self.data,
                c.lang,
                [c.path],
                {c.path: c.subtypes},
                os.environ.get("QUALITY_LEVEL"),
                rules,
                quiet=True,
            )
            v = versions.resolve(
                self.reg.languages[c.lang],
                (self.data.get("languages") or {}).get(c.lang),
                self.root,
            )
            sub = f" +{','.join(c.subtypes)}" if c.subtypes else ""
            vtxt = f", version={v[0]} via {v[1]}" if v[0] else ""
            print(
                f"{c.path}: {c.lang}{sub} (level={lvl}{vtxt}, charset={c.charset or '?'}"
                f"{'' if c.confident else ', GUESSED'})"
            )
            for t, _, _ in steps:
                print(f"    {t['role']:<7} {t['id']}")
        return 0

    def ask(self, files):
        """Languages new to the rules file whose version could not be detected.

        The host prompts once for each (TSV on stdout: lang, env, default, label).

        Args:
            files: the paths.

        Returns:
            int: 0.
        """
        try:
            data = rules.load(self.rules_path) if os.path.exists(self.rules_path) else None
        except (OSError, json.JSONDecodeError):
            data = None
        self.data = data or rules.skeleton("")
        known = set((self.data.get("languages") or {}).keys())
        for lid in sorted(set(self.detect_languages(files)) - known):
            spec = self.reg.languages[lid].get("version")
            if not spec or not spec.get("ask", True):
                continue
            _, src = versions.resolve(self.reg.languages[lid], None, self.root)
            if src == "default":
                print(
                    "\t".join(
                        [
                            lid,
                            spec.get("env") or "-",
                            str(spec.get("default") or "-"),
                            spec.get("label", f"{self.reg.languages[lid]['name']} version"),
                        ]
                    )
                )
        return 0


def old_blobs(root, rev, paths):
    """{path: bytes} of the given paths at revision rev, read by one 'git cat-file --batch'.

    QS_GIT_DIR (the repository's object store mounted read-only by the hooks) is used when set.
    Paths missing at rev (new files) are left out; any git failure gives {} (first commit, no
    git): the checks then treat every finding as new.

    Args:
        root: the work tree.
        rev: the revision; '' gives {}.
        paths: the paths, relative to root.

    Returns:
        dict[str, bytes]: the content of each path found at rev.
    """
    paths = [p for p in paths if "\n" not in p]
    if not rev or not paths:
        return {}
    try:
        proc = subprocess.run(
            [*gitcmd(root), "cat-file", "--batch"],
            capture_output=True,
            timeout=120,
            input="".join(f"{rev}:{p}\n" for p in paths).encode("utf-8"),
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return {}
    if proc.returncode:
        return {}
    out, data, i = {}, proc.stdout, 0
    for path in paths:
        nl = data.find(b"\n", i)
        if nl < 0:
            break
        head = data[i:nl].split()
        i = nl + 1
        if len(head) == 3 and head[1] == b"blob":
            size = int(head[2])
            out[path] = data[i : i + size]
            i += size + 1
    return out


def read_list(path):
    """File list written by the hooks: NUL-separated (git -z) or one path per line.

    Args:
        path: the list file.

    Returns:
        list[str]: the non-empty paths.

    Raises:
        OSError: the file cannot be read.
    """
    with open(path, "rb") as fh:
        raw = fh.read().decode("utf-8", "surrogateescape")
    items = raw.split("\0") if "\0" in raw else raw.splitlines()
    return [x for x in items if x]


def gitcmd(root):
    """git command for the repository: the object store mounted by the hooks, else the work tree.

    Args:
        root: the work tree.

    Returns:
        list[str]: the git command line prefix.
    """
    gd = os.environ.get("QS_GIT_DIR")
    return ["git", f"--git-dir={gd}"] if gd else ["git", "-C", root]


# ---------------------------------------------------------------- repository file commands


def _tool_version_set(ap, argv, where):
    """qs.py version-set: write the version to VERSION, pom.xml modules and package.json.

    Args:
        ap: the argument parser of the command.
        argv: the command arguments.
        where: namespace with root, data, br (branches policy) and git.

    Returns:
        int: 0, or 2 for an invalid version. The changed files are printed.
    """
    br = where.br
    ap.add_argument("version")
    ap.add_argument(
        "--pom", default=br["pom_version"], choices=("update", "snapshot", "check", "off")
    )
    ap.add_argument("--version-file", default=br["version_file"])
    a = ap.parse_args(argv)
    if not semver.valid(a.version):
        print(f"'{a.version}' is not a semantic version", file=sys.stderr)
        return 2
    changed, notes = maven.set_versions(where.root, a.version, a.version_file, pom=False)
    pv = maven.read_versions(where.root, "").get("pom.xml")
    if a.pom in ("update", "snapshot") and pv is not None:
        want = a.version + (
            "-SNAPSHOT" if a.pom == "snapshot" and not a.version.endswith("-SNAPSHOT") else ""
        )
        c, n = maven.set_poms(where.root, want)
        changed, notes = changed + c, notes + n
    elif a.pom == "check" and pv and pv not in (a.version, a.version + "-SNAPSHOT"):
        notes.append(
            f"pom.xml has {pv}; set it: mvn versions:set -DnewVersion={a.version} "
            f"-DgenerateBackupPoms=false"
        )
    changed += maven.set_package_json(where.root, a.version)
    for n in notes:
        print(f"[quality-suite] {n}", file=sys.stderr)
    print("\n".join(changed))
    return 0


def _tool_version_align(ap, argv, where):
    """qs.py version-align: give files the version of a winner (merge driver).

    Args:
        ap: the argument parser of the command.
        argv: the command arguments.
        where: namespace with root, data, br and git (unused).

    Returns:
        int: 0.

    Raises:
        OSError: a file cannot be read or written.
    """

    def rd(p):
        """Read a UTF-8 file without newline translation (CRLF kept).

        Args:
            p: path of the file.

        Returns:
            str: the file content.

        Raises:
            OSError: the file cannot be opened or read.
            UnicodeDecodeError: the file is not valid UTF-8.
        """
        with open(p, encoding="utf-8", newline="") as fh:
            return fh.read()

    ap.add_argument("winner")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args(argv)
    kind = "json" if a.winner.endswith(".json") else "pom"
    texts = maven.align(rd(a.winner), [rd(f) for f in a.files], kind)
    for f, t in zip(a.files, texts, strict=True):
        with open(f, "w", encoding="utf-8", newline="") as fh:
            fh.write(t)
    return 0


def _tool_version_get(ap, argv, where):
    """qs.py version-get: the versions declared in VERSION / pom.xml / package.json as JSON.

    Args:
        ap: the argument parser of the command (unused: the command takes no arguments).
        argv: the command arguments (ignored).
        where: namespace with root, data, br and git.

    Returns:
        int: 0.
    """
    print(json.dumps(maven.read_versions(where.root, where.br["version_file"])))
    return 0


def _previous_release(git, old, version):
    """The newest release older than version, from CHANGELOG.md and the git tags.

    Args:
        git: the git command line prefix.
        old: the CHANGELOG.md text.
        version: the version being released.

    Returns:
        str: the previous release version, or ''.

    Raises:
        RuntimeError: git failed.
    """
    known = [v for v in changelog.versions(old) if semver.valid(v)] + [
        semver.strip_v(t)
        for t in repofiles._git(git, "tag", "-l").split()
        if semver.valid(semver.strip_v(t))
    ]
    older = [v for v in known if semver.compare(v, version) < 0 and semver.is_release(v)]
    return max(older, key=semver.key) if older else ""


def _tool_release_notes(ap, argv, where):
    """qs.py release-notes: the Common Changelog entry of a release (stdout).

    Args:
        ap: the argument parser of the command.
        argv: the command arguments.
        where: namespace with root, data, br and git.

    Returns:
        int: 0. With --write the entry is merged into the changelog file.

    Raises:
        RuntimeError: git failed.
    """
    br, git = where.br, where.git
    for opt in ("--version", "--tip", "--base"):
        ap.add_argument(opt, required=opt != "--base", default="")
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    ap.add_argument("--previous", default="")
    ap.add_argument("--tag", default="")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args(argv)
    origin = repofiles._git(git, "config", "--get", "remote.origin.url").strip()
    tag_t, commit_t = repofiles.link_templates(
        origin, br.get("tag_url", ""), br.get("commit_url", "")
    )
    levels = br.get("levels") or []
    ot_rx = levels[1] if len(levels) > 1 else policy.OT_RX
    items, omitted = changelog.entries(git, a.tip, a.base, commit_t, ot_rx)
    link = tag_t.replace("{tag}", a.tag or a.version) if tag_t else ""
    block = changelog.render(a.version, a.date, items, link)
    sys.stdout.write(block)
    if omitted:
        print(
            f"[quality-suite] left out of the notes ({len(omitted)}: "
            "docs, test, ci, chore, style): "
            + "; ".join(omitted[:8])
            + (" ..." if len(omitted) > 8 else ""),
            file=sys.stderr,
        )
    cpath = os.path.join(where.root, br["changelog_file"]) if br["changelog_file"] else ""
    old = read_text(cpath) if cpath and os.path.isfile(cpath) else ""
    prev = a.previous or _previous_release(git, old, a.version)
    if prev:
        w = semver.needed_bump(
            prev,
            a.version,
            any(e["breaking"] for e in items),
            any(e["group"] == "Added" for e in items),
        )
        if w:
            print(f"[quality-suite] WARN semver: {w}", file=sys.stderr)
    if a.write and cpath:
        new = changelog.merge(old, a.version, block, link)
        if new != old:
            with open(cpath, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(new)
            print(f"[quality-suite] written: {br['changelog_file']}", file=sys.stderr)
    return 0


def _tool_release_docs(ap, argv, where):
    """qs.py release-docs: the README version badge and CITATION.cff of a release.

    Args:
        ap: the argument parser of the command.
        argv: the command arguments.
        where: namespace with root, data, br and git.

    Returns:
        int: 0. The changed files are printed.

    Raises:
        OSError: a file cannot be read or written.
    """
    ap.add_argument("--version", required=True)
    ap.add_argument("--date", default=datetime.date.today().isoformat())
    a = ap.parse_args(argv)
    changed = []
    for rel, fn in (
        (where.br["readme_file"], lambda t: changelog.set_badge(t, a.version)),
        ("CITATION.cff", lambda t: changelog.set_citation(t, a.version, a.date)),
    ):
        p = os.path.join(where.root, rel) if rel else ""
        if not p or not os.path.isfile(p):
            continue
        with open(p, encoding="utf-8", newline="") as fh:
            old = fh.read()
        new = fn(old)
        if new != old:
            with open(p, "w", encoding="utf-8", newline="") as fh:
                fh.write(new)
            changed.append(rel)
    print("\n".join(changed))
    return 0


def _tool_repo_files(ap, argv, where):
    """qs.py repo-files: create the missing standard repository files.

    Args:
        ap: the argument parser of the command.
        argv: the command arguments.
        where: namespace with root, data, br and git.

    Returns:
        int: 0, or 2 for --force without names.
    """
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry-run", "-n", action="store_true")
    ap.add_argument("names", nargs="*")
    a = ap.parse_args(argv)
    if a.force and not a.names:
        print(
            "--force regenerates the files you name: git repo-files --force CONTRIBUTORS.md",
            file=sys.stderr,
        )
        return 2
    res = repofiles.generate(where.root, where.git, where.data, a.names or None, a.force, a.dry_run)
    for name, what in res:
        mark = "+" if what in ("created", "would create") or what.startswith("regenerated") else "="
        print(f"  {mark} {name:20s} {what}")
    return 0


TOOL_COMMANDS = {
    "version-set": _tool_version_set,
    "version-get": _tool_version_get,
    "version-align": _tool_version_align,
    "release-notes": _tool_release_notes,
    "release-docs": _tool_release_docs,
    "repo-files": _tool_repo_files,
}


def tool_main(cmd, argv):
    """Commands that edit repository files for the git aliases (np, release, repo-files).

    Args:
        cmd: the command name (a key of TOOL_COMMANDS).
        argv: its arguments.

    Returns:
        int: the exit status of the command; 2 for an unknown command.
    """
    root = os.path.abspath(env("QS_ROOT", os.getcwd()))
    rules_path = env("QS_RULES", os.path.join(root, ".quality-rules.json"))
    try:
        data = rules.load(rules_path) if os.path.exists(rules_path) else {}
    except (OSError, ValueError):
        data = {}
    handler = TOOL_COMMANDS.get(cmd)
    if handler is None:
        return 2
    where = types.SimpleNamespace(
        root=root, data=data, br=policy.get(data, "branches"), git=gitcmd(root)
    )
    return handler(argparse.ArgumentParser(prog=f"qs.py {cmd}"), argv, where)


def _policy_cmd(app):
    """qs.py policy: the commit/branch policy as shell KEY='value' lines.

    Args:
        app: the App (its rules_path is read; an unreadable file gives the defaults).

    Returns:
        int: 0.
    """
    try:
        data = rules.load(app.rules_path) if os.path.exists(app.rules_path) else None
    except (OSError, ValueError):
        data = None
    sys.stdout.write(policy.shell_env(data or {}))
    return 0


def _langs_cmd(app, files):
    """qs.py langs: language ids, 'lang/subtype' and 'tool:<id>' tokens for the installer.

    why: "lang/subtype" tokens let the installer add subtype tools only when needed, and
    opt-in tools are installed only once the rules file enables them.

    Args:
        app: the App.
        files: the paths.

    Returns:
        int: 0. The tokens are printed, space separated.
    """
    try:
        app.data = (
            rules.load(app.rules_path) if os.path.exists(app.rules_path) else None
        ) or rules.skeleton("")
    except (OSError, ValueError):
        app.data = rules.skeleton("")
    toks = set()
    for lang, subtypes in app.detect_languages(files).items():
        toks.add(lang)
        toks.update(f"{lang}/{s}" for s in subtypes)
    for lid in {t.split("/")[0] for t in toks}:
        for tid in app.reg.tools_for(
            lid, [t.split("/", 1)[1] for t in toks if t.startswith(lid + "/")]
        ):
            tool = app.reg.tools.get(tid) or {}
            if tool.get("default_enabled", True) or not tool.get("install"):
                continue
            if rules.tool_settings(app.data, lid, tid, tool["role"])["enabled"]:
                toks.add(f"tool:{tid}")
    print(" ".join(sorted(toks)))
    return 0


def main(argv):
    """Entry point: dispatch a qs.py command.

    Args:
        argv: the command line without the program name.

    Returns:
        int: the exit status.
    """
    if argv and argv[0] in TOOL_COMMANDS:
        return tool_main(argv[0], argv[1:])
    cmd = (
        argv[0]
        if argv and argv[0] in ("run", "explain", "langs", "sync", "ask", "policy", "encoding")
        else "run"
    )
    files = argv[1:] if argv and argv[0] == cmd else argv
    fix = "--fix" in files
    files = [f for f in files if f != "--fix"]
    if not files and os.environ.get("QS_FILES_FROM"):
        # why: thousands of paths do not fit a Windows command line (32K); the hook passes a list
        files = read_list(os.environ["QS_FILES_FROM"])
    app = App()
    handlers = {
        "explain": lambda: app.explain(files),
        "ask": lambda: app.ask(files),
        "encoding": lambda: app.encoding_cmd(files, fix),
        "policy": lambda: _policy_cmd(app),
        "langs": lambda: _langs_cmd(app, files),
    }
    try:
        if cmd in handlers:
            return handlers[cmd]()
        return app.run(files, sync_only=(cmd == "sync"))
    finally:
        shutil.rmtree(app.tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
