# chardetz

A pure-[Zig](https://ziglang.org) character-encoding detector — a faithful
translation of [uchardet](https://github.com/BYVoid/uchardet) (the Mozilla
universalchardet-lineage detector) with **no C/C++ runtime dependency**,
cross-compilable to every Zig target, and **WASM-able**.

chardetz mirrors uchardet's C ABI, so it is a **drop-in** replacement for
existing uchardet consumers.

> **Status:** early development. Milestone 1 (project infrastructure, data-table
> generation, and the differential-oracle test harness) is in progress; no
> detection probers are wired yet. See `PLAN.md`.

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
