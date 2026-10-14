# Rules

1. Translated logic and data tables keep uchardet's MPL 1.1 / GPL 2.0+ / LGPL 2.1+ tri-license and their upstream license blocks. Never relicense them.
2. Never hand-edit files marked `@generated`. Change the generator or the manifest and regenerate with `zig build gen-tables`.
3. A divergence from the C++ oracle is a bug. Fence one only in the expected-divergences ledger, with a written reason.
4. Control files are guarded by `blessed_hashes.txt`. Changing one requires re-blessing it with `./bless` in the same commit, and that two-file change gets human review. Current control files: `tools/gen_tables/manifest.txt` and `tests/expected_divergences.json`.
5. The core under `src/` performs no I/O. The C CLI reaches it only through the C FFI header.
6. No Python.
