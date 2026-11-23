#!/usr/bin/env bash
# fake-gh.sh - a FAKE `gh` for tests; the real GitHub API is never called.
# Install it as `gh` on PATH:  cp tests/hooks/fake-gh.sh "$T/bin/gh"; chmod +x "$T/bin/gh"
# Environment: FAKE_GH is the state directory (required).
#   $FAKE_GH/loggedout   when this file exists, `gh auth status` fails (not logged in).
#   $FAKE_GH/resp/<p>    stored response served for `gh api <path>` (GET); <p> is the path with
#                        every "/" replaced by "_"; a missing file answers "HTTP 404" (exit 1).
#   $FAKE_GH/calls.log   one line per api call: "<METHOD> <path>".
#   $FAKE_GH/bodies.log  one line per write call sent with --input: "<METHOD> <path> <body>".
# Write calls (any method but GET) answer {} and change nothing.
# Exit: 0 served, 1 unknown GET path or `auth status` while logged out.

if [ "${1:-}" = auth ]; then
	[ ! -f "$FAKE_GH/loggedout" ]
	exit
fi
shift
method=GET path="" input=0
while [ $# -gt 0 ]; do
	case "$1" in
	-X)
		method="$2"
		shift
		;;
	--input)
		input=1
		shift
		;;
	*) path="$1" ;;
	esac
	shift
done
echo "$method $path" >>"$FAKE_GH/calls.log"
if [ "$method" != GET ]; then
	[ "$input" = 0 ] || { echo "$method $path $(cat)" >>"$FAKE_GH/bodies.log"; }
	echo '{}'
	exit 0
fi
f="$FAKE_GH/resp/$(printf '%s' "$path" | tr '/' '_')"
[ -f "$f" ] || {
	echo "HTTP 404" >&2
	exit 1
}
cat "$f"
