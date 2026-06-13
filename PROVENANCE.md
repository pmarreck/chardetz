# Provenance

chardetz is a faithful C++→Zig translation of **uchardet**, which is itself a
port of **Mozilla's universalchardet** character-encoding detector.

## Lineage

- **Original Code:** Mozilla Universal charset detector. Initial Developer:
  Netscape Communications Corporation. © 2001 the Initial Developer. All Rights
  Reserved.
- **uchardet:** BYVoid \<byvoid.kcp@gmail.com\> and contributors —
  https://github.com/BYVoid/uchardet
- **uchardetz:** Peter Marreck's Zig-build fork —
  https://github.com/pmarreck/uchardetz
- **chardetz:** this project — a pure-Zig translation (no C/C++ runtime
  dependency, cross-compilable, WASM-able).

## Pinned source

Translated from **uchardetz @ `abacfc1fc86ef7618547d7dce7cc7501e756fa31`**
(branch `yolo`). Every data table under `src/tables/` is mechanically generated
from that exact commit by `tools/gen_tables/`; the pinned source manifest lives
in `tools/gen_tables/manifest.zig` and is hash-guarded against silent drift.

## Why the tables carry the upstream license

The character-mapping tables, frequency models, and state machines are the
copyrighted intellectual property of the upstream project. A translation of
them is a derivative work. Accordingly, both the ported logic and the generated
tables carry the upstream tri-license; they are **not** relicensed.

## License

Tri-licensed **MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later**, inherited from
upstream. See `COPYING` (full license text) and `THIRD_PARTY_LICENSES`.
