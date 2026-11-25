#!/usr/bin/env bash
# rama/release.sh - git changelog / git release (branch analysis, changelog, notes) (module of git-rama.sh).
# Sourced by git-rama.sh after its option parsing; defines functions and constants only.
# why: set -euo pipefail and the variables shared between modules come from git-rama.sh
# shellcheck disable=SC2034,SC2119,SC2120,SC2164

# shellcheck disable=SC1091
. "$DIR/rama/release-common.sh"

# --- git changelog / git release / git publicar ------------------------------------------------
# A version tree '<version>/...' is released from its top '<version>/ORIGINAL', in two steps:
#   git release   every branch of the tree is compared with its nearest ORIGINAL (siblings with the
#                 ORIGINAL of their level, children with theirs, recursively); a branch with nothing
#                 outside it is integrated (deleted); a branch with commits that never reached it is
#                 set aside as 'unmerged/<name>' (with a warning). '<version>/ORIGINAL' becomes
#                 '<version>/RELEASE', which gets three commits: the version (VERSION, pom.xml),
#                 CHANGELOG.md (Common Changelog) and the README badge. The team reviews RELEASE.
#   git publicar  RELEASE is merged into develop, tagged, pushed and deleted.
# The changelog comes from the history of '<version>/ORIGINAL' (merge commits of 'git integra'
# carry 'Refs: <branch> -> <parent>'), so it works even after final branches were deleted.

all_branches() { # local and origin branch names, deduplicated
	{
		git for-each-ref --format='%(refname:lstrip=2)' refs/heads/
		git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin/ | { grep -vx 'HEAD' || true; }
	} | LC_ALL=C sort -u
}
# the one tip of a branch: local and origin agree (one contains the other); 'diverged' otherwise
branch_tip() {
	local b="$1" l="" r=""
	exists_ref "refs/heads/$b" && l="$(git rev-parse "refs/heads/$b")"
	exists_ref "refs/remotes/origin/$b" && r="$(git rev-parse "refs/remotes/origin/$b")"
	if [ -n "$l" ] && [ -n "$r" ]; then
		if git merge-base --is-ancestor "$l" "$r"; then
			echo "$r"
		elif git merge-base --is-ancestor "$r" "$l"; then
			echo "$l"
		else echo diverged; fi
	else echo "${l:-$r}"; fi
}
# nearest existing ORIGINAL above a branch of the tree (its parent in the model, or higher up
# when that one is gone); the top of the tree for anything else
nearest_original() {
	local b="$1" p
	p="$(branch_node "$b")"
	is_parent_branch "$b" || p="$b"
	while case "$p" in */*) true ;; *) false ;; esac do
		p="${p%/*}"
		if [ "$p/$QS_BR_LEAF" != "$b" ] && exists_branch "$p/$QS_BR_LEAF"; then
			echo "$p/$QS_BR_LEAF"
			return
		fi
	done
	echo "$REL_TOP"
}
# a free name for a branch set aside: no ref with that name, under it, or above it (git stores
# refs as files and folders, so 'a/b' blocks 'a/b/c' and the other way round)
name_taken() {
	local n="$1" p="$1"
	exists_branch "$n" || has_branches_under "$n" && return 0
	while case "$p" in */*) true ;; *) false ;; esac do
		p="${p%/*}"
		exists_branch "$p" && return 0
	done
	case "$REL_PLANNED" in *$'\n'"$n"$'\n'*) return 0 ;; esac
	return 1
}
archive_name() {
	local base="$QS_BR_ARCHIVE/$1" n i
	n="$base"
	i=2
	while name_taken "$n" && [ "$i" -le 9 ]; do
		n="$base-$i"
		i=$((i + 1))
	done
	name_taken "$n" && n="$QS_BR_ARCHIVE-$(date +%Y%m%d%H%M%S)/$1"
	name_taken "$n" && return 1
	echo "$n"
}

