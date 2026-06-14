# chardetz

[![Garnix](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fgarnix.io%2Fapi%2Fbadges%2Fpmarreck%2Fchardetz%3Fbranch%3Dyolo)](https://garnix.io/repo/pmarreck/chardetz)

A pure-[Zig](https://ziglang.org) character-encoding detector — a faithful
translation of [uchardet](https://github.com/BYVoid/uchardet) (the Mozilla
universalchardet-lineage detector) with **no C/C++ runtime dependency**,
cross-compilable to every Zig target, and **WASM-able**.

chardetz mirrors uchardet's C ABI, so it is a **drop-in** replacement for
existing uchardet consumers.

> **Status:** the full detection engine is complete and verified at **oracle
> parity** — chardetz matches uchardet exactly across the entire test corpus
> (every charset uchardet supports: UTF-8/16/32, the CJK multibyte set, all
> single-byte language models, Hebrew, Latin-1, and the ISO-2022/HZ escape
> sets), backed by a differential fuzz harness. A drop-in `uchardet_*` C ABI and
> a C CLI are included. See `PLAN.md`.

## Why

uchardet is excellent but is C++, which complicates static linking, cross-
compilation, and especially WebAssembly. chardetz removes the C/C++ toolchain
requirement while preserving uchardet's tables and logic exactly — validated by
a differential oracle against the original.

## Building

```bash
./build      # nix build (sandboxed, ReleaseFast) — static library
./test       # full test suite (hermetic Zig tests; differential oracle harness)
```

(Uses Nix; native `zig build` is intentionally avoided — see `RULES.md`.)

## License

chardetz is a **derivative work** of uchardet / Mozilla universalchardet. Its
ported logic and generated data tables carry the upstream license and are **not**
relicensed.

**Tri-licensed: [MPL 1.1](https://www.mozilla.org/MPL/1.1/) /
GPL 2.0-or-later / LGPL 2.1-or-later.**

Full text in [`COPYING`](COPYING). Lineage and the pinned upstream commit are
documented in [`PROVENANCE.md`](PROVENANCE.md); attributions in
[`THIRD_PARTY_LICENSES`](THIRD_PARTY_LICENSES).
