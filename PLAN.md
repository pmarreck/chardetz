# PLAN

Completed items retire to `docs/PLAN_LOG.md`. Purpose: `INTENT.md`. Design: `docs/superpowers/specs/2026-06-13-chardetz-design.md`.

## M1: scaffold, tables, oracle harness (local only)
- [x] Scaffold git repo (branch yolo), flake pinning uchardetz-src @ abacfc1f, build.zig, ./test, ./build (done 2026-10-14 15:05 EDT)
- [x] Tested table generator (tools/gen_tables) and all 25 upstream table files generated into src/tables with freshness gate (done 2026-10-14 15:05 EDT)
- [x] License and provenance artifacts: COPYING, PROVENANCE.md, THIRD_PARTY_LICENSES, README license section, per-file license blocks (done 2026-10-14 15:05 EDT)
- [x] Manifest control file guarded by blessed_hashes.txt and pin-agreement check (done 2026-10-14 15:05 EDT)
- [x] Build uchardetz C++ as a test-only static library from CHARDETZ_UCHARDET_SRC in build.zig (done 2026-10-14 16:40 EDT)
- [x] Differential core gate over the 59-file seed corpus: oracle matches filename labels on all; Zig core pending; empty guarded ledger (done 2026-10-14 16:40 EDT)
- [ ] Add chunk-boundary variants to the oracle gate (feed each corpus file in 1, 7 and 4096-byte chunks)
- [ ] Table-level differential check: compile a C++ shim that includes each upstream table source and compare every array byte-for-byte with src/tables
- [ ] CLI-vs-CLI parity test skeleton in tests/cli (activates when the chardetz CLI exists)
- [ ] Register Mechatron Prime CI targets via the mechatron-ci skill once a remote exists (deferred to the public push at M2)
- [ ] Report M1 to the orchestrator

## M2: first probers at oracle parity, then public debut
- [ ] UTF-8 prober, Latin-1 prober and one single-byte language model at oracle parity
- [ ] Ask the BDFN for the name veto on "chardetz", then create the public GitHub repo pmarreck/chardetz

## Later milestones
- [ ] M3: full multibyte prober set (Big5, EUC-JP/KR/TW, GB2312/GB18030, SJIS, MBCS group, escape SM)
- [ ] M4: all single-byte language models, Hebrew prober, SBCS group
- [ ] M5: C FFI (uchardet ABI), C CLI dogfooding it, performance gate (scaling ratio and constant-factor bench vs C++)
- [ ] M6: wasm32-freestanding target
- [ ] Apply cross-platform-project-build-arch layout to ./build before M5 ships binaries