# Markdown section of the history of <tip> not reachable from the excluded commits, following first
# parents; each merge becomes a sub-section with what it brought. Output on stdout.
#   cl_section <depth> <tip> <exclude>...
cl_section() {
	local depth="$1" tip="$2"
	shift 2
	local ex=() e H P h s an ad nm body src sub hd items="" subs="" line p1 p2
	for e in "$@"; do ex+=("^$e"); done
	while IFS=$'\x1f' read -r -d $'\x1e' H P h s an ad nm body; do
		H="${H#$'\n'}"
		[ -n "$H" ] || continue
		read -r p1 p2 _ <<<"$P"
		if [ -n "${p2:-}" ]; then
			src="$(sed -n 's/^Refs: \([^ ]*\) -> .*/\1/p' <<<"$body" | head -n1)"
			[ -n "$src" ] || src="$(sed -n "s/^Merge \(remote-tracking \)\{0,1\}branch '\(origin\/\)\{0,1\}\([^']*\)'.*/\3/p" <<<"$body" | head -n1)"
			[ -n "$src" ] || src="merge $h"
			sub="$(cl_section $((depth + 1)) "$p2" "$@" "$p1")"
			[ -n "$sub" ] || continue # a sync merge (parent into child): nothing new
			hd="$(printf '%*s' $((depth + 1)) '' | tr ' ' '#')"
			[ "$depth" -ge 5 ] && hd="######"
			subs="$subs"$'\n'"$hd $src"$'\n'"Integrated $ad by $an ($h): $s"$'\n'"$sub"$'\n'
		else
			src="$(sed -n 's/^Refs: \([^ ]*\) -> .*/\1/p' <<<"$body" | head -n1)"
			line="- $h $s ($an, $ad)${nm:+ [Norms: $nm]}"
			if [ -n "$src" ] && grep -q '^Commits:' <<<"$body"; then # squash integration
				hd="$(printf '%*s' $((depth + 1)) '' | tr ' ' '#')"
				subs="$subs"$'\n'"$hd $src (squashed)"$'\n'"Integrated $ad by $an ($h): $s"$'\n'
				subs="$subs$(sed -n '/^Commits:/,/^$/p' <<<"$body" | grep '^- ' || true)"$'\n'
			else
				items="$items$line"$'\n'
			fi
		fi
	done < <(git log --first-parent --reverse --date=short \
		--format='%H%x1f%P%x1f%h%x1f%s%x1f%an%x1f%ad%x1f%(trailers:key=Norms,valueonly,separator=%x2c)%x1f%B%x1e' \
		"$tip" ${ex[@]+"${ex[@]}"} --)
	if [ -n "$items" ]; then
		[ "$depth" = 1 ] && [ -n "$subs" ] && printf '## %s (direct commits)\n' "$REL_TOP"
		printf '%s' "$items"
	fi
	[ -n "$subs" ] && printf '%s' "$subs"
	return 0
}

