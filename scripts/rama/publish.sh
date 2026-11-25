#!/usr/bin/env bash
# rama/publish.sh - git publicar (squash flow, rebase, tag, push) (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

# --- git publicar with branches.flow = squash ----------------------------------------------------
# State of one run, set by publish_local_release: PUB_TIP the '<v>/RELEASE' tip being published.
# PUB_AGAIN: the command that resumes after a stopped rebase (git subir sets it; empty means
# git publicar --version <v>). PUB_TOKEN: the placeholder of a release-owned line while
# publish_solve_file merges a release file; PUB_POMS: the "|a|b|" artifactIds of the RELEASE side.
PUB_TIP="" PUB_AGAIN="" PUB_TOKEN='@@qs:release-owned@@' PUB_POMS="|"

# publish_is_release_file <path>: whether <path> is one of the files the release commits write:
# QS_BR_CHANGELOG, the version file, a pom.xml, package.json, the README or CITATION.cff.
# Arguments: $1 path (from the top of the work tree). Returns: 0 when it is one, 1 otherwise.
publish_is_release_file() {
	release_owned_file "$1" --content
}

# publish_mask <path> <in> <out> <saved>: write to <out> the file <in> with every release-owned
# piece replaced by PUB_TOKEN, and append each piece replaced to <saved> (one per line, in
# order). Release-owned: in the README the badge between its qs:version markers (only that span);
# in a pom.xml the project's own version (POM_AWK; the parent version when the parent is one of
# PUB_POMS); in package.json the top-level "version" line; in CITATION.cff the top-level
# version: and date-released: lines. Any other file is copied as it is.
# Arguments: $1 the path in the repository (picks the rules); $2 input; $3 output; $4 the list of
# pieces (created empty first). Returns: 0; 1 when <in> already holds PUB_TOKEN.
publish_mask() {
	local p="$1" in="$2" out="$3" saved="$4"
	: >"$saved"
	! grep -qF -- "$PUB_TOKEN" "$in" || return 1
	case "$p" in
	"${QS_BR_README:-README.md}")
		# shellcheck disable=SC2016
		awk -v token="$PUB_TOKEN" -v saved="$saved" -v s='<!-- qs:version -->' -v e='<!-- /qs:version -->' '{
			out = ""; rest = $0
			while ((i = index(rest, s)) && (j = index(substr(rest, i + length(s)), e))) {
				k = i + length(s) + j + length(e) - 2
				print substr(rest, i, k - i + 1) >>saved
				out = out substr(rest, 1, i - 1) token
				rest = substr(rest, k + 1)
			}
			print out rest
		}' "$in" >"$out"
		;;
	pom.xml | */pom.xml) awk -v mode=mask -v token="$PUB_TOKEN" -v saved="$saved" -v ours="$PUB_POMS" "$POM_AWK" "$in" >"$out" ;;
	package.json) awk -v mode=mask -v token="$PUB_TOKEN" -v saved="$saved" "$JSON_AWK" "$in" >"$out" ;;
	CITATION.cff) awk -v token="$PUB_TOKEN" -v saved="$saved" '/^(version|date-released):/ { print token; print >>saved; next } { print }' "$in" >"$out" ;;
	*) cat -- "$in" >"$out" ;;
	esac
}

# publish_unmask <in> <saved>: print <in> with each PUB_TOKEN replaced, in order, by the next line
# of <saved> (the release-owned pieces of the RELEASE side, publish_mask).
# Arguments: $1 the merged masked file; $2 the pieces. Output: the file.
# Returns: 0; 1 when the number of placeholders and of pieces differ (output incomplete).
publish_unmask() {
	awk -v token="$PUB_TOKEN" -v saved="$2" '
		BEGIN { while ((getline l < saved) > 0) piece[++np] = l }
		{
			out = ""; rest = $0
			while ((i = index(rest, token))) {
				if (++k > np) bad = 1
				out = out substr(rest, 1, i - 1) piece[k]
				rest = substr(rest, i + length(token))
			}
			print out rest
		}
		END { exit (bad || k != np) ? 1 : 0 }' "$1"
}

# publish_solve_file <path> <ours> <base> <theirs> <out>: the merge of a release file that solves
# ONLY its release-owned pieces (publish_mask): the three sides are masked, merged with git
# merge-file (so develop's edits next to the badge or the version line are kept), and the
# pieces of the RELEASE side put back. Any conflict left is a conflict on other lines.
# Arguments: $1 the path in the repository; $2 develop side; $3 base; $4 RELEASE side; $5 output.
# Returns: 0 when solved; 1 when another line conflicts (or the pieces do not line up).
publish_solve_file() {
	local p="$1" out="$5" s
	for s in 2 3 4; do publish_mask "$p" "${!s}" "${!s}.m" "${!s}.saved" || return 1; done
	git merge-file -q -p "$2.m" "$3.m" "$4.m" >"$out.m" 2>/dev/null || return 1
	publish_unmask "$out.m" "$4.saved" >"$out"
}

