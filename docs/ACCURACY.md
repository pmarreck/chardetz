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
| (none yet) | | | |
