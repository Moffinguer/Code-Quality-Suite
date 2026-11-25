#!/usr/bin/env python3
"""check-versions - compare every pinned tool version with its latest stable release.

  python3 tools/check-versions.py [--only npm,pip,github] [--json] [--verify-assets]

Sources: npm registry (dist-tags.latest), PyPI JSON (info.version), GitHub tags through
`git ls-remote` (no API token, no rate limit), for github/url/jar/phar installs hosted on
GitHub. Pre-releases (alpha, beta, rc, dev, nightly, preview) are ignored. --verify-assets
checks that the pinned release assets still download (HTTP 200).

Maintenance tool for the suite maintainer: it needs network; the hooks never run it.
"""

import argparse
import concurrent.futures as cf
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRE = re.compile(r"(alpha|beta|rc|dev|nightly|preview|pre|snapshot|canary|next|insiders)", re.I)
PEP440_PRE = re.compile(r"\d(a|b|c|rc)\d*$|\.dev")
GH_URL = re.compile(r"https://github\.com/([^/]+/[^/]+)/releases/download/([^/]+)/")


def http_json(url):
    """Fetch a URL and parse its body as JSON.

    Args:
        url: absolute HTTP(S) URL to request.
    Returns:
        The decoded JSON value.
    Raises:
        urllib.error.URLError: when the request fails or times out.
        ValueError: when the body is not valid JSON.
    """
    req = urllib.request.Request(
        url, headers={"Accept": "application/json", "User-Agent": "qs-check-versions"}
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def vkey(v):
    """Sort key that orders version strings by their numeric and alphabetic parts.

    Args:
        v: version string such as "1.10.2".
    Returns:
        A list of ints and strings, comparable with other keys.
    """
    return [int(x) if x.isdigit() else x for x in re.findall(r"\d+|[A-Za-z]+", v)]


def latest_npm(name):
    """Return the latest npm dist-tag version of a package.

    Args:
        name: npm package name, scoped names allowed.
    Returns:
        The version string of the "latest" dist-tag.
    Raises:
        urllib.error.URLError: when the registry is unreachable.
        KeyError: when the registry answer has no "version" field.
    """
    return http_json(
        "https://registry.npmjs.org/" + urllib.parse.quote(name, safe="@") + "/latest"
    )["version"]


def latest_pypi(name):
    """Return the highest stable PyPI release of a package.

    Args:
        name: PyPI project name.
    Returns:
        The newest release that is not a pre-release and not yanked, or the
        current info version when no such release exists.
    Raises:
        urllib.error.URLError: when PyPI is unreachable.
        KeyError: when the answer has no "info" or "version" field.
    """
    data = http_json(f"https://pypi.org/pypi/{name}/json")
    vers = [
        v
        for v, files in data.get("releases", {}).items()
        if files
        and not PRE.search(v)
        and not PEP440_PRE.search(v)
        and not any(f.get("yanked") for f in files)
    ]
    return max(vers, key=vkey) if vers else data["info"]["version"]


_TAGS: dict[str, list[str]] = {}


def gh_tags(repo):
    """Return the tag names of a GitHub repository, cached per repository.

    Args:
        repo: "owner/name" of the GitHub repository.
    Returns:
        The tag names (without the refs/tags/ prefix); empty when git lists none.
    Raises:
        subprocess.TimeoutExpired: when git ls-remote takes more than 60 seconds.
        OSError: when git cannot be started.
    """
    if repo not in _TAGS:
        out = subprocess.run(
            ["git", "ls-remote", "--tags", "--refs", f"https://github.com/{repo}"],
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        ).stdout
        _TAGS[repo] = [
            line.split("refs/tags/", 1)[1] for line in out.splitlines() if "refs/tags/" in line
        ]
    return _TAGS[repo]


def latest_tag(repo, current):
    """Highest stable tag shaped like the current one (same prefix, same number of parts)."""
    tag = urllib.parse.unquote(current)
    m = re.match(r"^(.*?)(\d+(?:\.\d+)*)(.*)$", tag)
    if not m:
        return None
    prefix, num, suffix = m.groups()
    rx = re.compile("^" + re.escape(prefix) + r"(\d+(?:\.\d+)*)" + re.escape(suffix) + "$")
    best = None
    for t in gh_tags(repo):
        mm = rx.match(t)
        if mm and mm.group(1).count(".") != num.count("."):
            # why: same shape only (plantuml's old 'v8059' tags are not newer than v1.2026.8)
            continue
        if (
            mm
            and not PRE.search(t.replace(prefix, "", 1))
            and (best is None or vkey(mm.group(1)) > vkey(best[1]))
        ):
            best = (t, mm.group(1))
    return best[0] if best else None


def _same_major(repo, cur):
    """Node: stay on the pinned LTS line (v24.x), only report newer patch/minor releases."""
    major = cur.split(".")[0]
    vers = [t for t in gh_tags(repo) if re.fullmatch(re.escape(major) + r"\.\d+\.\d+", t)]
    return max(vers, key=vkey) if vers else None


def head_ok(url):
    """Check that an asset URL answers HTTP 200 to a HEAD request.

    Args:
        url: absolute URL of the asset.
    Returns:
        True for HTTP 200, False for any other status or error.
    """
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "qs-check-versions"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status == 200
    except Exception:
        return False


# why: one branch per install channel; splitting them would only move the branches around
def items(reg):  # noqa: C901, PLR0912
    """(tool, channel, name, current, asset_urls) for every pinned install."""
    out = []
    for tid, t in sorted(reg["tools"].items()):
        for ins in t.get("install") or []:
            if "npm" in ins:
                for spec in ins["npm"]:
                    name, _, ver = spec.rpartition("@")
                    out.append((tid, "npm", name, ver, []))
            elif "pip" in ins:
                name, _, ver = ins["pip"]["pkg"].partition("==")
                out.append((tid, "pip", re.sub(r"\[.*\]", "", name), ver, []))
            elif "github" in ins:
                g = ins["github"]
                ver = g["tag"][1:] if g["tag"].startswith("v") else g["tag"]
                arch = g.get("arch") or {"amd64": "x86_64"}
                assets = [
                    f"https://github.com/{g['repo']}/releases/download/{g['tag']}/"
                    + g["asset"].format(tag=g["tag"], ver=ver, arch=a)
                    for a in arch.values()
                ]
                out.append((tid, "github", g["repo"], g["tag"], assets))
            else:
                for kind in ("url", "jar", "phar"):
                    if kind in ins:
                        u = ins[kind]["url"]
                        m = GH_URL.match(u)
                        arch = ins[kind].get("arch") or {}
                        urls = [u.format(arch=a) for a in arch.values()] if "{arch}" in u else [u]
                        hm = re.match(r"https://get\.helm\.sh/helm-(v[\d.]+)-", u)
                        if m:
                            out.append((tid, kind, m.group(1), m.group(2), urls))
                        elif hm:
                            out.append((tid, kind, "helm/helm", hm.group(1), urls))
                        else:
                            out.append((tid, kind, u, "-", urls))
    for rid, rt in sorted(reg["runtimes"].items()):
        m = re.search(r"(\d+\.\d+\.\d+)", rt.get("name", ""))
        if rid in RUNTIME_TAGS and m:
            repo, fmt = RUNTIME_TAGS[rid]
            out.append((f"runtime:{rid}", "runtime", repo, fmt.format(m.group(1)), []))
        for ins in rt.get("install") or []:
            if "github" in ins:
                g = ins["github"]
                out.append((f"runtime:{rid}", "github", g["repo"], g["tag"], []))
            elif "script" in ins and re.search(r"/latest|latest-v|mode=json", ins["script"]):
                out.append((f"runtime:{rid}", "script", rid, "floating", []))
            if "apt" in ins:
                out.append((f"runtime:{rid}", "apt", " ".join(ins["apt"]), "ubuntu", []))
    return out


# runtime id -> (GitHub repo whose tags carry the releases, tag format of the pinned version)
RUNTIME_TAGS = {
    "node": ("nodejs/node", "v{}"),
    "go": ("golang/go", "go{}"),
    "rust": ("rust-lang/rust", "{}"),
    "dart": ("dart-lang/sdk", "{}"),
    "julia": ("JuliaLang/julia", "v{}"),
}


# newer releases deliberately not taken (status "held"); revisit when the reason goes away
HELD = {
    (
        "npm",
        "typescript",
    ): "typescript-eslint 8.x supports typescript <6.1 (7.x is the native port)",
    ("npm", "graphql"): "graphql-schema-linter and @graphql-eslint require graphql ^16",
    ("github", "open-policy-agent/regal"): "the v2.x tags publish no release binaries",
}


def check(item, verify):
    """Compare one pinned install with its latest stable release.

    Args:
        item: (tool, channel, name, current, asset_urls) tuple from items().
        verify: when True, also check that the pinned and newer assets download.
    Returns:
        A dict with the keys tool, channel, name, current, latest, status and note.
    Errors from the source lookups are not raised: they are reported in note.
    """
    tid, ch, name, cur, assets = item
    latest, note = None, ""
    try:
        if ch == "npm":
            latest = latest_npm(name)
        elif ch == "pip":
            latest = latest_pypi(name)
        elif ch == "runtime" and name == "nodejs/node":
            latest = _same_major(name, cur)
        elif ch in ("github", "url", "jar", "phar", "runtime") and cur != "-":
            latest = latest_tag(name, cur)
    except Exception as e:  # why: one unreachable source must not hide the rest
        note = f"lookup failed: {e.__class__.__name__}"
    if verify and assets:
        bad = [a for a in assets if not head_ok(a)]
        if bad:
            note = (
                (note + "; " if note else "")
                + "asset missing: "
                + ", ".join(os.path.basename(b) for b in bad)
            )
        if latest and latest not in (cur, urllib.parse.unquote(cur)):
            # why: a newer tag is useless if it ships no binaries
            # (some projects tag before releasing)
            enc = urllib.parse.quote(latest, safe="") if "%2F" in cur else latest
            nv, ov = re.sub(r"^\D*", "", latest), re.sub(r"^\D*", "", urllib.parse.unquote(cur))
            cand = [a.replace(cur, enc).replace(ov, nv) for a in assets]
            missing = [c for c in cand if not head_ok(c)]
            note = (note + "; " if note else "") + (
                "new assets OK"
                if not missing
                else "new assets missing: " + os.path.basename(missing[0])
            )
    cur_cmp = urllib.parse.unquote(cur)
    status = (
        "floating"
        if cur == "floating"
        else "distro"
        if cur == "ubuntu"
        else "?"
        if not latest
        else "ok"
        if latest in (cur, cur_cmp)
        else "update"
    )
    if status == "update" and (ch, name) in HELD:
        status, note = "held", HELD[(ch, name)]
    return {
        "tool": tid,
        "channel": ch,
        "name": name,
        "current": cur_cmp,
        "latest": latest or "",
        "status": status,
        "note": note,
    }


def main(argv):
    """Command line entry point: print the status of every pinned tool.

    Args:
        argv: command line arguments, without the program name.
    Returns:
        0 after printing the table, or the JSON list with --json.
    Raises:
        SystemExit: on invalid arguments (argparse).
        OSError: when registry/registry.json cannot be read.
    """
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--verify-assets", action="store_true")
    a = ap.parse_args(argv)
    with open(os.path.join(ROOT, "registry", "registry.json"), encoding="utf-8") as fh:
        reg = json.load(fh)
    todo = [i for i in items(reg) if not a.only or i[1] in a.only.split(",")]
    seen, uniq = set(), []
    for i in todo:
        k = (i[1], i[2], i[3])
        if k not in seen:
            seen.add(k)
            uniq.append(i)
    with cf.ThreadPoolExecutor(8) as ex:
        res = list(ex.map(lambda i: check(i, a.verify_assets), uniq))
    if a.json:
        json.dump(res, sys.stdout, indent=1)
        return 0
    w = max(len(r["tool"]) for r in res)
    for r in sorted(res, key=lambda r: (r["status"] != "update", r["tool"])):
        print(
            f"{r['status']:<8} {r['tool']:<{w}} {r['channel']:<6} {r['name']:<40} "
            f"{r['current']:<22} "
            f"{r['latest']:<22} {r['note']}"
        )
    n = sum(r["status"] == "update" for r in res)
    print(f"\n{len(res)} pinned items, {n} with a newer stable release")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