# publish_changelog_merge <ours> <theirs> <version>: the changelog <ours> with the '## <version>'
# section of <theirs> in semver order (newest first): it replaces a section of that version in
# <ours>, or goes before the first heading of a lower version, or at the end. Headings that are
# not versions ('## [Unreleased]') stay where they are. Without such a section in <theirs> the
# output is <ours> unchanged.
# Arguments: $1 file of the develop side; $2 file of the RELEASE side; $3 the version.
# Output: the merged changelog. Returns: 0.
publish_changelog_merge() {
	awk -v v="$3" -v theirs="$2" '
		# hv: the version of a "## [v] - date" / "## v - date" / "## v" heading
		function hv(line, s, n) {
			s = substr(line, 4)
			sub(/^\[/, "", s)
			n = index(s, "]")
			if (n) s = substr(s, 1, n - 1)
			sub(/ .*$/, "", s)
			return s
		}
		# isver(s): awk helper. Returns 1 when s looks like a version (dotted digits, optional -suffix), else 0.
		# Arguments: s a string. Errors: none.
		function isver(s) { return s ~ /^[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.-]+)?$/ }
		# isnum(s): awk helper. Returns 1 when s is only digits, else 0.
		# Arguments: s a string. Errors: none.
		function isnum(s) { return s ~ /^[0-9]+$/ }
		# cmp: -1, 0 or 1 as semver orders a and b (a pre-release sorts before its release)
		function cmp(a, b, ca, cb, pa, pb, i, n, na, nb, A, B) {
			ca = a; pa = ""; i = index(a, "-"); if (i) { ca = substr(a, 1, i - 1); pa = substr(a, i + 1) }
			cb = b; pb = ""; i = index(b, "-"); if (i) { cb = substr(b, 1, i - 1); pb = substr(b, i + 1) }
			na = split(ca, A, "."); nb = split(cb, B, ".")
			n = na > nb ? na : nb
			for (i = 1; i <= n; i++) if (A[i] + 0 != B[i] + 0) return A[i] + 0 < B[i] + 0 ? -1 : 1
			if (pa == pb) return 0
			if (pa == "") return 1
			if (pb == "") return -1
			na = split(pa, A, "."); nb = split(pb, B, ".")
			for (i = 1; i <= na && i <= nb; i++) {
				if (A[i] == B[i]) continue
				if (isnum(A[i]) && isnum(B[i])) return A[i] + 0 < B[i] + 0 ? -1 : 1
				if (isnum(A[i])) return -1
				if (isnum(B[i])) return 1
				return A[i] < B[i] ? -1 : 1
			}
			return na < nb ? -1 : (na > nb ? 1 : 0)
		}
		# emit(i): awk helper. Prints the held section (sec[1] to sec[ns]) and a blank line, then marks it
		# done so it is printed only once. Arguments: none (i is a local loop variable). Errors: none.
		function emit(i) {
			for (i = 1; i <= ns; i++) print sec[i]
			print ""
			last = ""
			done = 1
		}
		BEGIN {
			while ((getline line < theirs) > 0) {
				if (line ~ /^## /) { if (on) break; on = (hv(line) == v) }
				if (on) sec[++ns] = line
			}
			while (ns > 0 && sec[ns] == "") ns--
		}
		/^## / {
			skip = (ns > 0 && hv($0) == v)
			if (!skip && !done && ns > 0 && isver(hv($0)) && cmp(hv($0), v) < 0) emit()
		}
		skip { next }
		{ print; last = $0 }
		END {
			if (done || ns == 0) exit
			if (NR && last != "") print ""
			emit()
		}' "$1"
}

