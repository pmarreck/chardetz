# PRINTABLE-BINARY prober — design (approved 2026-06-15)

**Goal:** chardetz detects [printable_binary](https://github.com/pmarreck/printable_binary)
("PB") encoded content — a known, constrained UTF-8 subset — and reports the charset
`PRINTABLE-BINARY`. This is a chardetz **extension beyond uchardet** (uchardet has no such
charset), so it is validated **metamorphically** (round-trip via PB's own encoder), NOT
against the differential oracle.

**Motivation:** PB is valid UTF-8 built from a fixed 256-glyph table; without a dedicated
prober chardetz reports it as `UTF-8`. Detecting it lets downstream tools (docscan, etc.)
recognize binary-data-as-text.

## The PB format (from `printable_binary/character_map.txt`, the source of truth)

- Each byte `0x00..0xFF` maps to **exactly one Unicode codepoint** (1–4 UTF-8 bytes). The
  map is a bijection.
- **66 bytes are "self-mapped"** to their own ASCII char: `0-9`, `A-Z`, `a-z`, and a few
  (e.g. `.`). These are plain ASCII and read normally even when encoded.
- **190 bytes map to distinctive special glyphs**: control bytes (`0x00-0x1F`, `0x7F`),
  most punctuation (space→␣ U+2423, `#`→♯, comma→special, …), and all high bytes
  (`0x80-0xFF`). These are the glyphs that essentially never occur, in these proportions,
  in normal text.
- Optional encode flags change the literal output alphabet:
  - `-s/-t/-n/-w` preserve literal space/tab/CR-LF/all-whitespace (U+0020/09/0A/0D appear
    literally instead of as ␣/⇥/⏎/↧).
  - `-f/--format` injects literal spaces + newlines as group/line separators.
  - **In scope:** default glyph mode + whitespace-preserve + formatting.
  - **Out of scope (v1):** `-X/--hexlike` (a different alphabet — hex runs prefixed by
    `Οχ`); `-P <chars>` (unbounded arbitrary literal passthrough).

## Heuristic (Peter's spec, made concrete)

Over the decoded codepoints of the input:

- **Allowed set** = the 256 PB glyph codepoints **∪** literal whitespace
  {U+0020, U+0009, U+000A, U+000D} → 260 distinct codepoints. Whitespace is **neutral**.
- **Distinctive set** = the 190 non-self-mapped glyph codepoints.
- **Condition A:** `in_allowed / total ≥ 0.99` (i.e. < 1% of codepoints fall outside the
  allowed set). Invalid-UTF-8 bytes count as out-of-set.
- **Condition B:** `distinctive / total ≥ 0.10`.
- **Min-data guard:** `total ≥ 32` codepoints (so tiny inputs can't false-fire).
- Both conditions + guard met → `PRINTABLE-BINARY` at high confidence (0.99).

**Why it won't intrude on other charsets:**
- Normal multilingual UTF-8 uses codepoints mostly *outside* the 256-glyph set → fails A.
- Normal prose has commas/quotes/punctuation that map to standard codepoints not in the
  set → fails A. (Comma is U+002C; the PB glyph for byte `,` is a *different* codepoint.)
- Plain alphanumeric text is ~100% self-mapped → 0% distinctive → fails B.
- Non-UTF-8 (single-byte charsets) → decode failures → fails A.
- Whitespace-as-neutral doesn't open a hole: the distinctive signal comes from the
  non-whitespace glyph forms.

## Integration

`PBProber` is **slot 0 of the detector's high-byte prober array**:
`[PBProber, MBCSGroup, SBCSGroup, Latin1]` (PROBER_COUNT 3 → 4).

- `handleData`: decode codepoints incrementally; tally `total`, `in_allowed`, `distinctive`.
  Reach `found_it` only once the guard + A + B hold (strong PB signature) — this pre-empts
  the UTF-8 prober (which lives at slot 0 *inside* MBCSGroup and would otherwise claim PB
  text as UTF-8). Reach `not_me` when A can no longer hold (out-of-set ratio already
  > 1%), so it deactivates and the rest of the array runs untouched. Else stay `detecting`.
- `getConfidence`: 0.99 if guard+A+B, else ~0.0 (so it can't win the dataEnd argmax when
  the signature is weak).
- Because PB only ever *wins* via `found_it`/high-confidence on a strong signature, and is
  otherwise inert, the uchardet-faithful prober groups and all existing verdicts are
  unaffected — **structural non-intrusion**.

The CJK/multibyte glyphs in PB output are high bytes, so PB-with-distinctive-glyphs always
enters the detector's `high_byte` state (the PB prober runs). Pure-alphanumeric PB (no
distinctive glyphs) takes the `pure_ascii` path → `ASCII`, which is correct (it's < 10%
distinctive, so not PB by Condition B anyway).

## Glyph table

Vendor a copy of `character_map.txt` into `src/tables/` and `@embedFile` + comptime-parse
it into a sorted `[260]` allowed-codepoint set with a parallel `distinctive` flag (mirrors
how printable_binary itself builds its map). A **drift-check test** asserts chardetz's
vendored copy is byte-identical to printable_binary's source (the independent truth source)
— mechanical drift detection.

## Testing (MFIC)

- **Metamorphic round-trip (primary gate, oracle-free):** generate varied inputs (random
  bytes, binary, mixed text+binary) → encode with printable_binary (default + `-s/-t/-n/-w`
  + `-f`) → feed to chardetz → assert `PRINTABLE-BINARY` whenever the input had ≥10%
  non-alphanumeric bytes. The encoder is the independent oracle (test-only Zig dep on
  printable_binary; sibling-Zig exception — it has a C CLI dogfooding its FFI).
- **Negative / boundary:** plain ASCII → `ASCII`; plain UTF-8 prose → `UTF-8`; a buffer at
  9% distinctive → not PB; at 11% → PB; tiny input (< 32 cp) → not PB.
- **Non-intrusion gates:** the existing 59-corpus differential still matches uchardet
  exactly (no verdict changed); each corpus file is *not* flagged PB; the differential
  **fuzz stays green** (PB introduces no new chardetz-vs-uchardet divergence on non-PB
  inputs — the key empirical risk).

## TDD plan (small steps)

1. Vendor `character_map.txt` + drift-check test (RED: file absent) → comptime set builder.
2. `PBProber` unit tests (hand-built PB fixtures: strong-PB → found_it/0.99; weak → not_me;
   sub-threshold → detecting/low) → implement prober.
3. Wire as detector slot 0; `detect()` test on a PB fixture → `PRINTABLE-BINARY`; negative
   tests (ASCII/UTF-8 unchanged).
4. Metamorphic round-trip test (printable_binary dep, `-Dwith-pb`-style or test-only).
5. Full `./test` (differential 59/59 unchanged) + `./fuzz` green; `./bm` unaffected.
