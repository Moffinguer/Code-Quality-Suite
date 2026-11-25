#!/usr/bin/env bash
# git-rama.sh - branch model commands, installed as git aliases (see git-flow-lib.sh):
#   git np  <name>        new PARENT branch: '<node>/<name>/ORIGINAL' (from develop: '<version>/ORIGINAL',
#                         a Semantic Versioning version; 'git np patch|minor|major' takes the next one
#                         after the highest tag / version tree / VERSION, and a first commit writes the
#                         version to VERSION, the pom.xml files and package.json)
#                         --migracion (from develop only): also creates <version>/MIGRATION, as
#                         git migracion does, and checks it out
#   git nr <name>        new FINAL branch:  '<node>/<name>' (sibling of the current ORIGINAL's children)
#                         --from <ORIGINAL|develop>: use that branch instead of the current one
#                         (agents in their own worktree, where the ORIGINAL is checked out elsewhere)
#   git convertir-padre   turn the current final branch into a parent ('x/y' -> 'x/y/ORIGINAL')
#   git subir             final: rebase onto its ORIGINAL + push --force-with-lease
#                         ORIGINAL: merge its parent in if behind, then push (never rebased: shared)
#   git integra           final -> its ORIGINAL (rebase, then merge or squash); ORIGINAL -> parent
#                         ORIGINAL (merge --no-ff; children must be integrated first); the top
#                         '<version>/ORIGINAL' gets the version tag and is merged into develop
#                         (branches.flow = merge). flow = squash: the branch is rebased onto its
#                         ORIGINAL and lands there as ONE commit (Commits:, Files:, Refs:,
#                         Squashed:), then it is deleted; '<v>/<ot>/ORIGINAL' goes up by git release
#                         -m "<subject>" [-m "<body>"]: message without opening the editor (agents)
#   git arbol [prefix]    the branch tree: parents, siblings, children, merged/behind state
#                         (flow = squash: '= integrated as <sha>', TESTING, RELEASE marked)
#                         --limpiar [--yes]: delete the integrated branches (local and origin)
#   git estructura [file] the whole tree read from stdin (or files): creates what is missing from
#   (git es)              its parent, checks what exists (never recreates), adds new siblings; a new
#                         version tree gets its version commit (VERSION, pom.xml) like git np.
#                         -n/--dry-run: only show the plan; --push: push the branches of the
#                         structure that are not on origin yet (new ones and local-only ones);
#                         --convertir: turn final branches that need children into parents
#   git changelog [tag]   preview of a release: changelog per branch (from the commits in the
#                         version ORIGINAL), recursive check of the tree, the CHANGELOG.md entry
#                         (Common Changelog) with semver advice, plan. Changes nothing.
#                         --version <v> (default: the version of the current branch), -o <file>
#   git release [tag]     step 1 of a release: branches not integrated into their ORIGINAL are set
#                         aside as 'unmerged/<name>'; '<version>/ORIGINAL' becomes '<version>/RELEASE'
#                         with the version commit, CHANGELOG.md and the README badge (separate
#                         commits); RELEASE is pushed and the rest of the tree deleted. Review it.
#                         --version <v>, --yes, --no-push, -n (= changelog)
#                         branches.flow = squash, inside '<v>/<ot>/...' or with --ot <v>/<ot>: the OT
#                         release instead: '<v>/<ot>/RELEASE' = the OT ORIGINAL tip + one
#                         docs(changelog) commit with the OT lines, write the hidden ref branches.ot_ref (not a tag) at the OT
#                         ORIGINAL tip, RELEASE and the ref pushed, the OT subtree deleted (resumable);
#                         git changelog there previews it. On '<v>/ORIGINAL', develop or with
#                         --version <v>: the version release, refused while an OT lacks its RELEASE;
#                         '<v>/RELEASE' = '<v>/ORIGINAL' + every OT RELEASE squashed in as one commit (oldest first),
#                         version, CHANGELOG.md (union of the OT sections) and badge commits, local
#                         tag on its tip, one atomic push, OT RELEASEs and '<v>/ORIGINAL' deleted
#                         (resumable; after a conflict: git commit, then git release).
#                         --reset --version <v> [--yes]: forgets the resume state of a version
#                         release given up (refused while '<v>/RELEASE' exists); a release whose
#                         '<v>/RELEASE' was deleted by hand is also forgotten by the next git release
#   git publicar [tag]    step 2: '<version>/RELEASE' merged into develop, tagged (annotated with its
#                         CHANGELOG.md entry), pushed, and deleted. --version <v>, --yes, --no-push
#                         branches.flow = squash: '<v>/RELEASE' rebased onto develop (conflicts on
#                         release-owned lines solved: badge, version, CHANGELOG entries; any other
#                         conflict stops with the steps, re-run resumes), ONE commit on develop
#                         (changelog entry, Commits:, Files:, Refs:, Squashed:, Squashes:), the tag
#                         moved onto it, one atomic push of develop + tag + the deletion of RELEASE
#                         on origin. --reset --version <v> [--yes]: forgets the publish state kept
#                         while RELEASE is rebased (refused while a rebase is stopped); a state left
#                         by 'git rebase --abort' is also forgotten by the next git publicar
#   git nueva-version <v> new version tree '<v>/ORIGINAL' next to the others, from any branch
#   (git nv)              (--from <branch>, default the current one), with its version commit; the
#                         branches below that branch are copied under '<v>/' keeping their path below
#                         the version, each with its work and merged with its new parent;
#                         --arbol-completo: every branch of that version tree. -n: only the plan
#   git combinar          several '<v>/RELEASE' into one: asks yes/no for each and the version; on
#                         develop, one squash commit per RELEASE (creation order, oldest first) with
#                         only its own changes (develop merged in first, as a temporary commit, when
#                         a RELEASE lacks it), then the version, CHANGELOG.md and README badge of
#                         '<version>/RELEASE'; the ones combined are kept as 'unmerged/<v>/RELEASE'.
#                         branches.flow = squash: the entry is the union of the reviewed sections of
#                         the combined RELEASEs, each squash has its Files: block, and their local
#                         version tags are deleted; git publicar then lands it as ONE commit
#                         --version <v>, --incluir <v1,v2...>, --yes; a RELEASE that a later chosen
#                         one already holds (ancestor, commits listed in its history, or the same
#                         changes) is not squashed again; --contenida <v1,v2...> says so by hand for
#                         versions whose content the later one took in with its own resolution
#   git repo-files [NAME] the standard repository files that are missing (README, CHANGELOG, VERSION,
#                         CONTRIBUTING, ... DEVELOPMENT), filled from git history and pom.xml; never
#                         overwrites; --force NAME regenerates one; -n shows the plan
# Long names: git nueva-padre / git nueva-final. Options: --yes (no prompts), --force.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$(cd "$DIR/.." && pwd)"
HOOK_ENV="$(git rev-parse --path-format=absolute --git-path hooks 2>/dev/null)/quality-suite.env"
# shellcheck disable=SC1090
[ -f "$HOOK_ENV" ] && {
	set -a
	. "$HOOK_ENV"
	set +a
}
: "${QUALITY_SUITE_DIR:=$SUITE}"
# shellcheck disable=SC1091
. "$DIR/git-flow-lib.sh"
# shellcheck disable=SC1091
. "$DIR/special-integra.sh" # integration order and refusals of the special branches
# why: the Files block of the squash commits is rendered by the commit-message library
# shellcheck disable=SC1091
. "$DIR/commit-files-lib.sh"
# why: git np --migracion and the MIGRATION squash of git integra use the creator of git migracion
# shellcheck disable=SC1091
. "$DIR/git-migracion.sh"
qs_policy_load