# publish_autosolve: solve the conflicts of the stopped step of the RELEASE rebase when the
# commit being replayed is a release commit (RELEASE_COMMITS_RX) and every conflicted path is a
# release file. Only release-owned text is solved: QS_BR_CHANGELOG keeps both entries in semver
# order (publish_changelog_merge, the REL_VERSION section of the RELEASE side), the version file
# takes the RELEASE side, and the README, pom.xml, package.json and CITATION.cff keep every edit of
# both sides with the RELEASE side's badge / version (publish_solve_file). A conflict on any other
# line, a side that deleted the file, or a piece that does not line up leaves the step for the
# human. All files are solved in a scratch folder first; only then are they written and staged.
# Arguments: none; reads REL_VERSION; runs at the top of the work tree.
# Returns: 0 when every conflict was solved; 1 when one is left for the human (nothing written).
publish_autosolve() {
	local c files f t i=0 rc=0
	c="$(git rev-parse -q --verify REBASE_HEAD 2>/dev/null)" || return 1
	[[ $(git log -1 --format=%s "$c") =~ $RELEASE_COMMITS_RX ]] || return 1
	files="$(git diff --name-only --diff-filter=U)"
	[ -n "$files" ] || return 1
	while IFS= read -r f; do publish_is_release_file "$f" || return 1; done <<<"$files"
	t="$(git rev-parse --absolute-git-dir)/quality-suite/publish-solve"
	rm -rf "$t"
	mkdir -p "$t/out"
	PUB_POMS="$(pom_artifacts "$c")"
	while IFS= read -r f; do
		i=$((i + 1))
		git show ":3:$f" >"$t/theirs" 2>/dev/null || {
			rc=1
			break
		}
		if [ "$f" = "$QS_BR_CHANGELOG" ]; then
			git show ":2:$f" >"$t/ours" 2>/dev/null || : >"$t/ours"
			publish_changelog_merge "$t/ours" "$t/theirs" "$REL_VERSION" >"$t/out/$i"
		elif [ "$f" = "${QS_BR_VERSION_FILE:-VERSION}" ]; then
			cp -- "$t/theirs" "$t/out/$i"
		elif ! git show ":2:$f" >"$t/ours" 2>/dev/null; then
			rc=1
			break
		else
			git show ":1:$f" >"$t/base" 2>/dev/null || : >"$t/base"
			publish_solve_file "$f" "$t/ours" "$t/base" "$t/theirs" "$t/out/$i" || {
				rc=1
				break
			}
		fi
	done <<<"$files"
	if [ "$rc" = 0 ]; then
		i=0
		while IFS= read -r f; do
			i=$((i + 1))
			cat -- "$t/out/$i" >"$f"
			git add -- "$f"
		done <<<"$files"
	else
		echo "[rama] $f: the conflict is not only on release-owned lines (badge, version); it is left for you" >&2
	fi
	rm -rf "$t"
	[ "$rc" = 0 ] || return 1
	say "release files solved for $(git log -1 --format='%h %s' "$c"): ${files//$'\n'/ }"
}

# publish_stopped: end git publicar while the rebase of REL_RELEASE is stopped on a conflict it
# cannot solve, with the conflicted files and the exact steps. The rebase stays stopped: develop,
# REL_RELEASE, the tag and origin have not moved. Step 3 names PUB_AGAIN (git subir) or git publicar.
# Arguments: none; reads REL_RELEASE REL_VERSION REL_TAG PUB_AGAIN. Returns: never (exits 1 through die).
publish_stopped() {
	local files at
	files="$(git diff --name-only --diff-filter=U)"
	at="$(git log -1 --format='%h %s' REBASE_HEAD 2>/dev/null || echo 'a step')"
	{
		echo "[rama] conflict while rebasing $REL_RELEASE onto $QS_BR_MAINLINE at $at${files:+, in: ${files//$'\n'/ }}."
		echo "  Nothing was published: $QS_BR_MAINLINE, $REL_RELEASE, the tag $REL_TAG and origin did not move."
		echo "  Solve it:"
		echo "    1. edit the files, then: git add <files>"
		echo "    2. git rebase --continue"
		echo "    3. ${PUB_AGAIN:-git publicar --version $REL_VERSION}   (it resumes; release-file conflicts are solved for you)"
		echo "  Give up instead: git rebase --abort"
	} >&2
	die "stopped: solve the conflict, then run ${PUB_AGAIN:-git publicar --version $REL_VERSION} again"
}

# publish_rebase <onto>: rebase REL_RELEASE onto <onto> (a develop commit), or carry on with the
# stopped rebase of REL_RELEASE. Steps that stop only on release files of a release commit are
# solved (publish_autosolve) and continued; any other stop ends through publish_stopped with the
# rebase left stopped, so REL_RELEASE does not move until the rebase ends.
# Arguments: $1 the commit to rebase onto. Returns: 0 when REL_RELEASE contains <onto>; exits
# through die otherwise.
publish_rebase() {
	local onto="$1" log
	log="$(git rev-parse --absolute-git-dir)/quality-suite/publish.log"
	mkdir -p "$(dirname "$log")"
	if ! rebase_in_progress; then
		git merge-base --is-ancestor "$onto" "refs/heads/$REL_RELEASE" && return 0
		say "rebasing $REL_RELEASE onto $QS_BR_MAINLINE ($(git rev-parse --short "$onto"))..."
		if ! git rebase -q "$onto" "$REL_RELEASE" >"$log" 2>&1 && ! rebase_in_progress; then
			cat "$log" >&2
			die "the rebase of $REL_RELEASE onto $QS_BR_MAINLINE was refused (see above); nothing was changed"
		fi
	fi
	while rebase_in_progress; do
		if [ -n "$(git ls-files -u)" ]; then publish_autosolve || publish_stopped; fi
		# why: a step whose solution (made here or by hand, then git add) equals develop has nothing
		# left to commit, and git rebase --continue refuses it; unstaged edits are never skipped
		if git diff --cached --quiet && git diff --quiet; then
			GIT_EDITOR=true git rebase --skip >"$log" 2>&1 && continue
			[ -n "$(git ls-files -u)" ] && continue
			cat "$log" >&2
			publish_stopped
		fi
		GIT_EDITOR=true git rebase --continue >"$log" 2>&1 && continue
		[ -n "$(git ls-files -u)" ] && continue
		cat "$log" >&2
		publish_stopped
	done
	git merge-base --is-ancestor "$onto" "refs/heads/$REL_RELEASE" ||
		die "$REL_RELEASE was not rebased onto $QS_BR_MAINLINE (see the messages above)"
}

