# chardetz — Plan

Pinned source: uchardetz @ `abacfc1f`. Spec:
`docs/superpowers/specs/2026-06-13-chardetz-design.md`. M1 plan:
`docs/superpowers/plans/2026-06-13-chardetz-m1.md`.

## Milestones

- [ ] **M1 — Infrastructure (local-only, NO public repo, NO prober)**
  - [x] Phase 0: scaffold + jj init + house-brief symlinks + flake (Zig 0.16 pinned) + docs; `./build`+`./test` green — *2026-06-13 ~12:00 EST*
  - [x] Phase 1: license/provenance artifacts (COPYING verbatim, PROVENANCE, THIRD_PARTY_LICENSES, README, SPDX header) — *2026-06-13 ~12:05 EST*
  - [x] Phase 2: core struct defs (SequenceModel, SMModel+PckInt, CharDistribution, JpCntx) — *2026-06-13 ~20:30 EST*
  - [ ] Phase 3: table generator — single-byte models (33 SequenceModels)
  - [ ] Phase 4: table generator — MBCS + Esc state machines
  - [ ] Phase 5: table generator — CharDistribution + JpCntx
  - [ ] Phase 6: MFIC blessed-hash control-file sentinel
  - [ ] Phase 7: corpus (seed from uchardetz/test + manifest)
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

## Completed (recent, for continuity)
- 2026-06-13: brainstorm → spec → M1 plan (subagent-driven execution chosen).
- 2026-06-13 ~20:30 EST: Phase 2 complete — all 4 struct files + 3 test files,
  TDD red→green, jj commit d06aae7b.
