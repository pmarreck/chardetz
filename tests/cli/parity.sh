#!/usr/bin/env bash
# CLI-vs-CLI differential parity (Phase 9). In M1: validates the uchardetz oracle
# CLI against corpus filename labels. M5 hook: once chardetz has its own CLI,
# compare chardetz-CLI output to uchardetz-CLI output here (the true CLI parity).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

# Build the pinned uchardetz CLI (cached after first run). Pinned to the same
# commit as the in-harness oracle (build.zig.zon / tools/gen_tables/manifest.zig).
ORACLE_REF="git+https://github.com/pmarreck/uchardetz?rev=abacfc1fc86ef7618547d7dce7cc7501e756fa31"
if ! nix build "$ORACLE_REF" -o .oracle-cli 2>/dev/null; then
	echo "FAIL: could not build uchardetz oracle CLI" >&2; exit 1
fi
ORACLE="$ROOT/.oracle-cli/bin/uchardet"

fail=0; n=0
while IFS=$'\t' read -r path label; do
	n=$((n+1))
	got="$("$ORACLE" "$ROOT/tests/corpus/$path" 2>/dev/null)"
	# case-insensitive compare
	if [ "$(printf '%s' "$got" | tr 'a-z' 'A-Z')" != "$(printf '%s' "$label" | tr 'a-z' 'A-Z')" ]; then
		echo "CLI PARITY MISMATCH  $path  label=$label  got=$got" >&2; fail=1
	fi
done < <(nix develop -c jq -r '.[] | "\(.path)\t\(.label)"' tests/corpus/manifest.json 2>/dev/null || jq -r '.[] | "\(.path)\t\(.label)"' tests/corpus/manifest.json)
echo "CLI parity: checked $n corpus files via oracle CLI" >&2
exit $fail
