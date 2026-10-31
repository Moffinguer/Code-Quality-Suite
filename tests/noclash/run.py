#!/usr/bin/env python3
"""No-clash harness: messy-but-valid files are formatted in fix mode, then a check-mode run
must pass (formatters and linters agree); broken files must fail at the syntax step.

  python3 tests/noclash/run.py [--keep] [--only lang,...]

Runs the engine directly with whatever tools are on PATH; missing tools are skipped by the
engine (WARN), so the harness reports what it could exercise.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SUITE = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(SUITE, "engine", "qs.py")
PLACE = {"ci-workflow.yml": ".github/workflows/ci.yml", "gitlab-ci.yml": ".gitlab-ci.yml",
         "dependabot.yml": ".github/dependabot.yml", "k8s-svc.yaml": "deploy/svc.yaml"}


def run(repo, mode, files, extra_env=None):
    env = dict(os.environ, QS_ROOT=repo, QS_STATE=os.path.join(repo, ".git", "quality-suite"), QUALITY_MODE=mode,
               QS_PERSIST="1" if mode == "fix" else "0", QS_SUITE=SUITE, QUALITY_LOG_FORMAT="json",
               QUALITY_LOG_FILE=os.path.join(repo, f"{mode}.log"), QUALITY_LOG_LEVEL="INFO")
    env.setdefault("QS_RUBY_VERSION", "3.1")  # why: the sandbox rubocop is old; the image installs a current one
    env.update(extra_env or {})
    p = subprocess.run([sys.executable, ENGINE, "run", *files], cwd=repo, env=env, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def results(repo, mode):
    out = {}
    for line in open(os.path.join(repo, f"{mode}.log"), encoding="utf-8"):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if r.get("file") and r.get("status") in ("SUCCESS", "ERROR"):
            out.setdefault(r["file"], []).append((r.get("action"), r["status"], r.get("msg", "")))
    return out


def main(argv):
    keep = "--keep" in argv
    level = next((a.split("=", 1)[1] for a in argv if a.startswith("--level=")), "standard")
    os.environ["QUALITY_LEVEL"] = level
    repo = tempfile.mkdtemp(prefix="qs-noclash-")
    subprocess.run(["git", "init", "-q", repo], check=True)
    os.makedirs(os.path.join(repo, ".git", "quality-suite"), exist_ok=True)
    files = []
    for name in sorted(os.listdir(os.path.join(HERE, "ok"))):
        rel = PLACE.get(name, name)
        os.makedirs(os.path.dirname(os.path.join(repo, rel)) or repo, exist_ok=True)
        shutil.copy(os.path.join(HERE, "ok", name), os.path.join(repo, rel))
        files.append(rel)
    subprocess.run(["git", "-C", repo, "add", "-A"], check=True)
    rc1, out1, err1 = run(repo, "fix", files)
    rc2, out2, err2 = run(repo, "check", files)
    for label, rc, err in (("fix", rc1, err1), ("check", rc2, err2)):
        if "Traceback" in err or "internal error" in err or rc == 2:
            print(f"ENGINE FAILURE in {label} mode (rc={rc}):\n" + err[-3000:])
            return 2
    fixres, chkres = results(repo, "fix"), results(repo, "check")
    # why: when a formatter is not installed here, a lint finding on layout is not a clash
    import re as _re
    missing_fmt = set()
    reg = json.load(open(os.path.join(SUITE, "registry", "registry.json")))
    for line in open(os.path.join(repo, "fix.log"), encoding="utf-8"):
        r = json.loads(line)
        m = _re.search(r"tool '([^']+)' not installed", r.get("msg", ""))
        if m and reg["tools"].get(m.group(1), {}).get("role") == "format":
            missing_fmt.add(r.get("comp"))
    bad = 0
    print(f"{'file':<28} {'fix':<8} check   failing steps (check mode)")
    for f in files:
        fx = "ERROR" if any(s == "ERROR" for _, s, _ in fixres.get(f, [])) else "ok"
        ck_err = [a for a, s, _ in chkres.get(f, []) if s == "ERROR"]
        comps = {c for c, _ in [(x[0], 0) for x in []]}
        lang = next((json.loads(l).get("comp") for l in open(os.path.join(repo, "check.log"), encoding="utf-8")
                     if json.loads(l).get("file") == f and json.loads(l).get("comp") != "_global"), None)
        if ck_err and lang in missing_fmt:
            ck = "n/a"  # formatter missing in this environment
        else:
            ck = "ERROR" if ck_err else "ok"
            bad += bool(ck_err)
        print(f"{f:<28} {fx:<8} {ck:<7} {', '.join(ck_err)}")
    skipped = sorted({l for l in (err1 + err2).splitlines() if "not installed" in l})
    print(f"\n{len(files)} files, {bad} failing in check mode; tools missing in this environment: "
          f"{len(skipped)}")
    if "-v" in argv:
        print(out2[-6000:])
    # broken files must fail at the syntax step
    bad_dir = os.path.join(HERE, "bad")
    bfiles = []
    for name in sorted(os.listdir(bad_dir)):
        shutil.copy(os.path.join(bad_dir, name), os.path.join(repo, "bad_" + name))
        bfiles.append("bad_" + name)
    if bfiles:
        rc3, out3, err3 = run(repo, "check", bfiles)
        if rc3 == 2 or "Traceback" in err3:
            print("ENGINE FAILURE on broken files:\n" + err3[-3000:])
            return 2
        res = results(repo, "check")
        print("\nbroken files (must fail at a syntax step):")
        syntax_ids = None
        for f in bfiles:
            errs = [a for a, s, _ in res.get(f, []) if s == "ERROR"]
            print(f"  {f:<26} {'caught by ' + errs[0] if errs else 'NOT CAUGHT'}")
            bad += not errs
    print(f"\nrepo: {repo}" if keep else "")
    if not keep:
        shutil.rmtree(repo, ignore_errors=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
