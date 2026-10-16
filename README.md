# chardetz

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fchardetz.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

A pure-Zig translation of [uchardet](https://gitlab.freedesktop.org/uchardet/uchardet), the character-encoding detector descended from Mozilla's universalchardet. The goal is identical detection results with no C or C++ dependency, cross-compiled to macOS, Linux and Windows and built for WebAssembly, behind a drop-in copy of uchardet's C API.

**Status:** every uchardet prober is ported and agrees with the C++ original on the upstream corpus (at four chunk sizes) and on 20,000 randomized inputs. The C API, command-line tool and WebAssembly build are in progress. See `PLAN.md`.

## How it is built

- Every upstream data table (language models, state machines, CJK frequency tables) is produced by a tested generator, `tools/gen_tables`, from a pinned uchardet source tree. Generated files are committed and a test fails if they drift from regeneration. A second test has the C++ compiler evaluate each upstream table file and requires every generated array, constant and model to match it byte for byte.
- Correctness is defined by a differential oracle: the original C++ is compiled at test time and fed the same input as the Zig code, and the detected encodings must match.

## Building and testing

Requires [Nix](https://nixos.org/) with flakes. Continuous integration runs on Mechatron Prime CI, a self-hosted Nix build service that builds every pushed commit of this repository and reports the result in the badge above.

```sh
./build        # optimized build (ReleaseFast)
./test         # full test suite (runs inside `nix develop`)
nix develop -c zig build gen-tables   # regenerate src/tables from the pinned source
```

## License

chardetz's detection logic and data tables are derived from uchardet and are distributed under uchardet's tri-license: the Mozilla Public License 1.1, the GNU General Public License 2.0 or later, or the GNU Lesser General Public License 2.1 or later, at your option. The full texts are in `COPYING`. The rest of the repository uses the same terms for simplicity.

Lineage and the exact upstream revision are recorded in `PROVENANCE.md`; aggregated notices are in `THIRD_PARTY_LICENSES`.
