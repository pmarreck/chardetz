# chardetz intent

## Purpose and users

chardetz is a faithful translation of [uchardet](https://gitlab.freedesktop.org/uchardet/uchardet), the Mozilla universalchardet-lineage character-encoding detector, from C++ into pure Zig. It serves people and programs that need to guess the encoding of unlabeled text, especially across large corpora, without carrying a C or C++ toolchain or runtime.

No existing charset detector in this lineage is free of C/C++, cross-compiles to every common target from one toolchain, and also runs as WebAssembly. chardetz exists to fill that gap as public open-source software.

## Desired outcomes

- Detection results identical to uchardet for the same input, proven by a differential oracle that runs the original C++ beside the Zig translation.
- A drop-in C ABI matching uchardet's six functions (`uchardet_new`, `uchardet_delete`, `uchardet_handle_data`, `uchardet_data_end`, `uchardet_reset`, `uchardet_get_charset`), so existing uchardet consumers can switch without code changes.
- A pure Zig core with no I/O, a C FFI, a C command-line tool that consumes that FFI, and a `wasm32-freestanding` build of the same core.
- Builds for macOS aarch64, Linux aarch64/x86_64 and Windows aarch64/x86_64.
- Throughput at least matching the C++ original on a large corpus, measured rather than assumed.

## Scope and non-goals

- In scope: every prober and data table present in the pinned upstream revision (see `PROVENANCE.md`).
- Not in scope: new encodings or probers, API surface beyond uchardet's six C functions, or speculative SIMD work before the performance gate asks for it.
- Python is not used anywhere in the project.

## Constraints

- Licensing: the translated logic and data tables are derivative works of uchardet and keep its MPL 1.1 / GPL 2.0+ / LGPL 2.1+ tri-license. They are never relicensed under BSD/MIT. The whole repository stays under the tri-license for simplicity.
- Tables are produced by a tested mechanical generator from the pinned upstream source, not transcribed by hand.
- Divergence from the oracle is a porting bug to fix. A divergence may be fenced only in the guarded expected-divergences ledger with a documented reason.
- The public GitHub repository is created only after the first prober reaches oracle parity (milestone 2), and only after the BDFN (Benevolent Dictator For Now) confirms the project name.

## How success is verified

- `./test` runs the generator tests, the table freshness gate, the control-file hash checks and, as they land, the differential oracle gate and CLI parity tests.
- Performance is verified with a scaling-ratio test and a constant-factor benchmark against the C++ original.

## References

- Approved design: `docs/superpowers/specs/2026-06-13-chardetz-design.md`
- Work queue: `PLAN.md`
- Invariants: `RULES.md`
- Lineage and pinned revision: `PROVENANCE.md`

## Open questions

- Final project name: `chardetz` stands unless the BDFN vetoes it before the public repository is created (milestone 2).
