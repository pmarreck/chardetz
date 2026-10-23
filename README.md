# chardetz

[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fchardetz.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)

A pure-[Zig](https://ziglang.org) character-encoding detector, translated from [uchardet](https://gitlab.freedesktop.org/uchardet/uchardet) (the Mozilla universalchardet lineage). It has no C or C++ dependency, cross-compiles to macOS, Linux and Windows, builds for WebAssembly, and exposes a drop-in copy of uchardet's C API.

**Status:** every uchardet prober is ported, and the translation agrees with the C++ original on the upstream corpus at four chunk sizes and on 20,000 seeded randomized inputs. Every generated data table matches the C++ compiler's evaluation byte for byte. By default chardetz is more accurate than uchardet. On a generated corpus of 4,737 texts in about 500 languages and every charset uchardet claims, it is right on 99.2% with whole input against uchardet's 93.8%, and its answer no longer depends on how the input is split (uchardet falls to 78.9% when fed one byte at a time). There is no case where uchardet is right and chardetz wrong. The test suite enforces that, and every difference is listed with the fix that causes it (`docs/ACCURACY_REPORT.md`). A build with the fixes off (`UpstreamDetector`) is what the differential tests compare with uchardet. The policy is in `docs/ACCURACY.md`.

## Using it

- **Zig:** add this repository as a `build.zig.zon` dependency and import the `chardetz` module. `chardetz.detect(allocator, bytes)` returns the charset name (`""` when undetermined); `chardetz.Detector` is the streaming interface (`handleData`, `dataEnd`, `charset`).
- **C:** link `libchardetz.a` and include `uchardet.h`, which is byte-identical to upstream's header (`uchardet_new`, `uchardet_handle_data`, `uchardet_data_end`, `uchardet_get_charset`, `uchardet_reset`, `uchardet_delete`).
- **Command line:** `chardetz FILE...` prints the same output as the `uchardet` tool. `--json` emits one object per input; `--about` prints a one-line description and the platform. Use `-` or `@stdin` for standard input.
- **WebAssembly:** `nix build .#wasm` produces `chardetz.wasm` with a one-shot ABI; see `docs/wasm_abi.md`.

## Beyond uchardet: `PRINTABLE-BINARY`

chardetz detects one encoding uchardet doesn't know: text produced by [printable_binary](https://github.com/pmarreck/printable_binary), which writes binary data using a fixed map of 256 printable UTF-8 glyphs. It is reported as `PRINTABLE-BINARY` only on a strong signal: at least 99% of codepoints from the glyph set (plus literal whitespace), at least 10% of them distinctive glyphs, and at least 32 codepoints. Otherwise the prober is inert, so it never changes uchardet's answer for ordinary text.

## How correctness is established

- **Tables:** a tested generator (`tools/gen_tables`) produces every data table from the pinned uchardet source. A test fails if the committed tables drift from regeneration, and a second test has the C++ compiler evaluate each upstream table file and requires every array, constant and model to match byte for byte.
- **Logic:** the original C++ is compiled at test time and run beside the Zig code over the upstream corpus (whole files and 4096-, 7- and 1-byte chunks) and over seeded randomized inputs: generated, mutated, spliced, sliced and boundary-case data in random chunk sizes. The answers must match exactly.
- **Whole programs:** the chardetz CLI and the uchardet CLI must print identical output for every corpus file, and the C ABI has its own contract test.

## Building and testing

Requires [Nix](https://nixos.org/) with flakes. Continuous integration runs on Mechatron Prime CI, a self-hosted Nix build service that builds every pushed commit of this repository and reports the result in the badge above.

```sh
./build        # optimized native build (library, header, CLI) into ./result
./build-all    # all five platforms plus WebAssembly
./test         # the complete test suite
./fuzz         # a longer randomized differential campaign
./bm           # throughput benchmark and scaling-ratio gate
nix develop -c zig build gen-tables   # regenerate src/tables from the pinned source
```

## License

chardetz's detection logic and data tables are derived from uchardet and are distributed under uchardet's tri-license: the Mozilla Public License 1.1, the GNU General Public License 2.0 or later, or the GNU Lesser General Public License 2.1 or later, at your option. The full texts are in `COPYING`; the rest of the repository uses the same terms for simplicity. Lineage and the exact upstream revision are in `PROVENANCE.md`, notices in `THIRD_PARTY_LICENSES`, and upstream defects found during translation in `docs/UPSTREAM_DEFECTS.md`.
