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
3. A failing-then-passing test that shows the default mode giving the right answer where upstream mode gives the wrong one, against a ground truth the fix's author did not choose: the corpus filename labels, the iconv-decoded text of the generated corpus, or a property such as chunk invariance.
4. Evidence that it does not regress anything else: the upstream-corpus labels must still hold in default mode at every tested chunk size, and on the generated corpus chardetz must stay right wherever uchardet is right.
5. An entry in the table below, and in the list of fixes offered back to uchardetz.

## Fixes

| Fix | Upstream behavior | Why it is wrong | Test |
|---|---|---|---|
| `fixed_blocks` | Byte-order marks and BOM-less UTF-16 are checked only in the first chunk the caller passes, and probers stop early per chunk, so the answer depends on how the caller splits the input. | The same bytes must give the same answer. A UTF-16LE file with a byte-order mark, fed one byte at a time, comes out as WINDOWS-1252. chardetz regroups input into 64 KiB blocks (the size uchardet's own tool reads, against which its corpus labels were set) before the probers see it. | `detector.zig`: "a byte-order mark fed one byte at a time is still recognized"; `corpus_test.zig`: both default-mode tests |
| `revisable_ascii` | After an all-ASCII first chunk the verdict ASCII (or ISO-8859-1) is kept even when high bytes follow, unless some prober becomes certain on its own. | Text with non-ASCII characters is not ASCII. Any file whose first 64 KiB is plain ASCII is misreported, and with small chunks most of the corpus is. chardetz withdraws the provisional verdict at the first high byte. | `detector.zig`: "high bytes after a 64 KiB ASCII prefix are not reported as ASCII"; `corpus_test.zig`: "default mode: corpus labels hold at every chunk size" |
| `valid_utf8` | UTF-8 is weighed by a confidence that grows with the number of multibyte characters (0.505 for one, 0.75 for two, 0.99 only from six), so a single-byte language model with a higher score wins on short text; some full-length texts are lost as well. | Text written in a single-byte charset almost never forms valid multibyte UTF-8 by accident, so input that is entirely valid UTF-8 (strict RFC 3629 validation across chunk boundaries) and contains multibyte characters is reported as UTF-8. Byte-order marks, escape-sequence verdicts, probers that are certain, and PRINTABLE-BINARY still take precedence. | `detector.zig`: "valid UTF-8 with multibyte characters is reported as UTF-8", "input that is not valid UTF-8 is not forced to UTF-8", and a differential test of the validator against `std.unicode` |

## How accuracy is measured

Two independent ground truths, both checked by `./test`:

1. **The upstream corpus** (59 files from the pinned uchardetz tree, labeled by filename). The default mode must give every label at every tested chunk size (`tests/oracle/corpus_test.zig`).
2. **The generated accuracy corpus** (`tests/accuracy/`). A build-time tool takes the Universal Declaration of Human Rights in about 500 languages (pinned flake input `udhr-src`), cuts each text to 8, 16, 32, 64, 128, 256 and 1024 characters and in full, and writes it with iconv in every charset uchardet claims for that language, plus UTF-8 for every language: 4,737 cases. An answer is right when decoding the case's bytes with the named charset reproduces the text exactly, so the ground truth comes from iconv, not from either detector. Each case is fed whole, one byte at a time, and after 64 KiB of ASCII.

Results are in `docs/ACCURACY_REPORT.md`, generated by `zig build accuracy-report`. Every case where chardetz and uchardet answer differently is listed in `tests/accuracy/differences.tsv` with both answers, which one is right, and the fix that accounts for the difference (found mechanically by rebuilding the detector with each fix alone). `zig build test` fails when:

- chardetz is wrong on any case, in any feeding mode, where uchardet is right;
- the committed report or ledger differs from a fresh run, so any change in any answer must be regenerated and appears in review as a diff;
- a regeneration would lower chardetz's correct count in any feeding mode (the ratchet; `-Daccuracy-allow-regression=true` overrides it deliberately).

## Measured effect

On the generated corpus with whole input, uchardet is right on 4,444 of 4,737 cases (93.8%) and chardetz on 4,699 (99.2%). Fed one byte at a time, uchardet drops to 78.9% and chardetz stays at 99.2%; after 64 KiB of ASCII, uchardet is right on 77.0% and chardetz on 99.6%. There is no case where uchardet is right and chardetz wrong. The per-charset and per-length breakdown is in the report.

On the upstream corpus (59 files, each fed whole and in 65536-, 4096-, 7- and 1-byte chunks), uchardet gives the wrong encoding in 59 of the 295 runs (35 at 1-byte chunks, 24 at 7-byte chunks); the default mode gives the labeled encoding in all 295. Over the 20,000 seeded randomized inputs, uchardet changes its answer with the chunking in 3,165 cases (15.8%); the default mode in none.

## Candidates under evaluation

- The "Where both are wrong" table in `docs/ACCURACY_REPORT.md` lists the remaining failures, grouped. The largest groups are ISO-2022-CN text reported as ASCII at every length, and UTF-16 without a byte-order mark in non-Latin scripts, which the BOM-less UTF-16 check (it looks for NUL bytes) misses.
- Single-byte confidence on control-heavy input: upstream computes `total - ctrl` in unsigned arithmetic, which wraps when control characters outnumber the counted characters and can yield a high confidence. Upstream mode reproduces it (test "confidence reproduces upstream's unsigned (total - ctrl) wraparound" in `src/sbcs.zig`). It needs labeled evidence before it is changed.
- EUC-TW frequency orders past the end of the 5376-entry table: upstream reads out of bounds; chardetz treats them as infrequent in both modes (`docs/UPSTREAM_DEFECTS.md`).