# publish_local_release: make sure REL_RELEASE exists locally and is the copy to publish: created
# from origin when only origin has it, moved forward when it is behind origin. Local and origin
# diverged is accepted only when origin still holds the tip recorded before git publicar rebased
# it (git config qs.publish.<v>.from).
# Arguments: none; reads REL_RELEASE REL_VERSION. Sets PUB_TIP to the local tip. Returns: 0;
# exits through die when local and origin diverged otherwise.
publish_local_release() {
	local o l
	o="$(git rev-parse -q --verify "refs/remotes/origin/$REL_RELEASE" || true)"
	l="$(git rev-parse -q --verify "refs/heads/$REL_RELEASE" || true)"
	if [ -z "$l" ]; then
		git branch -q --no-track "$REL_RELEASE" "$o"
		l="$o"
	elif [ -n "$o" ] && ! git merge-base --is-ancestor "$o" "$l"; then
		if git merge-base --is-ancestor "$l" "$o"; then
			if [ "$(current_branch || true)" = "$REL_RELEASE" ]; then
				git merge -q --ff-only "$o"
			else git update-ref "refs/heads/$REL_RELEASE" "$o" "$l"; fi
			l="$o"
		elif [ "$o" != "$(git config "qs.publish.$REL_VERSION.from" 2>/dev/null || true)" ]; then
			die "$REL_RELEASE: local and origin diverged; pull it first (git checkout $REL_RELEASE && git pull)"
		fi
	fi
	PUB_TIP="$l"
}

# publish_remote_tag: the commit the tag REL_TAG points at on origin (peeled), or nothing when
# origin has no such tag or there is no origin.
# Arguments: none. Output: the commit id. Returns: 0.
publish_remote_tag() {
	has_origin || return 0
	git ls-remote --tags origin 2>/dev/null | awk -v t="refs/tags/$REL_TAG" '
		$2 == t { plain = $1 }
		$2 == t "^{}" { peeled = $1 }
		END { if (peeled != "") print peeled; else if (plain != "") print plain }'
}

# publish_message <base> <tip>: the message of the develop commit of the release: subject
# chore(release): <tag>, the CHANGELOG.md entry of the version, the Commits: block (nested) and
# the Files: block of base..tip, then the trailers Refs: <v>/RELEASE -> develop, Squashed:
# <v>/RELEASE <tip> and the Squashes: lines of the commits base..tip (a combined RELEASE).
# Arguments: $1 the develop commit; $2 the RELEASE tip. Output: the message. Returns: 0.
publish_message() {
	local base="$1" tip="$2" entry
	entry="$(version_section "$tip" | sed '1d' | sed '/./,$!d')"
	release_subject "$REL_TAG"
	printf '\n\n'
	echo "Release $REL_TAG of $REL_VERSION: $(git rev-list --count --no-merges "$tip" "^$base") commit(s)."
	echo
	[ -z "$entry" ] || printf '%s\n\n' "$entry"
	squash_commits_block "$base" "$tip"
	squash_files_block "$base" "$tip"
	echo
	echo "Refs: $REL_RELEASE -> $QS_BR_MAINLINE"
	echo "Squashed: $REL_RELEASE $(git rev-parse "$tip^{commit}")"
	git log --reverse --format=%B "$tip" "^$base" -- | grep '^Squashes: ' | awk '!seen[$0]++' || true
}