# Analyse the tree of a version: fills REL_* variables, prints nothing.
release_analyse() {
	local v="$1" b p tb tp n
	REL_TOP="$v/$QS_BR_LEAF"
	REL_RELEASE="$v/$QS_BR_RELEASE_LEAF"
	REL_ERRORS=() REL_OK=() REL_ARCHIVE=() REL_DELETE_LOCAL=() REL_DELETE_REMOTE=() REL_PLANNED=$'\n'
	REL_TIP="" REL_BASE="" REL_CL_BASE="" REL_RESUME=0
	exists_branch "$REL_TOP" || {
		REL_ERRORS+=("'$REL_TOP' does not exist (git arbol $v)")
		return 0
	}
	REL_TIP="$(branch_tip "$REL_TOP")"
	[ "$REL_TIP" = diverged ] && REL_ERRORS+=("$REL_TOP: local and origin diverged; run git subir on it first")
	REL_BASE="$(best_ref "$QS_BR_MAINLINE" || true)"
	[ -n "$REL_BASE" ] || REL_ERRORS+=("'$QS_BR_MAINLINE' does not exist")
	[ "$REL_TIP" = diverged ] || REL_CL_BASE="$REL_BASE"
	if exists_ref "refs/heads/$QS_BR_MAINLINE" && exists_ref "refs/remotes/origin/$QS_BR_MAINLINE" &&
		[ "$(branch_tip "$QS_BR_MAINLINE")" = diverged ]; then
		REL_ERRORS+=("$QS_BR_MAINLINE: local and origin diverged; pull it first")
	fi
	if [ "${#REL_ERRORS[@]}" -eq 0 ]; then
		if git merge-base --is-ancestor "$REL_TIP" "$REL_BASE"; then
			REL_ERRORS+=("$REL_TOP is already inside $QS_BR_MAINLINE (integrated with git integra?): nothing to release")
		elif ! git merge-base --is-ancestor "$REL_BASE" "$REL_TIP"; then
			REL_ERRORS+=("$QS_BR_MAINLINE has $(git rev-list --count "$REL_TIP..$REL_BASE") commit(s) that $REL_TOP lacks; bring them in first: git checkout $REL_TOP && git subir")
		fi
	fi
	if exists_branch "$REL_RELEASE" && [ "${#REL_ERRORS[@]}" -eq 0 ]; then
		local rt
		rt="$(branch_tip "$REL_RELEASE")"
		if [ "$rt" != diverged ] && git merge-base --is-ancestor "$REL_TIP" "$rt"; then
			REL_RESUME=1 # an interrupted git release: go on from there
		else
			REL_ERRORS+=("'$REL_RELEASE' exists and does not contain $REL_TOP (left by an earlier release?); publish or delete it first")
		fi
	fi
	# every branch of the tree against its nearest ORIGINAL
	while IFS= read -r b; do
		[ -n "$b" ] && [ "$b" != "$REL_TOP" ] && [ "$b" != "$REL_RELEASE" ] || continue
		testing_release_ok "$b" && {
			REL_OK+=("$b"$'\t'"$(nearest_original "$b")")
			continue
		} # TESTING sandbox (O7)
		tb="$(branch_tip "$b")"
		p="$(nearest_original "$b")"
		tp="$(branch_tip "$p")"
		if [ "$tb" = diverged ] || [ "$tp" = diverged ]; then
			REL_ERRORS+=("$([ "$tb" = diverged ] && echo "$b" || echo "$p"): local and origin diverged; run git subir on it first")
			continue
		fi
		n="$(git rev-list --count "$tp..$tb")"
		if [ "$n" = 0 ]; then
			REL_OK+=("$b"$'\t'"$p")
		else
			rel_archive_add "$b" "$p" "$n" || continue
		fi
	done < <(all_branches | awk -v p="$v/" 'index($0, p) == 1')
	# the branches to delete afterwards, and the branches checked out in another worktree
	rel_check_branches "$v" "$QS_BR_MAINLINE" "$REL_TOP"
	return 0
}

release_changelog() { # <tag> -> markdown on stdout: what each branch brought (for the review)
	local tag="$1" b p n entry
	echo "# Release $tag"
	echo
	echo "From \`$REL_TOP\` ($(git rev-parse --short "$REL_TIP")) into \`$QS_BR_MAINLINE\`" \
		"($(git rev-parse --short "$REL_CL_BASE")): $(git rev-list --count --no-merges "$REL_TIP" "^$REL_CL_BASE") commit(s)."
	echo
	cl_section 1 "$REL_TIP" "$REL_CL_BASE" | sed '1{/^$/d}'
	if [ "${#REL_ARCHIVE[@]}" -gt 0 ]; then
		echo
		echo "## Not included: never integrated into their ORIGINAL"
		for entry in "${REL_ARCHIVE[@]}"; do
			IFS=$'\t' read -r b n p _ <<<"$entry"
			echo
			echo "### $b -> set aside as $n"
			git log --no-merges --date=short --format='- %h %s (%an, %ad)' "$(branch_tip "$p")..$(branch_tip "$b")"
		done
	fi
}

# The CHANGELOG.md entry of the release (Common Changelog), from the suite image; semver advice on stderr.
release_notes() { # release_notes [--write]
	local root
	if [ "${REL_UNION:-0}" = 1 ]; then # why: the squash version release unites the OT sections
		version_union_notes "$@"
		return
	fi
	if [ "${REL_UNION:-0}" = combine ]; then # why: git combinar (flow = squash) unites the RELEASE sections
		combine_union_notes "$@"
		return
	fi
	root="$(git rev-parse --show-toplevel)"
	engine "$root" release-notes --version "$REL_VERSION" --tip "$REL_TIP" --base "$REL_CL_BASE" --tag "$REL_TAG" "$@"
}

