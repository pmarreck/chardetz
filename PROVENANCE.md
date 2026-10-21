# Provenance

chardetz is a C++ to Zig translation. Its detection logic and every data table derive from this lineage:

1. **Mozilla universalchardet** (Mozilla Communicator client code). Initial Developer: Netscape Communications Corporation; the upstream files carry copyright notices from 1998 and 2001. Licensed MPL 1.1 / GPL 2.0+ / LGPL 2.1+.
2. **uchardet** by BYVoid and later maintainers, which wrapped universalchardet in a C API and added language models. Same tri-license.
3. **uchardetz**, a fork of uchardet that adds a Zig build system: <https://github.com/pmarreck/uchardetz>.

## Pinned source

- Repository: `github:pmarreck/uchardetz`
- Commit: `abacfc1fc86ef7618547d7dce7cc7501e756fa31`
- Pinned in: `flake.nix` input `uchardetz-src`, locked with its content hash in `flake.lock`.
- The same revision appears in `tools/gen_tables/manifest.txt`; `./test` fails if the two disagree.

The pinned tree is used three ways: as the translation source for the table generator, as the C++ differential oracle (compiled at test time only), and as the seed test corpus (`test/<language>/<encoding>.txt`).

## What is derived

- `src/tables/*.zig` except `types.zig`, `tables_test.zig` and `all.zig`: generated mechanically by `tools/gen_tables` from the upstream files listed in the manifest. Each reproduces its upstream file's license block and names its source file and revision.
- `src/tables/types.zig`: hand port of `nsPkgInt.h` and the `SMModel`/`SequenceModel` record types.
- The prober and detector modules under `src/`: hand translations of the corresponding upstream `ns*.cpp` files, each carrying the upstream license block.
- `include/uchardet.h`: upstream's public header, byte-identical.

Not derived from uchardet: the `PRINTABLE-BINARY` prober (`src/printable_binary_prober.zig`, `src/printable_binary_table.zig`), whose glyph map `src/printable_binary_map.txt` comes from the printable_binary project, plus the build system, generator, CLI and test harnesses. The whole repository uses the tri-license for simplicity.

## History

The project was first built in June 2026 and published on GitHub. An independent second translation was written in October 2026 on another machine without knowledge of the first. The two were merged by keeping the faster, better-verified engine and generator from the second and the PRINTABLE-BINARY prober, WebAssembly ABI, benchmark, fuzz edge cases and history from the first. Both histories are preserved in Git.

## Changing the pin

Moving to a newer upstream revision is deliberate: update the flake input and the manifest `rev`, regenerate tables with `zig build gen-tables`, re-bless the manifest hash (`./bless`), and rerun `./test`.
