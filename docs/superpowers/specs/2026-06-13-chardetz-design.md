# chardetz — Design Spec

**Date:** 2026-06-13
**Author:** Claude (chardetz session) with Peter Marreck
**Source brief:** `inbox/2026-06-13-kickoff.md` (from Einstein / orchestrator)
**Status:** Approved design; drives the implementation plan.

---

## 1. Purpose

**chardetz** is a faithful **C++→Zig translation of uchardet** (the Mozilla
universalchardet-lineage character-encoding detector). The deliverable is a
charset detector with **no C/C++ runtime dependency**, cross-compilable to all
5 house targets, and **WASM-able** — which does not currently exist in the
ecosystem. It is a **drop-in** replacement for uchardet's C ABI, so existing
uchardet consumers can swap it in unchanged.

Community/OSS benefit is the point. Downstream (later, not now): docscan can
drop its C++ uchardetz dependency and compile its charset path into WASM.

### Definitions
- **uchardet** — the upstream C++ detector (BYVoid/uchardet), itself a port of
  Mozilla's universalchardet.
- **uchardetz** — Peter's fork of uchardet that adds a Zig build system (and an
  i18n layer). It contains the C++ source we translate **and** builds a working
  CLI + `libuchardet` we use as the live oracle.
- **chardetz** — this project: the pure-Zig translation.
- **Differential oracle** — feeding identical input to the C++ (uchardetz) and
  the Zig (chardetz) implementations and asserting identical output.
- **Prober** — a uchardet detection module specialized for a family of
  encodings (multibyte state-machine probers, single-byte frequency-model
  probers, the Latin-1 prober, the escape-sequence prober, the Hebrew prober).
- **Expected-divergences ledger** — the small, documented, hash-guarded list of
  cases where chardetz is *allowed* to differ from the oracle (each with a
  reason). Default is zero entries; near-exact agreement is required.

## 2. Source of truth & provenance (pinned)

