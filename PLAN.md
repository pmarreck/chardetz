# PLAN

Completed items retire to `docs/PLAN_LOG.md`. Purpose: `INTENT.md`. Design: `docs/superpowers/specs/2026-06-13-chardetz-design.md`.

## M1: scaffold, tables, oracle harness (local only)
- [x] Differential core gate over the 59-file seed corpus: oracle matches filename labels on all; Zig core pending; empty guarded ledger (done 2026-10-14 16:40 EDT)
- [x] Oracle gate also feeds every corpus file in 1, 7 and 4096-byte chunks, keyed path@N in the ledger (done 2026-10-15 14:05 EDT)
- [x] Table-level differential: generated C++ shims include each upstream table file; every array, constant and model in all 23 modules matches the compiler byte-for-byte (done 2026-10-15 14:05 EDT)
- [x] CLI-vs-CLI parity harness tests/cli/parity, self-tested against the C++ oracle CLI and wrong candidates (done 2026-10-15 14:05 EDT)
- [x] Report M1 to the orchestrator (done 2026-10-15 14:40 EDT, 6548328)

## Overnight 2026-10-15 (BDFN request): finish M2-M6, meet or exceed uchardet in Zig
- [ ] Create pmarreck/chardetz as a PRIVATE repo with Mechatron Prime CI; going public stays gated on the BDFN name veto

## M2: first probers at oracle parity, then public debut
- [ ] Silence the sandbox-only Zig warning "cannot build new glibc version 2.44.0" when linking the test-only oracle CLI (pin a glibc version or link it like the test binaries)
- [x] All probers ported (UTF-8, Latin-1, 35 single-byte incl. Hebrew, 6 CJK, escape) and at oracle parity on 59 files x 4 chunkings (done 2026-10-15 23:10 EDT)
- [x] Streaming Detector API; gate feeds the Zig core the same chunks as the oracle (done 2026-10-15 23:10 EDT)
- [x] Seeded randomized differential: 20,000 generated, mutated, spliced and sliced inputs in random chunks, zero mismatches; tie-break mutant caught (done 2026-10-15 23:10 EDT)
- [ ] Ask the BDFN for the name veto on "chardetz", then create the public GitHub repo pmarreck/chardetz
- [ ] Register Mechatron Prime CI targets (checks.build, checks.test) via the mechatron-ci skill once the remote exists

## Later milestones
- [x] M3: full multibyte prober set (done 2026-10-15 23:10 EDT, with M2)
- [x] M4: all single-byte language models, Hebrew prober, SBCS group (done 2026-10-15 23:10 EDT, with M2)
- [ ] M5: C FFI (uchardet ABI), C CLI dogfooding it, performance gate (scaling ratio and constant-factor bench vs C++)
- [ ] M5: run tests/cli/parity with the chardetz CLI as candidate in ./test
- [ ] M6: wasm32-freestanding target
- [ ] Apply cross-platform-project-build-arch layout to ./build before M5 ships binaries
