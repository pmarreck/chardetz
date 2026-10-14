# Provenance

chardetz is a C++ to Zig translation. Its detection logic and every data table derive from the following lineage:

1. **Mozilla universalchardet** (Mozilla Communicator client code). Initial Developer: Netscape Communications Corporation, portions copyright (C) 1998. Licensed MPL 1.1 / GPL 2.0+ / LGPL 2.1+.
2. **uchardet** by BYVoid and later maintainers (BYVoid, Jehan), which wrapped universalchardet in a C API and added language models. Same tri-license.
3. **uchardetz**, a fork of uchardet that adds a Zig build system: <https://github.com/pmarreck/uchardetz>.

## Pinned source

- Repository: `github:pmarreck/uchardetz`
- Commit: `abacfc1fc86ef7618547d7dce7cc7501e756fa31`
- Pinned in: `flake.nix` input `uchardetz-src`, locked with its content hash in `flake.lock`.
- The same revision appears in `tools/gen_tables/manifest.txt`; `./test` fails if the two disagree.

The pinned tree is used three ways: as the translation source for the table generator, as the C++ differential oracle (test time only), and as the seed test corpus (`test/<language>/<encoding>.txt`).

## What is derived

- `src/tables/*.zig` except `types.zig`, `tables_test.zig` and `all.zig`: generated mechanically by `tools/gen_tables` from the upstream files listed in the manifest. Each file reproduces its upstream license block and names its source file and revision.
- `src/tables/types.zig`: hand port of `nsPkgInt.h` and the `SMModel`/`SequenceModel` record types.
- Prober logic under `src/` (as it lands): hand translations of the corresponding upstream `ns*.cpp` files, each carrying the upstream license block.

## Changing the pin

Moving to a newer upstream revision is deliberate: update the flake input and the manifest `rev`, regenerate tables with `zig build gen-tables`, re-bless the manifest hash (`./bless`), and rerun the full differential gate.