# publish_commit <base> <tip>: ONE single-parent commit on develop with the tree of <tip> (the
# rebased RELEASE, which contains <base>) and publish_message; the hooks run. Local develop is
# first brought to <base> (a fast-forward to origin). On any failure develop goes back to where it
# was and the RELEASE branch is checked out.
# Arguments: $1 the develop commit; $2 the RELEASE tip. Returns: 0 when committed, 1 otherwise.
publish_commit() {
	local base="$1" tip="$2" msg old
	msg="$(git rev-parse --absolute-git-dir)/quality-suite/PUBLISH_MSG"
	mkdir -p "$(dirname "$msg")"
	publish_message "$base" "$tip" >"$msg"
	old="$(git rev-parse -q --verify "refs/heads/$QS_BR_MAINLINE" || true)"
	if [ -n "$old" ]; then
		git checkout -q "$QS_BR_MAINLINE"
	else git checkout -q -b "$QS_BR_MAINLINE" --track "origin/$QS_BR_MAINLINE"; fi
	if { [ "$(git rev-parse HEAD)" = "$base" ] || git merge -q --ff-only "$base"; } &&
		quiet_merge -c merge.ff=true merge -q --squash "$tip" &&
		git commit -q --cleanup=whitespace -F "$msg" &&
		[ "$(git rev-parse "HEAD^{tree}")" = "$(git rev-parse "$tip^{tree}")" ]; then
		return 0
	fi
	if [ -n "$old" ]; then git reset -q --hard "$old"; else git reset -q --hard HEAD; fi
	git checkout -q "$REL_RELEASE"
	[ -n "$old" ] || git branch -q -D "$QS_BR_MAINLINE"
	return 1
}

# publish_tag <commit>: the annotated tag REL_TAG on <commit> (the develop commit of the release),
# created or moved there; it keeps the message of the local tag git release made (reviewed text),
# else 'Release <tag> (<v>)' and the CHANGELOG.md entry. Local only: publish_push pushes it.
# Arguments: $1 the commit. Returns: 0; exits through die when the tag cannot be written.
publish_tag() {
	local c="$1" msg
	exists_ref "refs/tags/$REL_TAG" && [ "$(git rev-parse "refs/tags/$REL_TAG^{commit}")" = "$c" ] && return 0
	msg="$(git rev-parse --absolute-git-dir)/quality-suite/PUBLISH_TAG_MSG"
	if exists_ref "refs/tags/$REL_TAG" && [ "$(git cat-file -t "refs/tags/$REL_TAG")" = tag ]; then
		git for-each-ref --format='%(contents)' "refs/tags/$REL_TAG" >"$msg"
	else
		version_tag_message "$msg"
	fi
	git tag -f -a --cleanup=whitespace -F "$msg" "$REL_TAG" "$c" >/dev/null ||
		die "the tag $REL_TAG could not be written on $QS_BR_MAINLINE; run git publicar --version $REL_VERSION again (it resumes)"
	say "tag $REL_TAG on $QS_BR_MAINLINE ($(git rev-parse --short "$c"))"
}

# publish_push: ONE atomic push of develop, the tag REL_TAG and the deletion of REL_RELEASE on
# origin (with a lease on the value fetched). Nothing when REL_PUSH is 0 or there is no origin.
# Arguments: none. Returns: 0 when pushed (or nothing to push), 1 when the push was rejected
# (origin unchanged).
publish_push() {
	local refs lease=() o
	[ "$REL_PUSH" = 1 ] && has_origin || return 0
	refs=("refs/heads/$QS_BR_MAINLINE:refs/heads/$QS_BR_MAINLINE" "refs/tags/$REL_TAG:refs/tags/$REL_TAG")
	o="$(git rev-parse -q --verify "refs/remotes/origin/$REL_RELEASE" || true)"
	if [ -n "$o" ]; then
		refs+=(":refs/heads/$REL_RELEASE")
		lease=("--force-with-lease=refs/heads/$REL_RELEASE:$o")
	fi
	git push -q --atomic origin ${lease[@]+"${lease[@]}"} "${refs[@]}" || return 1
	say "pushed $QS_BR_MAINLINE and $REL_TAG$([ -n "$o" ] && echo "; $REL_RELEASE deleted on origin") (one atomic push)"
}

# publish_from_stale: whether git config qs.publish.<v>.from (the origin tip of REL_RELEASE kept
# while git publicar rebases it, so that the rebased local copy may differ from origin) is stale:
# no rebase is stopped and that permission is not needed: the local REL_RELEASE is gone, origin
# has no REL_RELEASE or another tip, or the local copy still contains the origin tip (it was not
# rebased, as after 'git rebase --abort' of a stopped git publicar, or it was pushed since).
# Arguments: none; reads REL_VERSION REL_RELEASE. Returns: 0 when stale; 1 when unset or in use.
publish_from_stale() {
	local from l o
	from="$(git config "qs.publish.$REL_VERSION.from" 2>/dev/null || true)"
	[ -n "$from" ] || return 1
	! rebase_in_progress || return 1
	l="$(git rev-parse -q --verify "refs/heads/$REL_RELEASE" || true)"
	o="$(git rev-parse -q --verify "refs/remotes/origin/$REL_RELEASE" || true)"
	if [ -z "$l" ] || [ -z "$o" ] || [ "$o" != "$from" ]; then return 0; fi
	git merge-base --is-ancestor "$o" "$l"
}

