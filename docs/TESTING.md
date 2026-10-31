# Testing on push

Tests run only on a delicate operation (push), via `scripts/run-tests.sh`, invoked
by the pre-push hook. They run on the host (they need the project toolchain) and any
failure blocks the push.

## Precedence

1. **Rules file**: `"tests": {"commands": [...]}` in `.quality-rules.json` (the engine
   exports them to `.git/quality-suite/tests.txt` for the hook).
2. **Explicit** `.quality-tests` at the repo root (one command per line, `#` =
   comment). If present, those commands run — nothing is guessed.
3. **Autodetect** (opt-in: `"tests": {"autodetect": true}` or `QUALITY_TESTS_AUTODETECT=1`): the first match of
   `pom.xml` → `mvn -B test`, Gradle → `./gradlew test`, `package.json` with a test
   script → `npm test`, `Cargo.toml` → `cargo test`, `go.mod` → `go test ./...`,
   `Makefile` with a `test:` target → `make test`.
4. **Nothing** defined → tests are skipped (no tests, no block).

## Example `.quality-tests`

```text
mvn -B test
# npm test --silent
# pytest -q
```

Copy `.quality-tests.example` to `.quality-tests` and edit. Each command runs from
the repo root; results are logged via the logging system (`comp=tests`).

## Notes

- This is separate from `QUALITY_HEAVY_CMD` (a single arbitrary pre-push command);
  both can coexist. Tests run before the heavy stage.
- Regex-based test selection is not implemented; define the exact commands you want.
