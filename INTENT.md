# chardetz intent

## Purpose and users

chardetz detects the character encoding of unlabeled text. It started as a translation of [uchardet](https://gitlab.freedesktop.org/uchardet/uchardet), the Mozilla universalchardet-lineage detector, from C++ into pure Zig. It serves people and programs that need encoding detection, often over large corpora, without carrying a C or C++ toolchain or runtime, and including in WebAssembly.

## Desired outcomes

- **At least as accurate as uchardet, and more accurate wherever uchardet is demonstrably wrong.** Faithfully reproducing a known upstream mistake is not a goal. Each deliberate improvement is named, tested against ground truth and explained (`docs/ACCURACY.md`).
- **A proven translation underneath.** A compile-time "upstream" mode of the same detector reproduces uchardet exactly, and the differential oracle gates run against it. That keeps the port provably faithful, so every intentional difference in the default mode is attributable to a documented fix rather than a porting error.
- Faster than the C++ original, measured rather than assumed (`./bm`).
- A drop-in C ABI matching uchardet's six functions, so existing consumers can switch without code changes, plus a one-shot WebAssembly ABI.
- A pure Zig core with no I/O, a C FFI, a C command-line tool that uses only that FFI, and `wasm32-freestanding` output.
- Builds for macOS aarch64, Linux aarch64/x86_64 and Windows aarch64/x86_64.
- Extensions uchardet lacks where they are useful and cannot disturb its answers: the `PRINTABLE-BINARY` prober is the first.

## Scope and non-goals

- In scope: every prober and data table of the pinned upstream revision (`PROVENANCE.md`), accuracy fixes with evidence, and narrowly scoped extensions.
- Not in scope: retraining language models without a labeled corpus to measure against, and speculative SIMD before the performance gate asks for it.
- Python is not used anywhere in the project.

## Constraints

- Licensing: translated logic and data tables are derivative works of uchardet and keep its MPL 1.1 / GPL 2.0+ / LGPL 2.1+ tri-license. They are never relicensed under BSD/MIT; the whole repository uses the tri-license for simplicity.
- Tables come from a tested mechanical generator run on the pinned upstream source, never hand transcription.
- In upstream mode, any divergence from the C++ oracle is a porting bug. In the default mode, a difference from the oracle must be explained by a documented accuracy fix with a test.
- Downstream consumers pin this repository's history (docscan pins a June commit), so pushed history is never rewritten.

## How success is verified

`./test` runs everything required: generator tests and table freshness, a byte-for-byte table differential against the C++ compiler, the differential oracle gate over the upstream corpus at several chunk sizes and over seeded randomized inputs, ground-truth and chunk-invariance tests for the accuracy fixes, the C ABI contract test, and CLI-versus-CLI parity. `./fuzz` runs longer randomized campaigns, and `./bm` measures throughput and growth.

## References

- Terms: `TERMINOLOGY.md`
- Accuracy policy and fixes: `docs/ACCURACY.md`
- Upstream defects found while translating: `docs/UPSTREAM_DEFECTS.md`
- Original design: `docs/superpowers/specs/2026-06-13-chardetz-design.md`
- Work queue: `PLAN.md`; invariants: `RULES.md`; lineage: `PROVENANCE.md`
