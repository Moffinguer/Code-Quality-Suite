#!/usr/bin/env python3
"""qs - code-quality-suite engine.

  qs.py [run] <files...>   classify, sync rules, generate configs, run pipelines
  qs.py explain <files...> show classification and planned tools (no changes)
  qs.py langs <files...>   print detected language ids (space separated)
  qs.py sync <files...>    only create/populate/diff the rules file
  qs.py ask <files...>     TSV of new languages whose version must be asked (lang, env, default, label)
  qs.py policy             commit/branch policy as shell KEY='value' lines (for the host hooks)
  qs.py encoding [--fix] <files...>  encoding and mojibake report; --fix repairs the files in place
  qs.py version-set <v> [--pom update|snapshot|check|off]   VERSION, pom.xml modules, package.json
  qs.py version-get        versions declared in VERSION / pom.xml / package.json (JSON)
  qs.py version-align WINNER FILE...   give FILEs the version of WINNER (pom.xml / package.json merge driver)
  qs.py release-notes --version V --tip REV --base REV [--date D] [--previous V] [--write]
                           Common Changelog entry of a release (stdout); --write merges it into CHANGELOG.md
  qs.py release-docs --version V [--date D]   README version badge and CITATION.cff
  qs.py repo-files [--force] [--dry-run] [NAME...]   create the missing standard repository files

Env: QUALITY_MODE fix|check, QUALITY_LEVEL, QS_ROOT, QS_STATE, QS_RULES, QS_PERSIST=1,
     QS_EXEC_FILES (file listing executable paths), QUALITY_LOG_LEVEL/FORMAT/FILE.
"""
import concurrent.futures as cf
import datetime
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import policy as P      # noqa: E402
import qslog            # noqa: E402
import registry as R    # noqa: E402
import rules as RU      # noqa: E402
import runner           # noqa: E402
import versions as V    # noqa: E402
import builtin          # noqa: E402
import writers as W     # noqa: E402

SUITE = os.path.dirname(HERE)


def env(name, default):
    return os.environ.get(name) or default


def load_runtime_env(path="/opt/qs/runtime.env"):
    """PATH and variables of the runtimes installed in the image (written by qs-install)."""
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        return
    for line in lines:
        k, _, v = line.partition("=")
        if k == "PATH_PREPEND" and v:
            os.environ["PATH"] = v + ":" + os.environ.get("PATH", "")
        elif k and k not in os.environ:
            os.environ[k] = v


