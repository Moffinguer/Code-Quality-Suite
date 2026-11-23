#!/usr/bin/env bash
# Cases of the FORMAT branch (6.0.0 format_branch task): git formatear creates and regenerates
# <node>/FORMAT with one 'style: format <scope>' commit of formatter output (a fake formatter
# stands for the suite formatters: QS_FORMAT_CMD), qs.py format-check, .git-blame-ignore-revs.
# The hook refusals (pre-commit, commit-msg, pre-rebase) and git integra belong to the hooks_rules
# and integra_order tasks and are tested there.
# why: every check is written `cond && ok "..." || fail "..."`, and ok never fails
# shellcheck disable=SC2015,SC2153
set -euo pipefail
# shellcheck source=tests/hooks/case-lib.sh
. "$SUITE/tests/hooks/case-lib.sh"
case_sandbox squash

# fake formatter: removes trailing blanks of the file given as its last argument
cat >"$T/fake-format.sh" <<'EOF'
#!/usr/bin/env bash
sed -i 's/[[:space:]]*$//' "$1"
EOF
export QS_FORMAT_CMD="bash $T/fake-format.sh" QS_PUBLISH=0
ORIG=6.0.0/ot1/ORIGINAL FMT=6.0.0/ot1/FORMAT

# subject BRANCH: the subject of the tip commit. Arguments: $1 branch. Returns: 0; prints it.
subject() { git log -n1 --format=%s "$1"; }

git np 6.0.0 >/dev/null
git np ot1 >/dev/null
# why: plumbing commits, because the pre-commit hook would already strip the trailing blanks
plumb_commit local "$ORIG" a.txt "one   " "feat(a): add a" >/dev/null
plumb_commit local "$ORIG" src/a/x.txt "x  " "feat(a): add x" >/dev/null
plumb_commit local "$ORIG" src/b/y.txt "y  " "feat(a): add y" >/dev/null
plumb_commit local "$ORIG" clean.txt "clean" "feat(a): add clean" >/dev/null
git nr a >/dev/null
git checkout -q "$ORIG"

# --- FM1 git formatear: one style commit equal to the formatter output
out="$(git formatear 2>&1)" || fail "git formatear failed: $out"
[ "$(git branch --show-current)" = "$FMT" ] && ok "formatear leaves FORMAT checked out" || fail "branch is $(git branch --show-current): $out"
[ "$(git rev-list --count "$ORIG..$FMT")" = 1 ] && ok "FORMAT has one commit over the ORIGINAL" || fail "commits: $(git rev-list --count "$ORIG..$FMT")"
[ "$(subject "$FMT")" = "style: format all" ] && ok "subject is 'style: format all'" || fail "subject: $(subject "$FMT")"
git log -n1 --format=%B "$FMT" | grep -qx "Format-scope: all" && ok "Format-scope trailer" || fail "no Format-scope trailer"
git log -n1 --format=%B "$FMT" | grep -qx "M a.txt" && ok "Files block lists a.txt" || fail "Files block"
[ "$(git show "$FMT:a.txt")" = "one" ] && [ "$(git show "$FMT:src/b/y.txt")" = "y" ] && ok "the files are the formatter output" || fail "content"
[ "$(git show "$ORIG:a.txt")" = "one   " ] && ok "the ORIGINAL is untouched" || fail "ORIGINAL changed"
git diff --quiet && git diff --cached --quiet && ok "work tree clean after formatear" || fail "dirty work tree"
git formatear >/dev/null 2>&1 && ok "formatear on FORMAT regenerates it" || fail "formatear on FORMAT failed"
[ "$(git rev-list --count "$ORIG..$FMT")" = 1 ] && ok "still one commit after regenerating" || fail "commits after regenerate"

# scoped, typed from a subfolder
git checkout -q "$ORIG"
git branch -q -D "$FMT"
(cd src && git formatear a >/dev/null 2>&1) || fail "git formatear src/a failed"
[ "$(subject "$FMT")" = "style: format src/a" ] && ok "git formatear a (from src) -> 'style: format src/a'" || fail "scoped subject: $(subject "$FMT")"
[ "$(git show "$FMT:src/a/x.txt")" = "x" ] && [ "$(git show "$FMT:src/b/y.txt")" = "y  " ] && [ "$(git show "$FMT:a.txt")" = "one   " ] &&
	ok "only the given path is formatted" || fail "scoped content"
git checkout -q "$ORIG"
git branch -q -D "$FMT"
git formatear nothere >/dev/null 2>&1 && fail "formatear of an unknown path accepted" || ok "formatear refuses an untracked path"
git formatear clean.txt >/dev/null 2>&1 || fail "formatear of a clean file failed"
git rev-parse -q --verify "$FMT" >/dev/null && fail "FORMAT made with nothing to format" || ok "nothing to format: no branch"

