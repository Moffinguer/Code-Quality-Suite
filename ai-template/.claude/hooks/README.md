Hooks for Claude Code live in ../settings.json. The quality gate hook calls
`<SUITE>/scripts/qs-run.sh --hook`, which reads the edited file from the hook JSON on stdin.