# publish_forget_stale: clear qs.publish.<v>.from when it is stale (publish_from_stale), saying so;
# otherwise nothing. The version release does the same with its own state (version_forget_stale).
# Arguments: none; reads REL_VERSION REL_RELEASE. Returns: 0.
publish_forget_stale() {
	publish_from_stale || return 0
	git config --unset-all "qs.publish.$REL_VERSION.from" 2>/dev/null || true
	say "$REL_RELEASE was not rebased: the stale publish state of $REL_VERSION is cleared (qs.publish.$REL_VERSION.from)"
	return 0
}

# publish_reset: git publicar --reset --version <v>: forget the publish state of REL_VERSION (git
# config qs.publish.<v>.from) after a confirmation (--yes skips it), like git release --reset.
# Refused, nothing changed, while a rebase is stopped (git publicar resumes it). Branches and tags
# are never touched.
# Arguments: none; reads REL_VERSION REL_TAG_GIVEN. Returns: 0; exits through die when refused or
# cancelled.
publish_reset() {
	local from
	[ "$REL_TAG_GIVEN" = 0 ] || die "--reset takes no tag: git publicar --reset --version <v>"
	! rebase_in_progress || die "a rebase is stopped: finish it (git rebase --continue, then git publicar --version $REL_VERSION) or give it up (git rebase --abort) first"
	from="$(git config "qs.publish.$REL_VERSION.from" 2>/dev/null || true)"
	if [ -z "$from" ]; then
		say "nothing to reset: no publish state for $REL_VERSION"
		return 0
	fi
	confirm "Forget the publish state of $REL_VERSION (qs.publish.$REL_VERSION.from = $from)?" || die "cancelled; nothing was changed"
	git config --unset-all "qs.publish.$REL_VERSION.from" 2>/dev/null || true
	say "publish state of $REL_VERSION forgotten (qs.publish.$REL_VERSION.from)"
	return 0
}

