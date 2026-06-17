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

## Beyond uchardet: `PRINTABLE-BINARY`

chardetz adds one charset uchardet doesn't know:
[`printable_binary`](https://github.com/pmarreck/printable_binary) — binary data
encoded with a fixed 256-glyph printable-UTF-8 map. It's reported as
`PRINTABLE-BINARY`. Detection is a high-precision heuristic over the **260-codepoint
allowed set** (those 256 glyphs **plus** the literal space/tab/CR/LF the preserve
modes `-s/-t/-n/-w` can emit): ≥99% of codepoints in that set, ≥10% "distinctive"
control/punctuation/high-byte glyphs, and ≥32 codepoints. It pre-empts the UTF-8
verdict only on a strong PB signal and is
otherwise inert — so it never perturbs uchardet-faithful detection (verified: the
full corpus still matches uchardet exactly, and the differential fuzz finds zero
new divergences). It's validated metamorphically (round-trip through PB's own
encoder) rather than against the oracle, since uchardet has no such charset.

## Performance

The pure-Zig rewrite isn't just a portability win — it is **faster than the C++
uchardet it ports**. Measured by `./bm` (ReleaseFast, min-of-31, Apple aarch64;
256 KiB synthetic per-path inputs — the same algorithm runs in both, so the ratio
is what matters):

| detection path | chardetz | uchardet (C++) | speedup |
|---|---:|---:|---:|
| single-byte (34-prober group) | 25.6 MB/s | 22.6 MB/s | **1.13×** |
| CJK multibyte (MBCS group) | 24.6 MB/s | 21.8 MB/s | **1.13×** |
| UTF-8 (multibyte validation) | 278 MB/s | 276 MB/s | 1.01× |
| pure-ASCII fast path | 1315 MB/s | 1574 MB/s | 0.84× |
| **aggregate** | **47.6 MB/s** | **42.4 MB/s** | **≈1.10×** |

chardetz is ~13% faster on the two heavy paths that dominate real-world
undeclared-encoding detection, at parity on UTF-8, and only trails on the trivial
ASCII fast path (>1.3 GB/s either way — far above any I/O that would feed it).

`./bm` also enforces a machine-independent **scaling-ratio gate**: it runs each hot
kernel at N/2N/4N/8N and fails if any doubling exceeds 2.5× — catching accidental
super-linear regressions. All paths are confirmed `O(n)` (worst observed 2.04×).
Per-run throughput is logged to `bench/<machine-id>.ndjson` with two-sided tolerance.

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
