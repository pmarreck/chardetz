# chardetz

A pure-Zig translation of [uchardet](https://gitlab.freedesktop.org/uchardet/uchardet), the character-encoding detector descended from Mozilla's universalchardet. The goal is identical detection results with no C or C++ dependency, cross-compiled to macOS, Linux and Windows and built for WebAssembly, behind a drop-in copy of uchardet's C API.

**Status:** early development. The data tables are translated and verified for freshness; the probers and the differential oracle gate are in progress. See `PLAN.md`.

## How it is built

- Every upstream data table (language models, state machines, CJK frequency tables) is produced by a tested generator, `tools/gen_tables`, from a pinned uchardet source tree. Generated files are committed and a test fails if they drift from regeneration.
- Correctness is defined by a differential oracle: the original C++ is compiled at test time and fed the same input as the Zig code, and the detected encodings must match.

## Building and testing

Requires [Nix](https://nixos.org/) with flakes.

```sh
./build        # optimized build (ReleaseFast)
./test         # full test suite (runs inside `nix develop`)
nix develop -c zig build gen-tables   # regenerate src/tables from the pinned source
```

## License

chardetz's detection logic and data tables are derived from uchardet and are distributed under uchardet's tri-license: the Mozilla Public License 1.1, the GNU General Public License 2.0 or later, or the GNU Lesser General Public License 2.1 or later, at your option. The full texts are in `COPYING`. The rest of the repository uses the same terms for simplicity.

Lineage and the exact upstream revision are recorded in `PROVENANCE.md`; aggregated notices are in `THIRD_PARTY_LICENSES`.
