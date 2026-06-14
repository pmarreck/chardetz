# chardetz — Plan

Pinned source: uchardetz @ `abacfc1f`. Spec:
`docs/superpowers/specs/2026-06-13-chardetz-design.md`. M1 plan:
`docs/superpowers/plans/2026-06-13-chardetz-m1.md`.

## Milestones

- [x] **M1 — Infrastructure (local-only, NO public repo, NO prober)** — *complete 2026-06-14 EST*
  - [x] Phase 0: scaffold + jj init + house-brief symlinks + flake (Zig 0.16 pinned) + docs; `./build`+`./test` green — *2026-06-13 ~12:00 EST*
  - [x] Phase 1: license/provenance artifacts (COPYING verbatim, PROVENANCE, THIRD_PARTY_LICENSES, README, SPDX header) — *2026-06-13 ~12:05 EST*
  - [x] Phase 2: core struct defs (SequenceModel, SMModel+PckInt, CharDistribution, JpCntx) — *2026-06-13 ~20:30 EST*
  - [x] Phase 3: table generator — single-byte models (33 SequenceModels) — *2026-06-13 ~20:35 EST*
  - [x] Phase 4: table generator — MBCS + Esc state machines (11 SMModels: 7 MBCS + 4 Esc; GB2312 correctly excluded — obsolete/commented-out upstream, superseded by GB18030) — *2026-06-13 ~16:50 EST*
  - [x] Phase 5: table generator — CharDistribution + JpCntx (5 DistributionTables + jp2_context 6889-entry ContextTable; all tests green, idempotent) — *2026-06-13 ~23:55 EST*
  - [x] Phase 6: MFIC blessed-hash control-file sentinel (scripts/bless-hashes + scripts/check-blessed-hashes + blessed_hashes.txt; gate wired into ./test) — *2026-06-13 EST*
  - [x] Phase 7: corpus (seed from uchardetz/test + manifest; 59 data files, 18 langs; tests/corpus/gen-manifest + manifest.json) — *2026-06-13 EST*
  - [x] Phase 8: differential harness — in-harness uchardetz link. C ABI link works end-to-end in hermetic nix sandbox; all 59 corpus files agree with the oracle after BOM/endianness corpus-label fix (manifest.json corrected: fr/utf-16.be→UTF-16, fr/utf-32.le→UTF-32, ko/utf-16.le→UTF-16, ko/utf-32.be→UTF-32). — *2026-06-14 EST*
  - [x] Phase 9: CLI-vs-CLI parity harness (tests/cli/parity.sh; oracle CLI vs corpus labels; 0 mismatches across 59 files; wired into ./test) — *2026-06-14 EST*
  - [x] Phase 10: ./bm skeleton + bench/.gitkeep + nix flake check -L green (all 5 cross-target packages + 3 checks evaluated clean; only aarch64-darwin checks run hermetically; cross-targets pure-Zig fine) + docs — *2026-06-14 EST*
- [x] **M2 — UTF-8 + Latin-1 + one single-byte model at oracle parity** — *UTF-8 prober + detection engine 2026-06-14; Latin-1 + full single-byte set 2026-06-14*
      → first green prober → name veto → create PUBLIC repo (repo step still pending)
- [x] **M3 — full multibyte prober set** (CJK MBCS group + escape prober — the 8 pending charsets) — *complete 2026-06-14 EST*
  - [x] `CharDistributionAnalysis` → `src/char_distribution_analysis.zig` (per-charset GetOrder byte-math for Big5/GB2312/EUCTW/EUCKR/SJIS/EUCJP; freq/((total-freq)*ratio) confidence + SURE_YES/SURE_NO clamps; EUC-TW OOB guard — table_size 8102 > array ~5378)
  - [x] `JapaneseContextAnalysis` → `src/jp_context_analysis.zig` (hiragana bigram model over jp2_context 83x83; SJIS/EUCJP GetOrder; (totalRel-relSample[0])/totalRel confidence)
  - [x] 6 CJK probers → `src/probers/{big5,gb18030,euckr,euctw,sjis,eucjp}.zig` (SJIS/EUCJP take max(context,distribution); others distribution-only; GB18030 prober uses GB2312 distribution)
  - [x] `nsMBCSGroupProber` → `src/probers/mbcs_group.zig` ([UTF8,SJIS,EUCJP,GB18030,EUCKR,Big5,EUCTW] — exact upstream order; incremental high-byte-run filter (keepNext), not the SBCS English-letter filter; max-confidence argmax)
  - [x] `nsEscCharSetProber` → `src/probers/escape.zig` (4 SMs [HZ,ISO2022CN,ISO2022JP,ISO2022KR]; first eItsMe wins; charset = winning SM model name)
  - [x] Detector restructured to uchardet's true shape: slot 0 = MBCSGroup (UTF-8 moved INSIDE it), slot 1 = SBCSGroup, slot 2 = Latin1; escape prober fed on the eEscAscii path
  - [x] Differential gate: IMPLEMENTED grown to all 8 CJK/escape charsets; **checked=59, pending=0, divergences=0** (full corpus coverage at oracle parity). `./test` green end-to-end.
- [x] **M4 — full single-byte language models + Hebrew + SBCS group** — *complete 2026-06-14 EST*
  - [x] `nsSBCharSetProber` → `src/probers/sbcs.zig` (bigram precedence-matrix scoring + positive-ratio confidence; reversed + name-prober support)
  - [x] `nsSBCSGroupProber` → `src/probers/sbcs_group.zig` (35 sub-probers in exact upstream order incl. Hebrew helper at slot 10; FilterWithoutEnglishLetters → max-confidence argmax)
  - [x] `nsHebrewProber` → `src/probers/hebrew.zig` (final-letter logical/visual heuristic → WINDOWS-1255 vs ISO-8859-8)
  - [x] `nsLatin1Prober` → `src/probers/latin1.zig` (8-class model + class-bigram table; FilterWithEnglishLetters; *0.5 downweight)
  - [x] `FilterWith[out]EnglishLetters` → `src/filter.zig`
  - [x] Wired into dispatcher: prober array now [UTF8, SBCSGroup, Latin1] (PROBER_COUNT=3; MBCS group lands in M3)
  - [x] Differential gate: IMPLEMENTED grown to all single-byte charsets; **checked=51, pending=8 (CJK+escape only), divergences=0**
- [ ] **M5 — C FFI + C CLI + performance gate**
- [ ] **M6 — WASM target**

## Tripwires / deferred
- Bring the in-harness differential gate into Garnix CI (C++-in-sandbox via
  zigDeps) by M2 if M1 keeps it local-only.
- `include/uchardet.h` drop-in header lands with the FFI in M5.
- **M3 EUCTW prober bounds — RESOLVED 2026-06-14:** EUCTW `GetOrder` max ≈ 5545
  exceeds its ~5378-entry `char_to_freq_order` array (table_size define is 8102).
  `CharDistributionAnalysis.handleOneChar` now guards
  `order < table_size AND order < char_to_freq_order.len` (an out-of-array order is
  simply never "frequent" — reproducing uchardet's effective UB behavior safely).
  Covered by a unit test feeding {0xfe,0xfe} (order 5545).

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
