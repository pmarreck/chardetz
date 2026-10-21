# Terminology

- **uchardet**: the upstream C++ detector, itself a port of Mozilla's universalchardet.
- **uchardetz**: a fork of uchardet with a Zig build system. Its pinned commit is chardetz's translation source, test-time oracle and seed corpus.
- **chardetz**: this project.
- **Prober**: a detection module for one family of encodings: multibyte state-machine probers (UTF-8, CJK), single-byte language-model probers, the Latin-1 prober, the escape-sequence (ISO-2022/HZ) prober and the Hebrew logical/visual prober. Group probers run several and pick the most confident.
- **Upstream mode**: `UpstreamDetector`, the same code compiled with every accuracy fix off, so it reproduces uchardet exactly.
- **Default mode**: `Detector`, with every accuracy fix on. This is what the Zig API, C ABI, CLI and WebAssembly module use.
- **Accuracy fix**: a named, tested change by which the default mode deliberately departs from uchardet because uchardet's answer is wrong (`docs/ACCURACY.md`).
- **Differential oracle**: running the original C++ and chardetz on identical input and comparing the reported encodings.
- **Expected-divergences ledger**: `tests/expected_divergences.json`, the hash-guarded list of accepted upstream-mode divergences, each with a reason. It is empty.
- **Chunk invariance**: the property that splitting the input into different `handle_data` calls cannot change the result. uchardet lacks it; chardetz's default mode has it.
- **PRINTABLE-BINARY**: a chardetz extension detecting text produced by the printable_binary encoder (binary data written with a fixed 256-glyph printable UTF-8 map).
