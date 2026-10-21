# Accuracy policy

chardetz aims to be at least as accurate as uchardet and more accurate wherever uchardet is demonstrably wrong. It does not reproduce a known upstream mistake just because upstream makes it. The BDFN (Benevolent Dictator For Now) set this direction on 2026-10-21. It replaces the original June goal of exact, bug-for-bug parity.

## Why two modes

Improving on uchardet and proving the translation correct pull in opposite directions. Once chardetz answers differently from uchardet on purpose, a differential test can no longer tell a deliberate improvement from a porting error. chardetz therefore compiles the same detector two ways:

- **Upstream mode** (`UpstreamDetector`) has every accuracy fix switched off at compile time. It must reproduce the C++ original exactly. Every differential oracle gate runs against it: the upstream corpus at several chunk sizes, the seeded randomized campaign, CLI parity and the table differential. Any divergence there is a porting bug.
- **Default mode** (`Detector`) has every accuracy fix on. It is what the Zig API, the C ABI, the CLI and the WebAssembly module use.

Because the fixes are compile-time switches on shared code, the upstream-mode gates also cover all of the code the default mode runs except the fixes themselves, and each fix carries its own tests.

## What every fix must have

1. A name, and one switch in `Fixes` (`src/detector.zig`).
2. A statement of the upstream behavior it corrects and why that behavior is wrong.
3. A failing-then-passing test that shows the default mode giving the right answer where upstream mode gives the wrong one, against a ground truth the fix's author did not choose: the corpus filename labels, or a property such as chunk invariance.
4. Evidence that it does not regress anything else: the upstream-corpus ground-truth labels must still hold in default mode at every tested chunk size.
5. An entry in the table below, and in the list of fixes offered back to uchardetz.

## Fixes

| Fix | Upstream behavior | Why it is wrong | Test |
|---|---|---|---|
| `fixed_blocks` | Byte-order marks and BOM-less UTF-16 are checked only in the first chunk the caller passes, and probers stop early per chunk, so the answer depends on how the caller splits the input. | The same bytes must give the same answer. A UTF-16LE file with a byte-order mark, fed one byte at a time, comes out as WINDOWS-1252. chardetz regroups input into 64 KiB blocks (the size uchardet's own tool reads, against which its corpus labels were set) before the probers see it. | `detector.zig`: "a byte-order mark fed one byte at a time is still recognized"; `corpus_test.zig`: both default-mode tests |
| `revisable_ascii` | After an all-ASCII first chunk the verdict ASCII (or ISO-8859-1) is kept even when high bytes follow, unless some prober becomes certain on its own. | Text with non-ASCII characters is not ASCII. Any file whose first 64 KiB is plain ASCII is misreported, and with small chunks most of the corpus is. chardetz withdraws the provisional verdict at the first high byte. | `detector.zig`: "high bytes after a 64 KiB ASCII prefix are not reported as ASCII"; `corpus_test.zig`: "default mode: corpus labels hold at every chunk size" |

## Measured effect

On the pinned upstream corpus (59 files, each fed whole and in 65536-, 4096-, 7- and 1-byte chunks), uchardet behavior gives the wrong encoding in 59 of the 295 runs: 35 at 1-byte chunks and 24 at 7-byte chunks. The default mode gives the labeled encoding in all 295. Over the 20,000 seeded randomized inputs, uchardet behavior changes its answer with the chunking in 3,165 cases (15.8%); the default mode in none. For inputs up to 64 KiB the default mode answers exactly as uchardet does when given the whole input at once.

## Candidates under evaluation

- Single-byte confidence on control-heavy input: upstream computes `total - ctrl` in unsigned arithmetic, which wraps when control characters outnumber the counted characters and can yield a high confidence. Upstream mode reproduces it (test "confidence reproduces upstream's unsigned (total - ctrl) wraparound" in `src/sbcs.zig`). It needs labeled evidence before it is changed.
- EUC-TW frequency orders past the end of the 5376-entry table: upstream reads out of bounds; chardetz treats them as infrequent in both modes (`docs/UPSTREAM_DEFECTS.md`).