# publish_squash: git publicar with branches.flow = squash (ACs M1-M3): REL_RELEASE rebased onto
# develop (release-file conflicts solved, any other conflict stops with the steps), ONE
# single-parent commit on develop with its tree (publish_message), the tag moved onto that commit,
# one atomic push of develop + tag + the deletion of REL_RELEASE, then REL_RELEASE deleted locally.
# Re-running resumes: a stopped rebase of REL_RELEASE, a develop commit already made (its
# 'Squashed: <v>/RELEASE <tip>' line), a push that failed. A failure before the develop commit
# puts REL_RELEASE back where it was.
# Arguments: none; reads the REL_* variables of release_args. Returns: 0; exits through die on a
# refusal, a stop or a failure.
publish_squash() {
	local start base tip old remote dev landed=0 rebased=0 entry
	cd "$(git rev-parse --show-toplevel)"
	publish_forget_stale
	if rebase_in_progress; then
		[ "$(rebase_state head-name)" = "refs/heads/$REL_RELEASE" ] ||
			die "a rebase is stopped: finish it (git rebase --continue) or give it up (git rebase --abort), then run git publicar again"
		say "resuming the rebase of $REL_RELEASE onto $QS_BR_MAINLINE..."
		publish_rebase "$(rebase_state onto)"
	fi
	require_clean || die "working tree not clean: commit or stash first"
	fetch_origin
	exists_branch "$REL_RELEASE" || die "'$REL_RELEASE' does not exist: prepare it first with git release --version $REL_VERSION"
	for start in "$REL_RELEASE" "$QS_BR_MAINLINE"; do
		! checked_out_elsewhere "$start" || die "'$start' is checked out in another worktree: free it there first (git switch -)"
	done
	start="$(current_branch || true)"
	publish_local_release
	tip="$PUB_TIP"
	[ "$(branch_tip "$QS_BR_MAINLINE")" = diverged ] && die "$QS_BR_MAINLINE: local and origin diverged; pull it first"
	base="$(best_ref "$QS_BR_MAINLINE" || true)"
	[ -n "$base" ] || die "'$QS_BR_MAINLINE' does not exist"
	base="$(git rev-parse "$base^{commit}")"
	dev="$(git rev-parse -q --verify "refs/heads/$QS_BR_MAINLINE" || true)"
	if [ -n "$dev" ] && git log -1 --format=%B "$dev" | grep -qxF "Squashed: $REL_RELEASE $tip"; then
		landed=1 # resumed after the develop commit
	fi
	remote="$(publish_remote_tag)"
	if [ -n "$remote" ] && { [ "$landed" = 0 ] || [ "$remote" != "$dev" ]; }; then
		die "tag '$REL_TAG' is already on origin on another commit; give another: git publicar <tag> --version $REL_VERSION"
	fi
	entry="$(version_section "$tip" | sed '1d' | sed '/./,$!d')"
	[ -n "$entry" ] || echo "[rama] WARN: $QS_BR_CHANGELOG on $REL_RELEASE has no entry for $REL_VERSION" >&2
	echo "Release $REL_TAG ($REL_VERSION)"
	echo
	[ -z "$entry" ] || printf '%s\n\n' "$entry"
	if [ "$landed" = 1 ]; then
		echo "Plan: $REL_RELEASE is already on $QS_BR_MAINLINE as $(git rev-parse --short "$dev"): tag $REL_TAG there, push, delete $REL_RELEASE"
	else
		echo "Plan: $(git merge-base --is-ancestor "$base" "$tip" || echo "rebase $REL_RELEASE onto $QS_BR_MAINLINE, ")ONE commit on $QS_BR_MAINLINE (\"$(release_subject "$REL_TAG")\"), tag $REL_TAG on it$([ "$REL_PUSH" = 1 ] && has_origin && echo ", push $QS_BR_MAINLINE and $REL_TAG"), delete $REL_RELEASE"
	fi
	confirm "Publish $REL_VERSION as $REL_TAG?" || die "cancelled; nothing was changed"
	if [ "$landed" = 0 ]; then
		old="$tip"
		if ! git merge-base --is-ancestor "$base" "$tip"; then
			[ -n "$(git config "qs.publish.$REL_VERSION.from" 2>/dev/null || true)" ] ||
				git config "qs.publish.$REL_VERSION.from" "$(git rev-parse -q --verify "refs/remotes/origin/$REL_RELEASE" || echo "$old")"
			publish_rebase "$base"
			rebased=1
			tip="$(git rev-parse "refs/heads/$REL_RELEASE")"
		fi
		if ! publish_commit "$base" "$tip"; then
			if [ "$rebased" = 1 ]; then
				git checkout -q --detach
				git update-ref "refs/heads/$REL_RELEASE" "$old" "$tip"
				git config --unset "qs.publish.$REL_VERSION.from" 2>/dev/null || true
			fi
			git checkout -q "${start:-$REL_RELEASE}" 2>/dev/null || git checkout -q "$REL_RELEASE"
			die "the commit on $QS_BR_MAINLINE failed (see the hook messages above); nothing was changed"
		fi
		dev="$(git rev-parse HEAD)"
		say "$REL_RELEASE landed on $QS_BR_MAINLINE as ONE commit: $(git rev-parse --short "$dev")"
	else
		git checkout -q "$QS_BR_MAINLINE"
	fi
	publish_tag "$dev"
	if [ -z "$remote" ] && ! publish_push; then
		die "push failed: $QS_BR_MAINLINE and $REL_TAG are ready locally and $REL_RELEASE is kept. Fix the push and run git publicar --version $REL_VERSION again (it resumes)"
	fi
	git branch -q -D "$REL_RELEASE"
	git config --unset "qs.release.$REL_VERSION.tag" 2>/dev/null || true
	git config --unset "qs.publish.$REL_VERSION.from" 2>/dev/null || true
	say "published $REL_VERSION as $REL_TAG: one commit on $QS_BR_MAINLINE; $REL_RELEASE deleted"
	if [ "$REL_PUSH" != 1 ] && has_origin; then
		say "not pushed (--no-push): git push --atomic origin $QS_BR_MAINLINE refs/tags/$REL_TAG :refs/heads/$REL_RELEASE"
	fi
	return 0
}