# placement
git checkout -q 6.0.0/ORIGINAL
git formatear >/dev/null 2>&1 && fail "formatear on the version ORIGINAL accepted" || ok "formatear refused on the version ORIGINAL"
git checkout -q 6.0.0/ot1/a
git formatear >/dev/null 2>&1 && fail "formatear on a final branch accepted" || ok "formatear refused on a final branch"
git checkout -q "$ORIG"

# --- FM2 qs.py format-check: formatter output only
git formatear >/dev/null 2>&1 || fail "formatear (FM2)"
printf '%s\n' "one" "added by hand" >a.txt
if QS_ROOT="$PWD" python3 "$SUITE/engine/qs.py" format-check a.txt >"$T/fc.out"; then fail "format-check accepted a hand edit"; fi
grep -q "a.txt" "$T/fc.out" && ok "format-check refuses a hand edit" || fail "format-check output"
git reset -q --hard "$FMT"
QS_ROOT="$PWD" python3 "$SUITE/engine/qs.py" format-check --rev "$ORIG" a.txt >/dev/null && ok "format-check accepts the formatter output" || fail "format-check refused the output"

# --- FM4 the ORIGINAL moved: regenerate (one commit again); other commits refused
plumb_commit local "$ORIG" b.txt "b   " "feat(b): add b" >/dev/null
git formatear >/dev/null 2>&1 || fail "formatear after the ORIGINAL moved"
[ "$(git rev-parse "$FMT^")" = "$(git rev-parse "$ORIG")" ] && ok "FORMAT reset to the moved ORIGINAL" || fail "FORMAT parent is not the ORIGINAL tip"
[ "$(git rev-list --count "$ORIG..$FMT")" = 1 ] && [ "$(git show "$FMT:b.txt")" = "b" ] && ok "FORMAT regenerated with one commit" || fail "regenerate: $(git rev-list --count "$ORIG..$FMT") commits"
plumb_commit local "$FMT" z.txt "hand" "feat(z): by hand" >/dev/null
out="$(git formatear 2>&1)" && fail "formatear accepted a FORMAT with another commit"
grep -q "not format commits" <<<"$out" && ok "FORMAT with a hand commit is refused" || fail "hand commit message: $out"

# --- FM5 .git-blame-ignore-revs and blame.ignoreRevsFile
[ -z "$(git config blame.ignoreRevsFile || true)" ] && ok "no ignore file, no blame config" || fail "blame config set without the file"
git checkout -q "$ORIG"
git branch -q -D "$FMT"
GIT_AUTHOR_NAME=Alice GIT_AUTHOR_EMAIL=alice@example.com plumb_commit local "$ORIG" blame.txt "keep   " "feat(c): add blame.txt" >/dev/null
git formatear >/dev/null 2>&1 || fail "formatear (blame)"
FSHA="$(git rev-parse "$FMT")"
(. "$SUITE/scripts/git-formatear.sh" && formatear_ignore_rev "$FSHA" all) || fail "formatear_ignore_rev"
grep -qx "$FSHA" .git-blame-ignore-revs && ok "the sha is in .git-blame-ignore-revs" || fail "sha missing"
(. "$SUITE/scripts/git-formatear.sh" && formatear_ignore_rev "$FSHA" all)
[ "$(grep -cx "$FSHA" .git-blame-ignore-revs)" = 1 ] && ok "the sha is written once" || fail "sha duplicated"
[ "$(git config blame.ignoreRevsFile)" = .git-blame-ignore-revs ] && ok "blame.ignoreRevsFile is set" || fail "blame config: $(git config blame.ignoreRevsFile)"
git config --unset blame.ignoreRevsFile
(. "$SUITE/scripts/git-flow-lib.sh" && configure_repo "$SUITE")
[ "$(git config blame.ignoreRevsFile)" = .git-blame-ignore-revs ] && ok "configure_repo sets it when the file exists" || fail "configure_repo blame config"
# blame: the line was written by Alice; the format commit is by the tester
git config --unset blame.ignoreRevsFile
who="$(git blame --line-porcelain blame.txt | sed -n 's/^author //p' | head -n1)"
[ "$who" = tester ] && ok "blame without the ignore list shows the formatter" || fail "blame author: $who"
git config blame.ignoreRevsFile .git-blame-ignore-revs
who="$(git blame --line-porcelain blame.txt | sed -n 's/^author //p' | head -n1)"
[ "$who" = Alice ] && ok "blame with the ignore list shows the previous author" || fail "blame author with the list: $who"

# --- FM6 convertir-padre on FORMAT refused
git formatear >/dev/null 2>&1 || fail "formatear (FM6)"
git convertir-padre --yes >/dev/null 2>&1 && fail "convertir-padre accepted on FORMAT" || ok "convertir-padre refused on FORMAT"
git show-ref --verify -q "refs/heads/$FMT" && ok "FORMAT is still a final branch" || fail "FORMAT was renamed"