# die MESSAGE...: print "[rama] <message>" to stderr and exit 1 (wrapper over qs_die, see qs-common.sh).
# Arguments: the words of the message. Errors: always exits the shell with status 1.
die() { QS_TAG=rama qs_die "$@"; }
# say MESSAGE...: print "[rama] <message>" to stdout (wrapper over qs_say). Return value: 0.
say() { QS_TAG=rama qs_say "$@"; }
YES=0 FORCE=0 FROM="" MIGRACION=0 MSG=() ARGS=()
# shellcheck disable=SC2034 # MIGRACION is read by rama/branch.sh
while [ "$#" -gt 0 ]; do
	case "$1" in
	--yes | -y) YES=1 ;;
	--force) FORCE=1 ;;
	--migracion) MIGRACION=1 ;;
	--from)
		[ "$#" -ge 2 ] || die "--from needs a branch"
		FROM="$2"
		shift
		;;
	--from=*) FROM="${1#--from=}" ;;
	-m)
		[ "$#" -ge 2 ] || die "-m needs a message"
		MSG+=("$2")
		shift
		;;
	*) ARGS+=("$1") ;;
	esac
	shift
done
set -- ${ARGS[@]+"${ARGS[@]}"}
CMD="${1:-}"
shift || true
# shellcheck disable=SC1091
. "$DIR/rama/core.sh"
# shellcheck disable=SC1091
. "$DIR/rama/branch.sh"
# shellcheck disable=SC1091
. "$DIR/rama/integra.sh"
# shellcheck disable=SC1091
. "$DIR/rama/arbol.sh"
# shellcheck disable=SC1091
. "$DIR/rama/release.sh"
# shellcheck disable=SC1091
. "$DIR/rama/publish.sh"
# shellcheck disable=SC1091
. "$DIR/rama/ot.sh"
# shellcheck disable=SC1091
. "$DIR/rama/version.sh"
# shellcheck disable=SC1091
. "$DIR/rama/combine.sh"
# shellcheck disable=SC1091
. "$DIR/rama/repofiles.sh"
case "$CMD" in
nueva-padre | np) cmd_nueva padre "$@" ;;
nueva-final | nr) cmd_nueva final "$@" ;;
convertir-padre) cmd_convertir ;;
subir) cmd_subir ;;
integra) cmd_integra ;;
arbol) cmd_arbol "$@" ;;
estructura | es) cmd_estructura "$@" ;;
changelog) cmd_changelog "$@" ;;
release) cmd_release "$@" ;;
publicar | publish) cmd_publicar "$@" ;;
nueva-version | nv) cmd_nueva_version "$@" ;;
combinar | combine) cmd_combinar "$@" ;;
repo-files | ficheros-repo) cmd_repo_files "$@" ;;
*)
	awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
	exit 2
	;;
esac
