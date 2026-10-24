# PLAN log

Completed items retired from PLAN.md, oldest first.

## June 2026 (first translation, published as pmarreck/chardetz)

- [x] **M9 — PRINTABLE-BINARY prober (chardetz extension beyond uchardet)** (2026-06-15 EST)
- [x] **M8 — Code review + performance review + real `./bm`** (2026-06-14 EST)
- [x] **M7 — Differential FUZZ harness** (`tests/fuzz/differential_fuzz.zig` + `./fuzz` + flake `checks.fuzz` + `test-fuzz` build step) (2026-06-14 EST)
- [x] **M1 — Infrastructure (local-only, NO public repo, NO prober)** (complete 2026-06-14 EST)
- [x] **M2 — UTF-8 + Latin-1 + one single-byte model at oracle parity** (UTF-8 prober + detection engine 2026-06-14; Latin-1 + full single-byte set 2026-06-14)
- [x] **M3 — full multibyte prober set** (CJK MBCS group + escape prober — the 8 pending charsets) (complete 2026-06-14 EST)
- [x] **M4 — full single-byte language models + Hebrew + SBCS group** (complete 2026-06-14 EST)
- [x] **M5 — C FFI + C CLI** (uchardet drop-in ABI + dogfooding C CLI) (complete 2026-06-14 EST)
- [x] **M6 — WASM target** (complete 2026-06-14 EST)
- [x] [Wind-down note, 2026-07-06, Mac working copy] Project complete and public at c7d1779; docscan repinned to c7d1779 (off a rewritten-history commit; lesson: never rewrite pushed history). Open question then: drop the redundant EUC-TW .len guard (superseded: the engine was replaced in the October merge).

## October 2026 (independent second translation on a second machine)

- [x] [M1: scaffold, tables, oracle harness (local only)] Scaffold git repo (branch yolo), flake pinning uchardetz-src @ abacfc1f, build.zig, ./test, ./build (done 2026-10-14 15:05 EDT)
- [x] [M1: scaffold, tables, oracle harness (local only)] Tested table generator (tools/gen_tables) and all 23 upstream table files generated into src/tables with freshness gate (done 2026-10-14 15:05 EDT)
- [x] [M1: scaffold, tables, oracle harness (local only)] License and provenance artifacts: COPYING, PROVENANCE.md, THIRD_PARTY_LICENSES, README license section, per-file license blocks (done 2026-10-14 15:05 EDT)
- [x] [M1: scaffold, tables, oracle harness (local only)] Manifest control file guarded by blessed_hashes.txt and pin-agreement check (done 2026-10-14 15:05 EDT)
- [x] [M1: scaffold, tables, oracle harness (local only)] Build uchardetz C++ as a test-only static library from CHARDETZ_UCHARDET_SRC in build.zig (done 2026-10-14 16:40 EDT)
- [x] Differential core gate over the 59-file seed corpus: oracle matches filename labels on all; Zig core pending; empty guarded ledger (done 2026-10-14 16:40 EDT)
- [x] Oracle gate also feeds every corpus file in 1, 7 and 4096-byte chunks, keyed path@N in the ledger (done 2026-10-15 14:05 EDT)
- [x] Table-level differential: generated C++ shims include each upstream table file; every array, constant and model in all 23 modules matches the compiler byte-for-byte (done 2026-10-15 14:05 EDT)
- [x] CLI-vs-CLI parity harness tests/cli/parity, self-tested against the C++ oracle CLI and wrong candidates (done 2026-10-15 14:05 EDT)
- [x] Report M1 to the orchestrator (done 2026-10-15 14:40 EDT, 6548328)
- [x] All probers ported (UTF-8, Latin-1, 35 single-byte incl. Hebrew, 6 CJK, escape) and at oracle parity on 59 files x 4 chunkings (done 2026-10-15 23:10 EDT)
- [x] Streaming Detector API; gate feeds the Zig core the same chunks as the oracle (done 2026-10-15 23:10 EDT)
- [x] Seeded randomized differential: 20,000 generated, mutated, spliced and sliced inputs in random chunks, zero mismatches; tie-break mutant caught (done 2026-10-15 23:10 EDT)
- [x] M3: full multibyte prober set (done 2026-10-15 23:10 EDT, with M2)
- [x] M4: all single-byte language models, Hebrew prober, SBCS group (done 2026-10-15 23:10 EDT, with M2)

## Retired 2026-10-23

- [x] [2026-10-21 (BDFN request): merge both translations; accuracy over bug-for-bug fidelity] Check the original development machine for the June working copy: no unpushed code, only an uncommitted wind-down note (done 2026-10-21 14:00 EDT)

## Retired 2026-10-24

- [x] [2026-10-21 (BDFN request): merge both translations; accuracy over bug-for-bug fidelity] Merge the October port and the June repo (engine and gates from October; PRINTABLE-BINARY, WASM ABI, bench, fuzz edge cases from June) (done 2026-10-21 14:20 EDT, db53518)