- Translation source = **uchardetz @ `abacfc1fc86ef7618547d7dce7cc7501e756fa31`**
  (branch `yolo`, https://github.com/pmarreck/uchardetz, public). Local and
  remote HEAD confirmed identical at design time.
- This is the exact code the oracle compiles from, guaranteeing the oracle
  reflects what we translate (including the fork's divergences from BYVoid
  upstream).

## 3. License (load-bearing legal artifact — get exactly right)

uchardet is **tri-licensed MPL 1.1 / GPL-2.0+ / LGPL-2.1+** (inherited from
Mozilla). A translation **is a derivative work**, so ported files (logic AND
the data tables — the tables are the copyrighted IP) **must carry the upstream
license**. We preserve the **full tri-license** to maximize downstream adoption.

Required artifacts:
- `COPYING` — copied **verbatim** from uchardetz (tri-license text).
- Per **ported** file (hand-ported logic AND generated tables): the upstream
  `/* ***** BEGIN LICENSE BLOCK ***** Version: MPL 1.1/GPL 2.0/LGPL 2.1 ... */`
  header, plus `SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR
  LGPL-2.1-or-later`.
- `PROVENANCE.md` — lineage Mozilla universalchardet → BYVoid/uchardet →
  uchardetz fork @ `abacfc1f`, naming the exact pinned commit and crediting
  Mozilla, Netscape (Initial Developer), and BYVoid.
- `THIRD_PARTY_LICENSES` — aggregated third-party notices.
- README license section — clear statement of the tri-license + provenance.

Non-derivative glue (build.zig, the C CLI shell, the WASM shim, the test
harness, the table generator's own code) is new work; for simplicity the whole
repo stays under the tri-license. **Do NOT relicense ported tables/logic as
BSD/MIT.** When in doubt, ask Peter.

## 4. Architecture (house hexagonal pattern)

```
chardetz CLI (C, dogfoods the FFI) ─┐
WASM (wasm32-freestanding)          ─┼─► C FFI (uchardet-compatible ABI) ─► Zig core (pure, no I/O)
existing uchardet consumers         ─┘
```

- **Zig core** (`src/`): pure in-memory detection. The `UniversalDetector`
  dispatcher + all probers + comptime tables. No I/O, no allocation surprises;
  all state passed in. This is where the porting happens.
- **C FFI** (`src/ffi.zig` + generated/curated `include/uchardet.h`): mirrors
  uchardet's ABI **exactly** — `uchardet_new`, `uchardet_delete`,
  `uchardet_handle_data`, `uchardet_data_end`, `uchardet_reset`,
  `uchardet_get_charset`. Header is byte-compatible with upstream's so chardetz
  is a true drop-in.
- **C CLI** (`cli/`): a C program that dogfoods the FFI (does all I/O). Follows
  house CLI conventions (`-h/--help`, `--about`, stdin/stdout `-`/`@stdin`,
  JSON output, `--simple`/`--no-color`, etc.) in later milestones.
- **WASM** target (M6): `wasm32-freestanding`, same core.

### Prober inventory to port (from uchardetz/src)
- **Dispatcher:** `nsUniversalDetector`.
- **Multibyte:** `nsUTF8Prober`, `nsBig5Prober`, `nsEUCJPProber`,
  `nsEUCKRProber`, `nsEUCTWProber`, `nsGB2312Prober`, `nsSJISProber`,
  `nsMBCSGroupProber` (group), driven by `nsMBCSSM` state machines +
  `nsCodingStateMachine`; CJK distribution via `CharDistribution`; Japanese
  context via `JpCntx`.
- **Single-byte:** `nsSBCharSetProber` + `nsSBCSGroupProber` consuming the
  `SequenceModel` tables (`Lang*Model.cpp`).
- **Latin-1:** `nsLatin1Prober`.
- **Escape:** `nsEscCharsetProber` + `nsEscSM`.
- **Hebrew:** `nsHebrewProber` (special-cased logit/visual+logical handling).

## 5. Table codegen (Milestone 1 — ALL tables up front)

The tables are the bulk and the value. We generate them mechanically rather
than hand-transcribe: deterministic, re-runnable on upstream bumps, far less
error-prone, and the generator is itself testable.

- **Generator:** `tools/gen_tables/` written in **Zig** (NOT Python), runnable
  via `zig build gen-tables`. It parses uchardetz's C++ table sources (plain C
  array initializers) and emits Zig source.
- **Table families:**
  - `Lang*Model.cpp` → `SequenceModel` Zig literals:
    `charToOrderMap: [256]u8`, `precedenceMatrix: []const u8`
    (`freqCharCount²`), `freqCharCount: usize`, `typicalPositiveRatio: f32`,
    `keepEnglishLetter: bool`, `charsetName`.
  - `nsMBCSSM.cpp` / `nsEscSM.cpp` → `SMModel`: packed class table
    (`_cls[256/8]`), state table (`_st[]`), `CharLenTable[]`, and the bit-pack
    descriptors (`eIdxSft4bits` etc.).
  - `CharDistribution.cpp` → CJK char-distribution tables.
  - `JpCntx.cpp` → Japanese 2-char context tables.
- **Generated output** is committed (so the build is hermetic and Garnix needs
  no codegen at build time). Each generated file carries the SPDX/license
  header + a `// @generated from <upstream file> @ abacfc1f — do not edit`
  provenance line.
- **Generator is tested** (MFIC): feed a known C++ table snippet → assert exact
  expected Zig output (authored-oracle unit test), AND the generated tables are
  independently validated end-to-end by the differential gate (oracle the
  author didn't write).
- **MFIC control file:** the generator's pinned-source manifest (which upstream
  files at which commit) is a control file guarded by a blessed-hash sentinel,
  so the pinned set can't drift silently — any change fails CI until the hash is
  deliberately re-blessed (two-file diff, human-reviewed).

## 6. Differential oracle harness (TDD — built FIRST, both mechanisms)

Per the kickoff: build the harness **before** porting logic. The harness is the
spec. Two mechanisms (Peter chose "Both"):

1. **Core gate — in-harness link (primary, high-throughput):**
   uchardetz is added as a **test-only** Zig dependency (it is already a
   Zig-build project with `build.zig.zon`). A Zig test feeds identical byte
   streams to uchardetz's C API (`uchardet_*`) and to chardetz's core, asserting
   identical `get_charset`. Runs over the full corpus + fuzzed/mutated inputs at
   high throughput. Test-time C++ toolchain is explicitly acceptable (it does
   not affect chardetz's runtime, which stays C++-free).
2. **End-to-end parity — CLI vs CLI:** a Bash test in `tests/cli/` runs the
   built `uchardetz` binary and the built `chardetz` binary over each corpus
   file and diffs the reported charset string. Catches FFI/CLI-layer drift the
   core gate can't see.

### Corpus
- Seed from `uchardetz/test/<lang>/<encoding>.txt` — **the filename is the
  ground-truth encoding label**, giving a *second independent oracle* (filename
  truth) alongside the live differential (uchardetz-says) oracle.
- Expand with a broader multi-encoding / multi-language corpus
  (`tests/corpus/`), generated/collected and committed.

### Expected-divergences ledger (no false greens)
- `tests/expected_divergences.json` — only **genuinely-acceptable** divergences,
  each with a documented reason. Default: empty. Any *un-fenced* divergence is a
  porting **bug to fix**, not to fence.
- Guarded by a blessed-hash control so the ledger cannot grow silently; growth
  requires a deliberate, human-reviewed two-file commit.

## 7. Testing & performance gates

- **`./test`** (Bash, accumulates sub-errors → exit code): Zig unit tests + the
  differential core gate + CLI parity tests. Runs clean (expected stderr
  captured/asserted, never printed). Leak-free via `std.testing.allocator`.
- **`./build`** / **`./build_all`**: nix-based (`nix build`), ReleaseFast
  default, per house Build-System rules (never `nix develop -c zig build` for
  native).
- **`flake.nix` + Garnix:** `packages.default` + `checks.{build,test}`; Zig
  pinned; Garnix-green required before any push.
- **Performance MVP gate** (throughput is the selling point — large corpora):
  - `// complexity: O(n)` declared on hot paths (the detector feed loop, prober
    step functions).
  - **Scaling-ratio test** N/2N/4N/8N (machine-independent, primary): assert
    per-doubling ratio ≈2 for linear paths; fail ≥~2.5–3×.
  - **Constant-factor bench** (`./bm`, secondary): two-sided tolerance,
    CPU/user time for the compute kernel, ReleaseFast only, ndjson logged as
    `bench/<machine-id>.ndjson` (new machine seeds + passes).
  - **Headline comparison:** chardetz vs C++ uchardet throughput on a large
    corpus — being *faster* with no C++ dependency is the story.

## 8. Tooling & conventions

- **jj only** (never raw git); branch **`yolo`**; `gh` for PR/release only.
- Scaffold via the **`scaffold-zig-project`** skill — do not hand-roll.
- ReleaseFast default in `build.zig` (per house rule, not
  `standardOptimizeOption`).
- Read `ZIG_RECENT_API_CHANGES.md` (symlinked) before writing Zig 0.16.
- `dirtree note` every important file; keep `PLAN.md`, `PROJECT_OVERVIEW.md`,
  `RULES.md` current.
- **No Python** anywhere (the oracle is C/Zig, so none is needed; harness is
  Bash/Zig).
- Repo is **PUBLIC** OSS (`pmarreck/chardetz`, SSH remote, jj-colocated) — but
  created on GitHub **only after Milestone 2 is green** (first prober agreeing
  with the oracle — "debut with substance"), and **only after Peter approves
  the name `chardetz`** (he reserved a veto window). M1 stays local-only.

## 9. Milestones (stop + LLMsend Einstein at each boundary)

1. **M1 (current):** scaffold (`scaffold-zig-project`) + `flake.nix` +
   Garnix-green + **both** oracle harnesses wired + **all tables codegen'd &
   committed** + license/provenance artifacts. **Done-criteria:** repo builds
   green on Garnix; `./test` runs the differential harness (it may report "core
   not yet implemented" for unported probers, but the harness itself works and
   the table generator's unit tests pass); all tables generated, license-headed,
   and committed; license artifacts complete. **M1 stays local-only — no public
   repo yet** (resolved: public push is deferred to M2 so the repo debuts with a
   working prober).
2. **M2:** UTF-8 + Latin-1 + one single-byte language model at oracle parity.
   → **First green prober milestone.** Then pause for Peter's name veto, then
   create the **public** GitHub repo (`pmarreck/chardetz`, SSH, jj-colocated).
3. **M3:** full multibyte prober set.
4. **M4:** full single-byte language models + Hebrew + SBCS group.
5. **M5:** C FFI + C CLI + performance gate.
6. **M6:** WASM target.

## 10. Risks & open questions

- **Float determinism:** uchardet uses `float` confidence math; Zig `f32` should
  match bit-for-bit for the same operations, but ordering/`-ffast-math`
  differences could cause tie-break divergences. Mitigation: the differential
  gate catches these; fence only with a documented reason if a tie is provably
  arbitrary.
- **Generator brittleness:** C++ table syntax edge cases (macros, computed
  initializers). Mitigation: generator is tested; fall back to hand-port for any
  table the generator can't handle (lean on the gate).
- **Name veto:** `chardetz` not yet final — public repo creation is gated on
  Peter's approval (handled explicitly, won't auto-create).
- **i18n layer:** uchardetz added an i18n layer; chardetz's core detector does
  not need it. CLI-level i18n (if any) is an M5 concern per the house i18n
  skill, not M1.

## 11. Out of scope (YAGNI)
- New encodings/probers beyond what uchardet@`abacfc1f` supports.
- API surface beyond uchardet's 6 C functions (M1–M5).
- Performance work beyond matching/beating uchardet (no exotic SIMD until the
  perf gate says it's needed).
