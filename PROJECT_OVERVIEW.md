# chardetz — Project Overview

## Goal

A faithful **C++→Zig translation of uchardet** (the Mozilla universalchardet-lineage
character-encoding detector), delivered as a charset detector with **no C/C++
runtime dependency**, cross-compilable to all 5 house targets, and **WASM-able**
— which does not currently exist in the ecosystem. chardetz is a **drop-in**
replacement for uchardet's C ABI, so existing uchardet consumers can swap it in.

Validated against the live uchardetz C++ as a **differential oracle** with a
**tight** gate: same tables + same logic ⇒ near-exact agreement is required.

## Terminology

- **uchardet** — upstream C++ detector (BYVoid/uchardet), a port of Mozilla's
  universalchardet.
- **uchardetz** — Peter's Zig-build fork of uchardet. Holds the C++ source we
  translate *and* builds the CLI + `libuchardet` used as the live oracle.
- **chardetz** — this project: the pure-Zig translation.
- **Prober** — a uchardet detection module for a family of encodings (multibyte
  state-machine probers, single-byte frequency-model probers, the Latin-1
  prober, the escape-sequence prober, the Hebrew prober).
- **Differential oracle** — feeding identical input to the C++ (uchardetz) and
  the Zig (chardetz) sides and asserting identical output.
- **Expected-divergences ledger** (`tests/expected_divergences.json`) — the small,
  documented, hash-guarded list of cases where chardetz is *allowed* to differ.
  Default empty; near-exact agreement required.

## Pinned source

Translated from **uchardetz @ `abacfc1fc86ef7618547d7dce7cc7501e756fa31`**
(branch `yolo`, https://github.com/pmarreck/uchardetz). All data tables in
`src/tables/` are mechanically generated from that exact commit; see
`tools/gen_tables/manifest.zig`.

## License

Tri-licensed **MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later**, inherited from
upstream (a translation is a derivative work). See `COPYING`, `PROVENANCE.md`,
`THIRD_PARTY_LICENSES`.

## Architecture

Pure **Zig core** (no I/O) → **C FFI** (uchardet-compatible ABI) → **C CLI**
(dogfoods the FFI) → **WASM** (`wasm32-freestanding`). Detection logic lives in
the Zig core; the FFI mirrors uchardet's 6-function API exactly.

## Design & plan documents

- Spec: `docs/superpowers/specs/2026-06-13-chardetz-design.md`
- M1 plan: `docs/superpowers/plans/2026-06-13-chardetz-m1.md`
