# PLAN

Completed items retire to `docs/PLAN_LOG.md`. Purpose: `INTENT.md`. Design: `docs/superpowers/specs/2026-06-13-chardetz-design.md`.

## M1: scaffold, tables, oracle harness (local only)
- [x] Scaffold git repo (branch yolo), flake pinning uchardetz-src @ abacfc1f, build.zig, ./test, ./build (done 2026-10-14 15:05 EDT)
- [x] Tested table generator (tools/gen_tables) and all 23 upstream table files generated into src/tables with freshness gate (done 2026-10-14 15:05 EDT)
- [x] License and provenance artifacts: COPYING, PROVENANCE.md, THIRD_PARTY_LICENSES, README license section, per-file license blocks (done 2026-10-14 15:05 EDT)
- [x] Manifest control file guarded by blessed_hashes.txt and pin-agreement check (done 2026-10-14 15:05 EDT)
- [x] Build uchardetz C++ as a test-only static library from CHARDETZ_UCHARDET_SRC in build.zig (done 2026-10-14 16:40 EDT)
- [x] Differential core gate over the 59-file seed corpus: oracle matches filename labels on all; Zig core pending; empty guarded ledger (done 2026-10-14 16:40 EDT)
- [x] Oracle gate also feeds every corpus file in 1, 7 and 4096-byte chunks, keyed path@N in the ledger (done 2026-10-15 14:05 EDT)
- [x] Table-level differential: generated C++ shims include each upstream table file; every array, constant and model in all 23 modules matches the compiler byte-for-byte (done 2026-10-15 14:05 EDT)
- [x] CLI-vs-CLI parity harness tests/cli/parity, self-tested against the C++ oracle CLI and wrong candidates (done 2026-10-15 14:05 EDT)
- [x] Report M1 to the orchestrator (done 2026-10-15 14:40 EDT, 6548328)

## M2: first probers at oracle parity, then public debut
- [ ] Silence the sandbox-only Zig warning "cannot build new glibc version 2.44.0" when linking the test-only oracle CLI (pin a glibc version or link it like the test binaries)
- [ ] UTF-8 prober, Latin-1 prober and one single-byte language model at oracle parity
- [ ] Streaming core API (uchardet handle_data semantics) so the path@N chunked gate runs feed the candidate in the same chunks as the oracle
- [ ] Ask the BDFN for the name veto on "chardetz", then create the public GitHub repo pmarreck/chardetz
- [ ] Register Mechatron Prime CI targets (checks.build, checks.test) via the mechatron-ci skill once the remote exists

## Later milestones
- [ ] M3: full multibyte prober set (Big5, EUC-JP/KR/TW, GB2312/GB18030, SJIS, MBCS group, escape SM)
- [ ] M4: all single-byte language models, Hebrew prober, SBCS group
- [ ] M5: C FFI (uchardet ABI), C CLI dogfooding it, performance gate (scaling ratio and constant-factor bench vs C++)
- [ ] M5: run tests/cli/parity with the chardetz CLI as candidate in ./test
- [ ] M6: wasm32-freestanding target
- [ ] Apply cross-platform-project-build-arch layout to ./build before M5 ships binaries