class App:
    def __init__(self):
        load_runtime_env(os.environ.get("QS_RUNTIME_ENV", "/opt/qs/runtime.env"))
        self.root = os.path.abspath(env("QS_ROOT", os.getcwd()))
        self.mode = env("QUALITY_MODE", "fix")
        self.state = env("QS_STATE", "/qs-state" if os.path.isdir("/qs-state") else "")
        self.persist = os.environ.get("QS_PERSIST") == "1" and self.mode == "fix"
        self.rules_path = env("QS_RULES", os.path.join(self.root, ".quality-rules.json"))
        self.config_dir = env("QS_CONFIG", os.path.join(SUITE, "config"))
        self.npm_dir = env("QS_NPM", "/opt/npm")
        self.reg = R.Registry(env("QS_REGISTRY", os.path.join(SUITE, "registry", "registry.json")))
        RU.bind(self.reg)
        self.tmp = tempfile.mkdtemp(prefix="qs-")
        if self.state and not os.environ.get("QUALITY_LOG_FILE") and os.access(self.state, os.W_OK):
            os.environ["QUALITY_LOG_FILE"] = os.path.join(self.state, "quality-suite.log")
        self.data = None
        self.exit = 0

    # ---------- rules file ----------
    def load_rules(self):
        schema_ref = env("QS_SCHEMA_REF", os.path.join(SUITE, "schema", "quality-rules.schema.json"))
        created = False
        try:
            self.data = RU.load(self.rules_path) if os.path.exists(self.rules_path) else None
        except json.JSONDecodeError as e:
            qslog.log("ERROR", "rules", f"invalid JSON at line {e.lineno} col {e.colno}: {e.msg}",
                      os.path.basename(self.rules_path), "load", "ERROR")
            return False
        if self.data is None:
            self.data = RU.skeleton(schema_ref)
            created = True
        errors, warnings = RU.validate(self.data, self.reg)
        for w in warnings:
            qslog.log("WARN", "rules", w, os.path.basename(self.rules_path), "validate", "WARN")
        for e in errors:
            qslog.log("ERROR", "rules", e, os.path.basename(self.rules_path), "validate", "ERROR")
        if errors:
            return False
        self._loaded = json.loads(json.dumps(self.data))
        self._created = created
        return True

    def sync_rules(self, langs, versions):
        changed_by_suite = []
        added = P.populate(self.data)
        if added and not getattr(self, "_created", False):
            changed_by_suite.append("policy")
            qslog.log("INFO", "rules", f"added policy defaults: {', '.join(added)}",
                      os.path.basename(self.rules_path), "populate", "SUCCESS")
        if RU.populate_global(self.data, self.reg):
            changed_by_suite.append("global")
        for lid in sorted(langs):
            lang = self.reg.languages[lid]
            env_v = os.environ.get((lang.get("version") or {}).get("env") or "_none_")
            if RU.populate_language(self.data, self.reg, lid, versions.get(lid), env_v):
                changed_by_suite.append(lid)
                qslog.log("INFO", "rules", f"added language '{lid}' with base rules"
                          + (f" (version pinned from env {lang['version']['env']}={env_v})" if env_v else ""),
                          os.path.basename(self.rules_path), "populate", "SUCCESS")
            sec = self.data["languages"].get(lid, {})
            v, src = versions.get(lid, (None, None))
            if sec.get("version", "auto") == "auto" and v and src not in ("rules",):
                det = f"{v} ({src})"
                if sec.get("detected_version") != det:
                    sec["detected_version"] = det
                    changed_by_suite.append(f"{lid}.detected_version")
        if self.persist and (self.data != self._loaded or getattr(self, "_created", False)):
            RU.save(self.rules_path, self.data)
            if getattr(self, "_created", False):
                qslog.log("INFO", "rules", "created rules file (languages are added as they are detected)",
                          os.path.basename(self.rules_path), "create", "SUCCESS")
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
        path = os.path.join(self.state, "tests.txt")
        text = "".join(l + "\n" for l in lines)
        try:
            if not os.path.exists(path) or open(path, encoding="utf-8").read() != text:
                with open(path, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(text)
        except OSError:
            pass

    def export_policy(self):
        """Commit/branch policy for the host hooks: <state>/policy.env (shell syntax)."""
        if not self.state or not os.access(self.state, os.W_OK):
            return
        path, text = os.path.join(self.state, "policy.env"), P.shell_env(self.data)
        try:
            if not os.path.exists(path) or open(path, encoding="utf-8").read() != text:
                with open(path, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(text)
        except OSError:
            pass

    def encoding_gate(self, cls):
        """Check every text file against the encoding policy before any tool touches it.

        Returns (StepResult or None, failed paths, {path: charset} of files to protect).
        Also fills self.enc_errors / self.enc_warnings ({path: [lines]}) for the console.
        why: formatters assume UTF-8; running them on a file in another charset corrupts accents.
        """
        enc = P.get(self.data, "encoding")
        self.enc_errors, self.enc_warnings = {}, {}
        if not enc.get("enabled", True):
            return None, set(), {}
        res = runner.StepResult("qs-encoding", "syntax")
        failed, protect, texts = set(), {}, {}
        mode = enc.get("mojibake", "block")
        for c in cls:
            if c.binary or c.reason in ("excluded", "not a regular file"):
                continue
            ap = os.path.join(self.root, c.path)
            try:
                raw = open(ap, "rb").read()
            except OSError:
                continue
            cs, bom = P.expected(enc, c.path, c.lang)
            probs = P.check(raw, cs, bom)
            if probs:
                failed.add(c.path)
                self.enc_errors[c.path] = probs
                continue
            if P.needs_protection(raw, cs):
                protect[c.path] = cs
            if cs == "utf-8" and mode != "off" and \
                    not any(P.glob_match(c.path, g) for g in enc.get("mojibake_ignore") or []):
                text = (raw[3:] if raw.startswith(P.BOM_UTF8) else raw).decode("utf-8")
                if "?" in text or any(ord(ch) >= 0x80 for ch in text):
                    texts[c.path] = text
        # why: the previous version tells new damage from old, and gives back accents turned into '?'
        olds = old_blobs(self.root, os.environ.get("QS_BASE_REV", ""), sorted(texts))
        rev = os.environ.get("QS_BASE_REV", "")
        for path, text in sorted(texts.items()):
            errs, warns = P.mojibake(text, P.decode_any(olds.get(path)))
            if mode == "warn":
                errs, warns = [], errs + warns
            if errs:
                failed.add(path)
                self.enc_errors[path] = [P.describe(f) for f in errs]
            if warns:
                self.enc_warnings[path] = [P.describe(f) + (f" [already in {rev}]" if f in warns and rev and
                                                            mode != "warn" else "") for f in warns]
        for c in cls:
            if c.path in failed:
                res.status[c.path] = "ERROR"
                res.output += [f"{c.path}: {x}" for x in self.enc_errors[c.path]]
            elif not (c.binary or c.reason in ("excluded", "not a regular file")) and \
                    os.path.isfile(os.path.join(self.root, c.path)):
                res.status[c.path] = "SUCCESS"
        for path, lines in sorted(self.enc_warnings.items()):
            for x in lines:
                qslog.log("WARN", "encoding", x, path, "mojibake", "WARN", console=False)
        return (res if res.status else None), failed, protect

    def encoding_report(self, stopped=True):
        """Console block listing every file with an encoding problem (and the warnings)."""
        n = len(self.enc_errors)
        if n:
            tail = " Nothing was formatted or analysed." if stopped else ""
            print(f"[quality-suite] ENCODING: {n} file(s) with encoding problems.{tail}", flush=True)
            for path in sorted(self.enc_errors):
                print(f"[quality-suite]   {path}")
                for x in self.enc_errors[path][:8]:
                    print(f"[quality-suite]       {x}")
                if len(self.enc_errors[path]) > 8:
                    print(f"[quality-suite]       ... {len(self.enc_errors[path]) - 8} more")
                qslog.log("ERROR", "encoding", "; ".join(self.enc_errors[path][:3]), path, "check", "ERROR",
                          console=False)
            print("[quality-suite] Repair: git encoding --fix <file>   (or reopen it in VS Code with the right "
                  "encoding, then 'Save with Encoding' -> UTF-8)", flush=True)
            print("[quality-suite] Guide: docs/QUALITY-RULES.md, section 'Encoding'", flush=True)
        for path in sorted(self.enc_warnings):
            for x in self.enc_warnings[path][:3]:
                print(f"[quality-suite] WARN encoding {path}: {x}", flush=True)

    def encoding_cmd(self, files, fix=False):
        """qs.py encoding [--fix]: report (and repair) the encoding of the given files."""
        if not self.load_rules():
            return 2
        P.populate(self.data)
        cls = self.classify(files)
        self.encoding_gate(cls)
        if fix:
            enc = P.get(self.data, "encoding")
            targets = [c for c in cls if not c.binary and c.reason not in ("excluded", "not a regular file")
                       and os.path.isfile(os.path.join(self.root, c.path))]
            olds = old_blobs(self.root, os.environ.get("QS_BASE_REV", ""), [c.path for c in targets])
            for c in targets:
                cs, bom = P.expected(enc, c.path, c.lang)
                ap = os.path.join(self.root, c.path)
                raw = open(ap, "rb").read()
                if cs != "utf-8":
                    if c.path in self.enc_errors:
                        print(f"[quality-suite] {c.path}: must be {cs.upper()}; not repaired automatically "
                              f"(see the message above)")
                    continue
                new, notes, left = P.repair(raw, olds.get(c.path))
                if bom == "forbid" and new.startswith(P.BOM_UTF8):
                    new, notes = new[3:], notes + ["BOM removed"]
                if new != raw:
                    with open(ap, "wb") as fh:
                        fh.write(new)
                    print(f"[quality-suite] repaired {c.path}: {'; '.join(notes)}")
                for x in left:
                    print(f"[quality-suite] {c.path}: NOT repaired, fix it by hand: {x}")
            self.encoding_gate(cls)
        self.encoding_report(stopped=False)
        if not self.enc_errors:
            print(f"[quality-suite] encoding OK: {len([c for c in cls if not c.binary])} file(s) checked", flush=True)
        return 1 if self.enc_errors else 0

    def snapshot_diff(self):
        if not self.state:
            return []
        snap = os.path.join(self.state, "rules.applied.json")
        try:
            old = json.load(open(snap, encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            old = None
        changes = RU.diff(old or {}, self.data) if old is not None else []
        for path, a, b in changes:
            kind = "added" if a is None else "removed" if b is None else "modified"
            qslog.log("INFO", "rules", f"{kind} {path}: {RU.short(a)} -> {RU.short(b)}",
                      os.path.basename(self.rules_path), "change", "SUCCESS")
        if self.persist and (old is None or changes) and os.access(self.state, os.W_OK):
            with open(snap, "w", encoding="utf-8") as fh:
                json.dump(self.data, fh, indent=2, ensure_ascii=False)
            if old is None:
                qslog.log("INFO", "rules", "baseline snapshot recorded", os.path.basename(self.rules_path),
                          "snapshot", "SUCCESS")
        return changes

    # ---------- configs ----------
    def tool_rules(self, lid, tid, version, seen=()):
        """Rules for a tool: inherited tool's rules (shared config) + own rules + version-derived values."""
        tool = self.reg.tools[tid]
        own = RU.tool_settings(self.data, lid, tid, tool["role"])["rules"]
        parent = (tool.get("config") or {}).get("inherit")
        merged = {}
        if parent and parent in self.reg.tools and parent not in seen:
            merged = self.tool_rules(lid, parent, version, seen + (tid,))
        merged = W.deep_merge(merged, own)
        return runner.effective_rules(tool, merged, version)

    def generate_configs(self, pairs, out_dir, vers=None):
        """pairs: iterable of (lang_id, tool_id). Returns ({(lid, tid): path}, ok)."""
        paths, ok = {}, True
        vers = vers or {}
        for lid, tid in sorted(set(pairs)):
            tool = self.reg.tools[tid]
            cfg = tool.get("config")
            if not cfg or not cfg.get("format"):
                continue  # why: {"inherit": ...} only shares rules (rendered as flags), no file to write
            rules = self.tool_rules(lid, tid, (vers.get(lid) or (None,))[0])
            base_rel = cfg.get("base")
            base_abs, base_text = None, None
            if base_rel:
                base_abs = base_rel.replace("{npm}", self.npm_dir).replace("{config}", self.config_dir)
                if not os.path.isabs(base_abs):
                    base_abs = os.path.join(self.config_dir, base_abs)
                try:
                    base_text = open(base_abs, encoding="utf-8").read()
                except OSError:
                    base_text = None
            if base_text is None and not rules and cfg.get("format") not in ("eslint", "php-cs-fixer"):
                if base_abs and os.path.exists(base_abs):
                    paths[(lid, tid)] = base_abs
                continue
            try:
                text = W.build(dict(cfg, base_abs=base_abs), base_text, rules)
            except Exception as e:  # why: a broken rule must block with a clear message, not run unconfigured
                qslog.log("ERROR", "rules", f"cannot generate config for '{lid}.{tid}': {e}", cfg.get("file", ""),
                          "generate", "ERROR")
                ok = False
                continue
            dst = os.path.join(out_dir, lid, tid, cfg["file"])
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
            paths[(lid, tid)] = dst
        return paths, ok

    def all_rule_tools(self):
        out = set()
        for lid, sec in (self.data.get("languages") or {}).items():
            if lid not in self.reg.languages:
                continue
            for cat in RU.CATEGORIES:
                for tid in (sec.get(cat) or {}):
                    if tid in self.reg.tools:
                        out.add((lid, tid))
        for tid in (self.data.get("global") or {}):
            if tid in self.reg.tools:
                out.add(("_global", tid))
        return out

    # ---------- main ----------
    def classify(self, files):
        excludes = list(self.reg.default_excludes) + list((self.data or {}).get("exclude", [])) + \
            [os.path.basename(self.rules_path)]
        extra = {}
        for lid, sec in ((self.data or {}).get("languages") or {}).items():
            for e in sec.get("extensions", []) or []:
                extra[e] = lid
        return R.classify(self.reg, self.root, files, excludes, extra)

    def run(self, files, sync_only=False):
        if not self.load_rules():
            return 2
        cls = self.classify(files)
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
                    qslog.log("WARN", c.lang, "ambiguous extension resolved by guess; add a modeline to pin it",
                              c.path, "classify", "WARN")
        vers = {lid: V.resolve(self.reg.languages[lid], (self.data.get("languages") or {}).get(lid), self.root)
                for lid in by_lang}
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
        if enc_failed:
            # why: a file in the wrong encoding is reported once, and no tool rewrites it
            for lid in list(by_lang):
                by_lang[lid] = [f for f in by_lang[lid] if f not in enc_failed]
                if not by_lang[lid]:
                    del by_lang[lid]
        changes = self.snapshot_diff()
        if self.persist and changes and self.state and os.access(self.state, os.W_OK):
            gen_dir = os.path.join(self.state, "generated")
            shutil.rmtree(gen_dir, ignore_errors=True)
            _, gok = self.generate_configs(self.all_rule_tools(), gen_dir, vers)
            qslog.log("INFO" if gok else "ERROR", "rules",
                      f"{len(changes)} change(s) applied; native configs regenerated in .git/quality-suite/generated",
                      os.path.basename(self.rules_path), "apply", "SUCCESS" if gok else "ERROR")
        if sync_only:
            return 0
        exec_files = set()
        if os.environ.get("QS_EXEC_FILES") and os.path.exists(os.environ["QS_EXEC_FILES"]):
            exec_files = set(open(os.environ["QS_EXEC_FILES"], encoding="utf-8").read().split("\n"))
        plans, pairs = {}, set()
        for lid, lfiles in sorted(by_lang.items()):
            steps, lvl = runner.plan(self.reg, self.data, lid, lfiles, subtypes, os.environ.get("QUALITY_LEVEL"), RU)
            plans[lid] = (steps, lvl)
            pairs |= {(lid, t["id"]) for t, _, _ in steps}
        gfiles = [c.path for c in cls if not c.binary and os.path.isfile(os.path.join(self.root, c.path))
                  and c.reason != "excluded"]
        gfiles = [f for f in gfiles if f not in enc_failed]
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
        ctx = runner.Ctx(self.root, self.mode, self.tmp, cfg_paths, exec_files, ambiguous)
        ctx.protect = protect
        ctx.policy = self.data
        enc = P.get(self.data, "encoding")
        ctx.charsets = {lid: P.expected(enc, "", lid)[0].upper().replace("WINDOWS-", "windows-") for lid in plans}
        builtin.CHARSET_OF = {os.path.join(self.root, f): cs for f, cs in protect.items()}
        qslog.log("INFO", "engine", f"run start mode={self.mode} files={len(files)} languages={len(plans)}",
                  action="run", status="SUCCESS")
        jobs = {}
        with cf.ThreadPoolExecutor(max_workers=max(2, os.cpu_count() or 2)) as ex:
            for lid, (steps, lvl) in plans.items():
                jobs[ex.submit(runner.run_language, self.reg, lid, steps, ctx, vers[lid][0])] = lid
            if gsteps and self.mode != "fix":
                jobs[ex.submit(self._run_global, gsteps, ctx)] = "_global"
            done = {}
            for fut in cf.as_completed(jobs):
                lid = jobs[fut]
                try:
                    done[lid] = fut.result()
                except Exception as e:  # why: one broken tool definition must not hide every other result
                    import traceback
                    qslog.log("ERROR", lid, f"internal error: {e!r}; see the log for the traceback",
                              action="run", status="ERROR")
                    qslog.log("DEBUG", lid, traceback.format_exc(), action="run", status="ERROR")
                    err = runner.StepResult("engine", "syntax")
                    err.status = {f: "ERROR" for f in (by_lang.get(lid) or [])}
                    err.output = [f"internal error in the {lid} pipeline: {e!r}"]
                    done[lid] = [err]
            if gsteps and self.mode == "fix":
                # why: formatters rewrite files in place; repository checks must read the final content
                done["_global"] = self._run_global(gsteps, ctx)
        if enc_res and (enc_failed or os.environ.get("QUALITY_LOG_LEVEL") == "DEBUG" or "_global" in done):
            done["_global"] = [enc_res] + done.get("_global", [])
        glevel = os.environ.get("QUALITY_LEVEL") or self.data.get("level", "standard")
        for lid in [l for l in sorted(plans) if l in done] + (["_global"] if "_global" in done else []):
            self._report(lid, done[lid], plans.get(lid, ([], glevel))[1], vers.get(lid), by_lang.get(lid, gfiles))
        status = "ERROR" if self.exit else "SUCCESS"
        qslog.log("ERROR" if self.exit else "INFO", "engine", f"run end status={status}", action="run", status=status)
        return self.exit

    def _global_steps(self, files):
        steps = []
        lvl = os.environ.get("QUALITY_LEVEL") or self.data.get("level", "standard")
        for tid in self.reg.global_tools:
            tool = self.reg.tools.get(tid)
            if not tool:
                continue
            st = RU.tool_settings(self.data, "_global", tid, tool["role"])
            tlevel = st.get("level") or tool.get("level") or R.ROLE_LEVEL[tool["role"]]
            if not st["enabled"] or R.level_rank(lvl) < R.level_rank(tlevel) or not runner.available(tool):
                continue
            req = (tool.get("requires") or {}).get("any_file")
            if req and not any(os.path.exists(os.path.join(self.root, r)) for r in req):
                continue
            steps.append((tool, st, files))
        return steps

    def _run_global(self, steps, ctx):
        return [runner.run_tool(t, st, None, ctx, files, None, "_global") for t, st, files in steps if files]

    def _report(self, lid, results, lvl, ver, files):
        name = self.reg.languages[lid]["name"] if lid in self.reg.languages else "Repository checks"
        vtxt = f", version={ver[0]} ({ver[1]})" if ver and ver[0] else ""
        print(f"[quality-suite] {name}: {len(files)} file(s) (level={lvl or 'standard'}{vtxt})", flush=True)
        for r in results:
            # why: successful steps stay quiet (fix chatter is noise); the log file keeps the per-file result
            if any(st == "ERROR" for st in r.status.values()) or os.environ.get("QUALITY_LOG_LEVEL") == "DEBUG":
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
        if not self.load_rules():
            return 2
        for c in self.classify(files):
            if c.skip:
                print(f"{c.path}: skipped ({c.reason})")
                continue
            steps, lvl = runner.plan(self.reg, self.data, c.lang, [c.path], {c.path: c.subtypes},
                                     os.environ.get("QUALITY_LEVEL"), RU, quiet=True)
            v = V.resolve(self.reg.languages[c.lang], (self.data.get("languages") or {}).get(c.lang), self.root)
            sub = f" +{','.join(c.subtypes)}" if c.subtypes else ""
            vtxt = f", version={v[0]} via {v[1]}" if v[0] else ""
            print(f"{c.path}: {c.lang}{sub} (level={lvl}{vtxt}, charset={c.charset or '?'}"
                  f"{'' if c.confident else ', GUESSED'})")
            for t, st, _ in steps:
                print(f"    {t['role']:<7} {t['id']}")
        return 0


    def ask(self, files):
        """Languages new to the rules file whose version could not be detected (host prompts once)."""
        try:
            data = RU.load(self.rules_path) if os.path.exists(self.rules_path) else None
        except (OSError, json.JSONDecodeError):
            data = None
        self.data = data or RU.skeleton("")
        known = set((self.data.get("languages") or {}).keys())
        for lid in sorted({c.lang for c in self.classify(files) if not c.skip} - known):
            spec = self.reg.languages[lid].get("version")
            if not spec or not spec.get("ask", True):
                continue
            v, src = V.resolve(self.reg.languages[lid], None, self.root)
            if src == "default":
                print("\t".join([lid, spec.get("env") or "-", str(spec.get("default") or "-"),
                                  spec.get("label", f"{self.reg.languages[lid]['name']} version")]))
        return 0


def old_blobs(root, rev, paths):
    """{path: bytes} of the given paths at revision rev, read by one 'git cat-file --batch'.

    QS_GIT_DIR (the repository's object store mounted read-only by the hooks) is used when set.
    Paths missing at rev (new files) are left out; any git failure gives {} (first commit, no
    git): the checks then treat every finding as new.
    """
    paths = [p for p in paths if "\n" not in p]
    if not rev or not paths:
        return {}
    gd = os.environ.get("QS_GIT_DIR")
    git = ["git", f"--git-dir={gd}"] if gd else ["git", "-C", root]
    try:
        proc = subprocess.run(git + ["cat-file", "--batch"], capture_output=True, timeout=120,
                              input="".join(f"{rev}:{p}\n" for p in paths).encode("utf-8"))
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
            out[path] = data[i:i + size]
            i += size + 1
    return out


def read_list(path):
    """File list written by the hooks: NUL-separated (git -z) or one path per line."""
    with open(path, "rb") as fh:
        raw = fh.read().decode("utf-8", "surrogateescape")
    items = raw.split("\0") if "\0" in raw else raw.splitlines()
    return [x for x in items if x]


def gitcmd(root):
    """git command for the repository: the object store mounted by the hooks, else the work tree."""
    gd = os.environ.get("QS_GIT_DIR")
    return ["git", f"--git-dir={gd}"] if gd else ["git", "-C", root]


def tool_main(cmd, argv):
    """Commands that edit repository files for the git aliases (np, release, repo-files)."""
    import argparse
    import changelog as CL
    import maven as MV
    import repofiles as RF
    import semver as SV
    root = os.path.abspath(env("QS_ROOT", os.getcwd()))
    rules = env("QS_RULES", os.path.join(root, ".quality-rules.json"))
    try:
        data = RU.load(rules) if os.path.exists(rules) else {}
    except (OSError, ValueError):
        data = {}
    br = P.get(data, "branches")
    git = gitcmd(root)
    ap = argparse.ArgumentParser(prog=f"qs.py {cmd}")
    if cmd == "version-set":
        ap.add_argument("version")
        ap.add_argument("--pom", default=br["pom_version"], choices=("update", "snapshot", "check", "off"))
        ap.add_argument("--version-file", default=br["version_file"])
        a = ap.parse_args(argv)
        if not SV.valid(a.version):
            print(f"'{a.version}' is not a semantic version", file=sys.stderr)
            return 2
        changed, notes = MV.set_versions(root, a.version, a.version_file, pom=False)
        pv = MV.read_versions(root, "").get("pom.xml")
        if a.pom in ("update", "snapshot") and pv is not None:
            want = a.version + ("-SNAPSHOT" if a.pom == "snapshot" and not a.version.endswith("-SNAPSHOT") else "")
            c, n = MV.set_poms(root, want)
            changed, notes = changed + c, notes + n
        elif a.pom == "check" and pv and pv not in (a.version, a.version + "-SNAPSHOT"):
            notes.append(f"pom.xml has {pv}; set it: mvn versions:set -DnewVersion={a.version} "
                         f"-DgenerateBackupPoms=false")
        changed += MV.set_package_json(root, a.version)
        for n in notes:
            print(f"[quality-suite] {n}", file=sys.stderr)
        print("\n".join(changed))
        return 0
    if cmd == "version-align":
        ap.add_argument("winner")
        ap.add_argument("files", nargs="+")
        a = ap.parse_args(argv)
        kind = "json" if a.winner.endswith(".json") else "pom"

        def rd(p):
            with open(p, encoding="utf-8", newline="") as fh:
                return fh.read()
        texts = MV.align(rd(a.winner), [rd(f) for f in a.files], kind)
        for f, t in zip(a.files, texts):
            with open(f, "w", encoding="utf-8", newline="") as fh:
                fh.write(t)
        return 0
    if cmd == "version-get":
        print(json.dumps(MV.read_versions(root, br["version_file"])))
        return 0
    if cmd == "release-notes":
        for opt in ("--version", "--tip", "--base"):
            ap.add_argument(opt, required=opt != "--base", default="")
        ap.add_argument("--date", default=datetime.date.today().isoformat())
        ap.add_argument("--previous", default="")
        ap.add_argument("--tag", default="")
        ap.add_argument("--write", action="store_true")
        a = ap.parse_args(argv)
        origin = RF._git(git, "config", "--get", "remote.origin.url").strip()
        tag_t, commit_t = RF.link_templates(origin, br.get("tag_url", ""), br.get("commit_url", ""))
        levels = br.get("levels") or []
        items, omitted = CL.entries(git, a.tip, a.base, commit_t, levels[1] if len(levels) > 1 else r"^[0-9]+$")
        link = tag_t.replace("{tag}", a.tag or a.version) if tag_t else ""
        block = CL.render(a.version, a.date, items, link)
        sys.stdout.write(block)
        if omitted:
            print(f"[quality-suite] left out of the notes ({len(omitted)}: docs, test, ci, chore, style): "
                  + "; ".join(omitted[:8]) + (" ..." if len(omitted) > 8 else ""), file=sys.stderr)
        cpath = os.path.join(root, br["changelog_file"]) if br["changelog_file"] else ""
        old = open(cpath, encoding="utf-8").read() if cpath and os.path.isfile(cpath) else ""
        prev = a.previous
        if not prev:
            known = [v for v in CL.versions(old) if SV.valid(v)] + \
                [SV.strip_v(t) for t in RF._git(git, "tag", "-l").split() if SV.valid(SV.strip_v(t))]
            older = [v for v in known if SV.compare(v, a.version) < 0 and SV.is_release(v)]
            prev = max(older, key=SV.key) if older else ""
        if prev:
            w = SV.needed_bump(prev, a.version, any(e["breaking"] for e in items),
                               any(e["group"] == "Added" for e in items))
            if w:
                print(f"[quality-suite] WARN semver: {w}", file=sys.stderr)
        if a.write and cpath:
            new = CL.merge(old, a.version, block, link)
            if new != old:
                with open(cpath, "w", encoding="utf-8", newline="\n") as fh:
                    fh.write(new)
                print(f"[quality-suite] written: {br['changelog_file']}", file=sys.stderr)
        return 0
    if cmd == "release-docs":
        ap.add_argument("--version", required=True)
        ap.add_argument("--date", default=datetime.date.today().isoformat())
        a = ap.parse_args(argv)
        changed = []
        for rel, fn in ((br["readme_file"], lambda t: CL.set_badge(t, a.version)),
                        ("CITATION.cff", lambda t: CL.set_citation(t, a.version, a.date))):
            p = os.path.join(root, rel) if rel else ""
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
    if cmd == "repo-files":
        ap.add_argument("--force", action="store_true")
        ap.add_argument("--dry-run", "-n", action="store_true")
        ap.add_argument("names", nargs="*")
        a = ap.parse_args(argv)
        if a.force and not a.names:
            print("--force regenerates the files you name: git repo-files --force CONTRIBUTORS.md", file=sys.stderr)
            return 2
        res = RF.generate(root, git, data, a.names or None, a.force, a.dry_run)
        for name, what in res:
            print(f"  {'+' if what in ('created', 'would create') or what.startswith('regenerated') else '='} "
                  f"{name:20s} {what}")
        return 0
    return 2


def main(argv):
    if argv and argv[0] in ("version-set", "version-get", "version-align", "release-notes", "release-docs",
                            "repo-files"):
        return tool_main(argv[0], argv[1:])
    cmd = argv[0] if argv and argv[0] in ("run", "explain", "langs", "sync", "ask", "policy", "encoding") else "run"
    files = argv[1:] if argv and argv[0] == cmd else argv
    fix = "--fix" in files
    files = [f for f in files if f != "--fix"]
    if not files and os.environ.get("QS_FILES_FROM"):
        # why: thousands of paths do not fit a Windows command line (32K); the hook passes a list file
        files = read_list(os.environ["QS_FILES_FROM"])
    app = App()
    try:
        if cmd == "explain":
            return app.explain(files)
        if cmd == "ask":
            return app.ask(files)
        if cmd == "encoding":
            return app.encoding_cmd(files, fix)
        if cmd == "policy":
            try:
                data = RU.load(app.rules_path) if os.path.exists(app.rules_path) else None
            except (OSError, ValueError):
                data = None
            sys.stdout.write(P.shell_env(data or {}))
            return 0
        if cmd == "langs":
            # why: "lang/subtype" tokens let the installer add subtype tools only when needed
            try:
                app.data = (RU.load(app.rules_path) if os.path.exists(app.rules_path) else None) or RU.skeleton("")
            except (OSError, ValueError):
                app.data = RU.skeleton("")
            toks = set()
            for c in app.classify(files):
                if not c.skip:
                    toks.add(c.lang)
                    toks.update(f"{c.lang}/{s}" for s in c.subtypes)
            # why: opt-in tools are installed only once the rules file enables them
            for lid in {t.split("/")[0] for t in toks}:
                for tid in app.reg.tools_for(lid, [t.split("/", 1)[1] for t in toks if t.startswith(lid + "/")]):
                    tool = app.reg.tools.get(tid) or {}
                    if tool.get("default_enabled", True) or not tool.get("install"):
                        continue
                    if RU.tool_settings(app.data, lid, tid, tool["role"])["enabled"]:
                        toks.add(f"tool:{tid}")
            print(" ".join(sorted(toks)))
            return 0
        return app.run(files, sync_only=(cmd == "sync"))
    finally:
        shutil.rmtree(app.tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