release_report() { # <tag>: checks and plan, for the preview and before running
	local tag="$1"
	rel_print_report "$REL_TOP is consistent (local/origin) and contains $QS_BR_MAINLINE" "contained in "
	[ "$REL_RESUME" = 1 ] && echo "[ok] $REL_RELEASE exists and contains $REL_TOP: git release resumes from there"
	echo
	echo "## Plan"
	echo
	local i=1
	if [ "${#REL_ARCHIVE[@]}" -gt 0 ]; then
		echo "$i. set aside ${#REL_ARCHIVE[@]} branch(es) as $QS_BR_ARCHIVE/... (local and origin)"
		i=$((i + 1))
	fi
	echo "$i. git release: $REL_TOP -> $REL_RELEASE, with up to three commits: $(version_subject "$REL_VERSION")," \
		"docs(changelog): $REL_VERSION ($QS_BR_CHANGELOG), docs(readme): version $REL_VERSION"
	i=$((i + 1))
	echo "$i. git release: push $REL_RELEASE; delete the rest of the tree: ${#REL_DELETE_LOCAL[@]} local branch(es)$(has_origin && [ "$REL_PUSH" = 1 ] && echo ", ${#REL_DELETE_REMOTE[@]} on origin")"
	i=$((i + 1))
	echo "$i. you: review $QS_BR_CHANGELOG on $REL_RELEASE (edit and commit there if needed)"
	i=$((i + 1))
	echo "$i. git publicar: $REL_RELEASE merged into $QS_BR_MAINLINE (\"$(release_subject "$tag")\"), tag $tag, push, $REL_RELEASE deleted"
}

release_subject() {
	local s="chore(release): $1"
	[ "${#s}" -le "${QS_COMMIT_SUBJECT_MAX:-50}" ] || s="chore: release $1"
	[ "${#s}" -le "${QS_COMMIT_SUBJECT_MAX:-50}" ] || s="chore: $1"
	printf '%s' "$s"
}

# release_args <argument>...: read the options of git changelog / release / publicar.
# Sets REL_TAG REL_TAG_GIVEN REL_VERSION REL_OT REL_OUT REL_PUSH REL_PREVIEW REL_RESET REL_TAG_AT.
# REL_OT ('<v>/<ot>', flow = squash only) comes from --ot or, without --version, from a current branch
# inside an OT ('<v>/<ot>/...'); empty means the version release. REL_RESET is 1 with --reset.
# Returns: 0; exits through die on a bad option, version, OT or tag.
release_args() {
	REL_TAG="" REL_TAG_GIVEN=0 REL_VERSION="" REL_OT="" REL_OUT="" REL_PUSH=1 REL_PREVIEW=0 REL_RESET=0
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--reset) REL_RESET=1 ;;
		--version)
			REL_VERSION="${2:?--version needs a version}"
			shift
			;;
		--version=*) REL_VERSION="${1#--version=}" ;;
		--ot)
			REL_OT="${2:?--ot needs <version>/<ot>}"
			shift
			;;
		--ot=*) REL_OT="${1#--ot=}" ;;
		-o | --output)
			REL_OUT="${2:?$1 needs a file}"
			shift
			;;
		--no-push) REL_PUSH=0 ;;
		-n | --preview) REL_PREVIEW=1 ;;
		-*) die "unknown option '$1'" ;;
		*)
			[ -z "$REL_TAG" ] || die "one tag only (got '$REL_TAG' and '$1')"
			REL_TAG="$1"
			REL_TAG_GIVEN=1
			;;
		esac
		shift
	done
	ot_release_target
	if [ -z "$REL_VERSION" ]; then
		local cur
		cur="$(current_branch || true)"
		if [ -n "$cur" ] && ! is_mainline "$cur" && ! is_archived_branch "$cur" && valid_branch_name "$cur" >/dev/null 2>&1; then
			REL_VERSION="$(branch_version "$cur")"
		else
			local tops
			tops="$(all_branches | awk -v l="/$QS_BR_LEAF" -v r="/$QS_BR_RELEASE_LEAF" '(gsub(l "$", "") || gsub(r "$", "")) && index($0, "/") == 0' | sort -u)"
			[ "$(grep -c . <<<"$tops")" = 1 ] && REL_VERSION="$tops"
			[ -n "$REL_VERSION" ] || die "which version? add --version <version> (version trees: ${tops//$'\n'/ })"
		fi
	fi
	REL_VERSION="${REL_VERSION%%/*}"
	printf '%s' "$REL_VERSION" | grep -qE -- "$(_br_level_re 1)" || die "'$REL_VERSION' is not a version of the branch model (branches.levels[0])"
	# why: git release keeps the tag it was given for git publicar (and the changelog link)
	[ -n "$REL_TAG" ] || REL_TAG="$(git config "qs.release.$REL_VERSION.tag" 2>/dev/null || true)"
	[ -n "$REL_TAG" ] || REL_TAG="$(render_tag "$REL_VERSION/$QS_BR_LEAF")"
	git check-ref-format "refs/tags/$REL_TAG" || die "'$REL_TAG' is not a valid tag name"
	LC_ALL=C grep -q '[^ -~]' <<<"$REL_TAG" && die "the tag must be ASCII: '$REL_TAG'"
	if exists_ref "refs/tags/$REL_TAG"; then REL_TAG_AT="$(git rev-parse "refs/tags/$REL_TAG^{commit}")"; else REL_TAG_AT=""; fi
	return 0
}

