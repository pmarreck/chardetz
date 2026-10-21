# Rules

1. Translated logic and data tables keep uchardet's MPL 1.1 / GPL 2.0+ / LGPL 2.1+ tri-license and their upstream license blocks. Never relicense them.
2. Never hand-edit files marked `@generated`. Change the generator or the manifest and regenerate with `zig build gen-tables`.
3. In upstream mode, any divergence from the C++ oracle is a porting bug. Fence one only in `tests/expected_divergences.json`, with a written reason.
4. The default mode departs from uchardet only through a documented accuracy fix that meets `docs/ACCURACY.md`.
5. Control files are guarded by `blessed_hashes.txt`. Changing one requires re-blessing it with `./bless` in the same commit, and that two-file change gets human review. Current control files: `tools/gen_tables/manifest.txt` and `tests/expected_divergences.json`.
6. The core under `src/` performs no I/O. The C CLI reaches it only through `include/uchardet.h`, which stays byte-identical to upstream's header.
7. Pushed history is never rewritten: downstream projects pin commits of this repository.
8. Hot paths declare `// complexity:`; `./bm` holds the scaling-ratio gate and the constant-factor benchmark (ReleaseFast only).
9. No Python.