cmd_publicar() { # step 2: RELEASE merged into develop, tagged, pushed, deleted
	local tip base notes msg pushed=0 merged=0 root rels
	# why: with several RELEASE branches, which one reaches develop is said explicitly, one at a time
	rels="$(release_branches)"
	if [ "$(grep -c . <<<"$rels")" -gt 1 ] && ! printf ' %s' "$@" | grep -qE ' --version(=| )'; then
		die "there are $(grep -c . <<<"$rels") RELEASE branches (${rels//$'\n'/ }); publish one at a time: git publicar --version <v>  (or join them first: git combinar)"
	fi
	release_args "$@"
	REL_RELEASE="$REL_VERSION/$QS_BR_RELEASE_LEAF"
	if [ "$REL_RESET" = 1 ]; then
		publish_reset
		return 0
	fi
	if [ "${QS_BR_FLOW:-merge}" = squash ]; then
		publish_squash
		return
	fi
	require_clean || die "working tree not clean: commit or stash first"
	fetch_origin
	exists_branch "$REL_RELEASE" || die "'$REL_RELEASE' does not exist: prepare it first with git release --version $REL_VERSION"
	tip="$(branch_tip "$REL_RELEASE")"
	[ "$tip" = diverged ] && die "$REL_RELEASE: local and origin diverged; pull it first (git checkout $REL_RELEASE && git pull)"
	base="$(best_ref "$QS_BR_MAINLINE" || true)"
	[ -n "$base" ] || die "'$QS_BR_MAINLINE' does not exist"
	[ "$(branch_tip "$QS_BR_MAINLINE")" = diverged ] && die "$QS_BR_MAINLINE: local and origin diverged; pull it first"
	if git merge-base --is-ancestor "$tip" "$base"; then
		merged=1 # resumed after the merge
	elif ! git merge-base --is-ancestor "$base" "$tip"; then
		die "$QS_BR_MAINLINE has $(git rev-list --count "$tip..$base") commit(s) that $REL_RELEASE lacks: git checkout $REL_RELEASE && git merge $QS_BR_MAINLINE, review again, then git publicar"
	fi
	[ -n "$REL_TAG_AT" ] && [ "$REL_TAG_AT" != "$tip" ] && die "tag '$REL_TAG' already exists on another commit; give another: git publicar <tag>"
	root="$(git rev-parse --show-toplevel)"
	notes="$(git rev-parse --absolute-git-dir)/quality-suite/RELEASE_NOTES.md"
	mkdir -p "$(dirname "$notes")"
	{
		echo "Release $REL_TAG ($REL_VERSION)"
		echo
		if [ -n "$QS_BR_CHANGELOG" ] && git cat-file -e "$tip:$QS_BR_CHANGELOG" 2>/dev/null; then
			git show "$tip:$QS_BR_CHANGELOG" | awk -v v="$REL_VERSION" '
        /^## / { if (on) exit; on = (index($0, "## [" v "]") == 1 || index($0, "## " v " ") == 1); next }
        on { print }' | sed '/./,$!d'
		fi
	} >"$notes"
	[ "$(grep -c . "$notes")" -gt 1 ] || echo "[rama] WARN: $QS_BR_CHANGELOG on $REL_RELEASE has no entry for $REL_VERSION" >&2
	cat "$notes"
	echo
	echo "Plan: $REL_RELEASE -> $QS_BR_MAINLINE (\"$(release_subject "$REL_TAG")\"), tag $REL_TAG$([ "$REL_PUSH" = 1 ] && has_origin && echo ", push $QS_BR_MAINLINE and $REL_TAG"), delete $REL_RELEASE"
	confirm "Publish $REL_VERSION as $REL_TAG?" || die "cancelled; nothing was changed"

	if exists_ref "refs/heads/$QS_BR_MAINLINE"; then
		git checkout -q "$QS_BR_MAINLINE"
	else git checkout -q -b "$QS_BR_MAINLINE" --track "origin/$QS_BR_MAINLINE"; fi
	[ "$(git rev-parse HEAD)" = "$(git rev-parse "$base")" ] || git merge -q --ff-only "$base"
	if [ "$merged" = 0 ]; then
		msg="$(git rev-parse --absolute-git-dir)/quality-suite/RELEASE_MSG"
		{
			release_subject "$REL_TAG"
			echo
			echo
			echo "Release $REL_TAG of $REL_VERSION: $(git rev-list --count --no-merges "$tip" "^$base") commit(s)."
			echo "Refs: $REL_RELEASE -> $QS_BR_MAINLINE"
		} >"$msg"
		exists_ref "refs/heads/$REL_RELEASE" || git branch -q --no-track "$REL_RELEASE" "$tip"
		quiet_merge merge -q --no-ff --no-commit "$REL_RELEASE" ||
			{
				git merge --abort 2>/dev/null || true
				die "merge into $QS_BR_MAINLINE failed; nothing was changed"
			}
		if ! git commit -q --cleanup=strip -F "$msg"; then
			git merge --abort 2>/dev/null || true
			die "the merge commit was rejected (see the hook messages above); nothing was changed"
		fi
		say "$REL_RELEASE merged into $QS_BR_MAINLINE"
	fi
	if [ -z "$REL_TAG_AT" ]; then
		git tag -a --cleanup=whitespace -F "$notes" "$REL_TAG" "$tip"
		say "tag $REL_TAG created on $REL_RELEASE"
	fi
	if [ "$REL_PUSH" = 1 ] && has_origin; then
		git push -q origin "$QS_BR_MAINLINE" "refs/tags/$REL_TAG" ||
			die "push failed: $QS_BR_MAINLINE and $REL_TAG are ready locally and $REL_RELEASE is kept. Fix the push and run git publicar again (it resumes)"
		pushed=1
		say "pushed $QS_BR_MAINLINE and $REL_TAG"
		exists_ref "refs/remotes/origin/$REL_RELEASE" && git push -q origin --delete "$REL_RELEASE"
	fi
	exists_ref "refs/heads/$REL_RELEASE" && git branch -q -D "$REL_RELEASE"
	git config --unset "qs.release.$REL_VERSION.tag" 2>/dev/null || true
	say "published $REL_VERSION as $REL_TAG; $REL_RELEASE deleted"
	[ "$pushed" = 1 ] || { has_origin && say "not pushed (--no-push): git push origin $QS_BR_MAINLINE $REL_TAG && git push origin --delete $REL_RELEASE"; }
	return 0
}