cmd_changelog() { # preview: changelog + release notes + checks + plan; changes nothing
	release_args "$@"
	[ "$REL_RESET" = 0 ] || die "--reset belongs to git release (it changes state)"
	if [ -n "$REL_OT" ]; then
		ot_changelog_preview
		return
	fi
	if [ "${QS_BR_FLOW:-merge}" = squash ]; then
		version_changelog_preview
		return
	fi
	fetch_origin
	if ! exists_branch "$REL_VERSION/$QS_BR_LEAF" && exists_branch "$REL_VERSION/$QS_BR_RELEASE_LEAF"; then
		say "$REL_VERSION is prepared on $REL_VERSION/$QS_BR_RELEASE_LEAF (git release done): review it, then git publicar"
		return 0
	fi
	release_analyse "$REL_VERSION"
	[ -n "$REL_TAG_AT" ] && [ "${#REL_ERRORS[@]}" -eq 0 ] && [ "$REL_TAG_AT" != "$REL_TIP" ] &&
		REL_ERRORS+=("tag '$REL_TAG' already exists on another commit; choose another name")
	if [ -n "$REL_TIP" ] && [ "$REL_TIP" != diverged ] && [ -n "$REL_CL_BASE" ]; then
		release_changelog "$REL_TAG"
		echo
		if [ -n "$REL_OUT" ]; then
			case "$REL_OUT" in /* | [A-Za-z]:*) ;; *) REL_OUT="${GIT_PREFIX:-}$REL_OUT" ;; esac
			release_changelog "$REL_TAG" >"$REL_OUT"
			say "changelog written to $REL_OUT"
		fi
		echo "## $QS_BR_CHANGELOG entry (Common Changelog)"
		echo
		release_notes 2>&1 || echo "(the suite image could not run: no release notes preview)"
		echo
	fi
	release_report "$REL_TAG"
	[ "${#REL_ERRORS[@]}" -eq 0 ] || {
		echo
		say "not releasable yet: fix the [!!] items above"
		return 1
	}
	echo
	say "preview only, nothing changed. Next: git release $REL_TAG --version $REL_VERSION"
}

# What to tell the human when a release commit fails: git release resumes, git combinar starts over.
REL_AGAIN="fix it, then run the same git release again (it resumes)"

# commit_files <subject> <file>...: commit those files if they changed (the hooks run).
# Arguments: $1 the subject; $2... the files (missing ones are skipped). Exit status: 0; ends the
# script through die when a hook rejects the commit (the message ends with REL_AGAIN).
commit_files() {
	local subject="$1"
	shift
	local f add=()
	for f in "$@"; do [ -n "$f" ] && [ -e "$f" ] && add+=("$f"); done
	[ "${#add[@]}" -gt 0 ] || return 0
	git add -- "${add[@]}"
	git diff --cached --quiet && return 0
	git commit -q -m "$subject" || die "the commit '$subject' was rejected (see the hook messages); $REL_AGAIN"
	say "committed: $subject"
}

cmd_release() { # step 1: RELEASE branch with version, changelog and README badge; tree deleted
	local root
	release_args "$@"
	if [ "$REL_RESET" = 1 ]; then
		[ "$REL_TAG_GIVEN" = 0 ] || die "--reset takes no tag: git release --reset --version <v>"
		[ -z "$REL_OT" ] || die "--reset clears a version release: drop --ot"
		version_reset
		return 0
	fi
	[ "$REL_PREVIEW" = 1 ] && {
		cmd_changelog "$@"
		return
	}
	if [ -n "$REL_OT" ]; then
		ot_release
		return
	fi
	if [ "${QS_BR_FLOW:-merge}" = squash ]; then
		version_release
		return
	fi
	require_clean || die "working tree not clean: commit or stash first"
	fetch_origin
	if ! exists_branch "$REL_VERSION/$QS_BR_LEAF" && exists_branch "$REL_VERSION/$QS_BR_RELEASE_LEAF"; then
		say "$REL_VERSION/$QS_BR_RELEASE_LEAF is already prepared. Review $QS_BR_CHANGELOG there, then: git publicar --version $REL_VERSION"
		return 0
	fi
	release_analyse "$REL_VERSION"
	[ -n "$REL_TAG_AT" ] && [ "${#REL_ERRORS[@]}" -eq 0 ] && [ "$REL_TAG_AT" != "$REL_TIP" ] &&
		REL_ERRORS+=("tag '$REL_TAG' already exists on another commit; choose another name")
	if [ "${#REL_ERRORS[@]}" -gt 0 ]; then
		release_report "$REL_TAG" >&2
		die "nothing was changed"
	fi
	release_changelog "$REL_TAG"
	echo
	echo "## $QS_BR_CHANGELOG entry (Common Changelog)"
	echo
	release_notes 2>&1 || die "the suite image could not run (Docker?): it writes $QS_BR_CHANGELOG; nothing was changed"
	echo
	release_report "$REL_TAG"
	echo
	confirm "Prepare $REL_VERSION on $REL_RELEASE?" || die "cancelled; nothing was changed"
	git config "qs.release.$REL_VERSION.tag" "$REL_TAG"
	root="$(git rev-parse --show-toplevel)"

	# 1. RELEASE at the tip of the version ORIGINAL (kept until the end: a failure leaves the tree)
	exists_ref "refs/heads/$REL_RELEASE" || git branch -q --no-track "$REL_RELEASE" "$([ "$REL_RESUME" = 1 ] && branch_tip "$REL_RELEASE" || echo "$REL_TIP")"
	git checkout -q "$REL_RELEASE"
	# 2.-4. the version (a SNAPSHOT pom becomes the release version), CHANGELOG.md, the README badge
	release_commits
	# 5. publish RELEASE before touching any remote branch
	if [ "$REL_PUSH" = 1 ] && has_origin; then
		git push -q -u origin "$REL_RELEASE" || die "push of $REL_RELEASE failed; the tree is untouched. Fix it and run git release again (it resumes)"
	fi
	# 6. branches never integrated: set aside as unmerged/<name>
	release_set_aside
	# 7. the rest of the tree (integrated branches, old names, the ORIGINAL)
	if [ "$REL_PUSH" = 1 ] && has_origin && [ "${#REL_DELETE_REMOTE[@]}" -gt 0 ]; then
		release_delete_remote "${REL_DELETE_REMOTE[@]}"
	fi
	[ "${#REL_DELETE_LOCAL[@]}" -gt 0 ] && git branch -q -D "${REL_DELETE_LOCAL[@]}"
	say "$REL_VERSION prepared on $REL_RELEASE: ${#REL_DELETE_LOCAL[@]} branch(es) of the tree deleted, ${#REL_ARCHIVE[@]} set aside"
	echo
	echo "Review now (you are on $REL_RELEASE):"
	echo "  git show --stat HEAD~2..HEAD          # the release commits"
	echo "  \$EDITOR $QS_BR_CHANGELOG               # wording, order; then: git commit -am 'docs(changelog): review'"
	echo "When it is right:"
	echo "  git publicar                          # merge into $QS_BR_MAINLINE, tag $REL_TAG, push, delete $REL_RELEASE"
	return 0
}
