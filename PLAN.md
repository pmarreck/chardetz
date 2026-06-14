# chardetz — Plan

Pinned source: uchardetz @ `abacfc1f`. Spec:
`docs/superpowers/specs/2026-06-13-chardetz-design.md`. M1 plan:
`docs/superpowers/plans/2026-06-13-chardetz-m1.md`.

## Milestones

- [ ] **M1 — Infrastructure (local-only, NO public repo, NO prober)**
  - [x] Phase 0: scaffold + jj init + house-brief symlinks + flake (Zig 0.16 pinned) + docs; `./build`+`./test` green — *2026-06-13 ~12:00 EST*
  - [x] Phase 1: license/provenance artifacts (COPYING verbatim, PROVENANCE, THIRD_PARTY_LICENSES, README, SPDX header) — *2026-06-13 ~12:05 EST*
  - [x] Phase 2: core struct defs (SequenceModel, SMModel+PckInt, CharDistribution, JpCntx) — *2026-06-13 ~20:30 EST*
  - [x] Phase 3: table generator — single-byte models (33 SequenceModels) — *2026-06-13 ~20:35 EST*
  - [x] Phase 4: table generator — MBCS + Esc state machines (11 SMModels: 7 MBCS + 4 Esc; GB2312 correctly excluded — obsolete/commented-out upstream, superseded by GB18030) — *2026-06-13 ~16:50 EST*
  - [x] Phase 5: table generator — CharDistribution + JpCntx (5 DistributionTables + jp2_context 6889-entry ContextTable; all tests green, idempotent) — *2026-06-13 ~23:55 EST*
  - [x] Phase 6: MFIC blessed-hash control-file sentinel (scripts/bless-hashes + scripts/check-blessed-hashes + blessed_hashes.txt; gate wired into ./test) — *2026-06-13 EST*
  - [x] Phase 7: corpus (seed from uchardetz/test + manifest; 59 data files, 18 langs; tests/corpus/gen-manifest + manifest.json) — *2026-06-13 EST*
  - [ ] Phase 8: differential harness — in-harness uchardetz link
  - [ ] Phase 9: differential harness — CLI vs CLI parity
  - [ ] Phase 10: wire ./test + ./bm skeleton + Garnix-green + LLMsend Einstein
- [ ] **M2 — UTF-8 + Latin-1 + one single-byte model at oracle parity**
      → first green prober → name veto → create PUBLIC repo
- [ ] **M3 — full multibyte prober set**
- [ ] **M4 — full single-byte language models + Hebrew + SBCS group**
- [ ] **M5 — C FFI + C CLI + performance gate**
- [ ] **M6 — WASM target**

## Tripwires / deferred
- Bring the in-harness differential gate into Garnix CI (C++-in-sandbox via
  zigDeps) by M2 if M1 keeps it local-only.
- `include/uchardet.h` drop-in header lands with the FFI in M5.
- **M3 EUCTW prober bounds:** EUCTW `GetOrder` max ≈ 5545 exceeds its 5376-entry
  `char_to_freq_order` array (table_size define is 8102, but the compiled array is
  5376 — uchardet's `order < table_size` guard does NOT prevent OOB here). The M3
  EUCTW prober MUST guard `order < char_to_freq_order.len` (not just table_size) to
  avoid a Zig panic on rare/malformed input; replicate uchardet's effective behavior.

## Completed (recent, for continuity)
- 2026-06-13: brainstorm → spec → M1 plan (subagent-driven execution chosen).
- 2026-06-13 ~20:30 EST: Phase 2 complete — all 4 struct files + 3 test files,
  TDD red→green, jj commit d06aae7b.
- 2026-06-13 ~20:35 EST: Phase 3 complete — gen_tables tool (parse_sbcs, emit,
  manifest, root, main), 2 new test files, 33 SequenceModels across 14 langs,
  jj commit e1a775df. Bug fixed: C++ `//` line comments in Bulgarian/others.
- 2026-06-13 EST: Phases 6+7 complete — MFIC blessed-hash sentinel (2 control files,
  negative test verified gate fires+exits-1), 59-file labelled corpus (18 langs),
  gen-manifest script, check-blessed-hashes wired into ./test; jj commit 4fcc5348.
