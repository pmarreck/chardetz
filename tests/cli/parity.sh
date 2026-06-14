#!/usr/bin/env bash
# CLI-vs-CLI differential parity (Phase 9 -> M5).
#
# THE TRUE END-TO-END CHECK: run the BUILT chardetz CLI and the uchardetz ORACLE
# CLI over every corpus file and assert agreement (case-insensitive on the
# charset name). This dogfoods the C FFI all the way out to the binary -- the
# chardetz CLI calls through the uchardet C ABI, so a match here proves the
# whole adapter stack (Zig core -> C FFI -> C CLI) reproduces uchardet's verdicts.
#
# MFIC note: the oracle CLI is a causally-independent reference implementation
# (uchardetz's own C++ binary), not anything chardetz produced -- agreement is a
# biting refutation, not a self-check.
#
# NEVER use `set -e`/`set -o pipefail` -- a mismatch legitimately returns nonzero
# and the caller (./test) folds that into its accumulated exit code.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

# -- Build the chardetz CLI (nix, ReleaseFast) --
if ! nix build .#default -o .chardetz-cli 2>/dev/null; then
	echo "FAIL: could not build chardetz CLI (nix build .#default)" >&2; exit 1
fi
CHARDETZ="$ROOT/.chardetz-cli/bin/chardetz"
if [ ! -x "$CHARDETZ" ]; then
	echo "FAIL: chardetz CLI not found at $CHARDETZ" >&2; exit 1
fi

# -- Build the pinned uchardetz oracle CLI (cached after first run) --
# Pinned to the same commit as the in-harness oracle (build.zig.zon /
# tools/gen_tables/manifest.zig).
ORACLE_REF="git+https://github.com/pmarreck/uchardetz?rev=abacfc1fc86ef7618547d7dce7cc7501e756fa31"
if ! nix build "$ORACLE_REF" -o .oracle-cli 2>/dev/null; then
	echo "FAIL: could not build uchardetz oracle CLI" >&2; exit 1
fi
ORACLE="$ROOT/.oracle-cli/bin/uchardet"

upper() { printf '%s' "$1" | tr 'a-z' 'A-Z'; }

fail=0; n=0; agree=0
while IFS=$'\t' read -r path label; do
	n=$((n+1))
	file="$ROOT/tests/corpus/$path"
	oracle_out="$("$ORACLE" "$file" 2>/dev/null)"
	chardetz_out="$("$CHARDETZ" "$file" 2>/dev/null)"
	if [ "$(upper "$chardetz_out")" != "$(upper "$oracle_out")" ]; then
		echo "CLI PARITY MISMATCH  $path  label=$label  oracle=$oracle_out  chardetz=$chardetz_out" >&2
		fail=1
	else
		agree=$((agree+1))
	fi
done < <(nix develop -c jq -r '.[] | "\(.path)\t\(.label)"' tests/corpus/manifest.json 2>/dev/null || jq -r '.[] | "\(.path)\t\(.label)"' tests/corpus/manifest.json)

echo "CLI parity (chardetz CLI vs uchardetz oracle CLI): $agree/$n agree" >&2
exit $fail
