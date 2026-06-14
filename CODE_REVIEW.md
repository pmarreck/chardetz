# Code Review — chardetz
**Date:** 2026-06-14
**Reviewer:** Claude (deep-code-review skill, run solo across all 11 dimensions)
**Scope:** Full codebase audit of the completed detection engine (`src/`, `cli/`, `tools/`, `tests/`, build/CI scripts)

## Summary

- **CRITICAL:** 0
- **WARN:** 1 (the one warning — the `./bm` stub — was **resolved** during the
  perf-review phase; see below and `PERF_REVIEW.md`)
- **INFO:** 8

chardetz is in excellent shape. It is a faithful, line-referenced port of uchardet
(`@ abacfc1f`) with strong **MFIC** backing: a differential oracle test against the
real C++ uchardet (`tests/differential/oracle_link_test.zig`, 59/59 corpus, zero
divergence), a seeded differential fuzz harness (`tests/fuzz/differential_fuzz.zig`),
and CLI-vs-CLI parity (`tests/cli/parity.sh`). Those three controls make a *correctness*
divergence from uchardet essentially refutable — and none was found.

The clean-code scan came back clean: **no** `catch unreachable` in production, **no**
`catch {}` swallows, **no** `page_allocator` misuse, **no** `anyerror`, **no** real
`TODO`/`FIXME`. Tests use `std.testing.allocator` (leak detection). Memory handling on
the FFI boundary and in the buffer-filter paths is correct (`defer`/`errdefer` present
and scoped to the owning allocation).

The single real gap is that the **benchmark suite (`./bm`) was never built past its M1
skeleton** — it does not benchmark anything and does not compare to uchardet, despite the
engine being complete and public. That is the headline action item and is addressed in
the performance-review phase.

---

## Warnings

### `bm:1-14` — `./bm` is a stale M1 stub: no benchmark, no uchardet comparison — ✅ RESOLVED
**Dimension:** 1 (Incomplete / Undefined Functionality)
**Status:** Fixed in the perf-review phase. `./bm` now runs a real benchmark
(`bench/bench.zig`): a hard machine-independent scaling-ratio gate over two declared-O(n)
kernels, plus a chardetz-vs-C++-uchardet throughput comparison logged to
`bench/<machine-id>.ndjson` with two-sided tolerance. Result: chardetz is ~1.10× faster
than uchardet in aggregate, all hot paths confirmed linear. See `PERF_REVIEW.md`. The
original finding is retained below for the record.


`./bm` still contains its M1-era placeholder: it computes a machine-id, prints
*"No runtime benchmarks in M1 — detection probers arrive in M2+, full perf gate in M5,"*
and `exit 0`. The probers it was waiting for now exist and are public, so the script's
own deferral condition is satisfied but the work was never done. Consequences:

- The house perf-MVP rule (CLAUDE.md) requires a **scaling-ratio gate (N/2N/4N/8N)** and
  a **two-sided constant-factor ndjson log** *as soon as main functionality hits MVP*.
  The engine is past MVP; the gate is absent.
- The kickoff's headline selling point — pure-Zig throughput vs C++ uchardet — is
  **unmeasured**. We claim parity of *correctness* (proven) but have no number for *speed*.
- `bench/.gitkeep` exists but no `bench/<machine-id>.ndjson` is ever written.

**Fix:** Replace the stub with a real per-function benchmark that (a) runs the detection
engine over fixed corpora at multiple sizes and asserts the growth ratio matches the
declared per-function complexity, and (b) runs the same inputs through the C++ uchardet
oracle (already linkable via the `zigDeps` cache the oracle/fuzz suites use) and reports
chardetz-vs-uchardet throughput, logging to `bench/<machine-id>.ndjson` with two-sided
tolerance. (In progress — see PERF_REVIEW.md.)

---

## Informational

### `src/char_distribution_analysis.zig:81` — EUC-TW dual-bounds clamp (documented deviation)
**Dimension:** 9 (Memory Safety) / 2 (Coverage)

`handleOneChar` guards `uorder < table_size AND uorder < char_to_freq_order.len`. The
second conjunct is a chardetz-specific safety addition: the EUC-TW table declares
`table_size = 8102` but the compiled `char_to_freq_order` array is ~5378 entries, and
`getOrder` can reach ~5545 — C++ reads OOB there (UB, effectively "never frequent"); Zig
would panic. The clamp + the array padding (`tables/char_distribution.zig`) are
defense-in-depth (physics + policy). Per PLAN.md/memory this latent path **no longer
reproduces** after the SMState-UB fix, so the guard is currently belt-and-suspenders.
*Suggestion:* add a tripwire test that deliberately drives `getOrder` to a value in
`[len, table_size)` and asserts no panic, so the guard's necessity is documented by a
biting test rather than prose (per the "workarounds need detection" rule).

### `src/char_distribution_analysis.zig:46` — `done` field unused by the live path
**Dimension:** 4 (Superfluous Functionality)

`done: bool` is set in `reset`/`init` but never read on any active code path (the comment
says "kept for fidelity; GotEnoughData is the live gate"). Harmless; flagged only so a
future reader doesn't assume it gates anything. Keep for fidelity or drop — either is fine.

### `src/detector.zig:276,285` / `sbcs_group.zig:236,239` / `mbcs_group.zig:170,173` — `proberSlice()` rebuilt redundantly
**Dimension:** 6 (Algorithmic Complexity)

The polymorphic handle array is correctly rebuilt-on-demand (pointer stability after
by-value `init`), but several methods rebuild it more than once per call:
`detector.dataEnd` builds it for the argmax loop *and* again for `…[max_prober].charsetName()`;
`*.charsetName` calls `getConfidence` (which builds) then builds again. Each rebuild is
3–35 pointer writes (not in the byte loop), so the cost is negligible — but it's avoidable
by caching the slice in a local. INFO-level; only worth doing if a benchmark shows it.

### `src/probers/sbcs_group.zig:180` / `latin1.zig:105` / `filter.zig` — heap alloc+free per `handleData`
**Dimension:** 6 (Algorithmic Complexity)

Each SBCS-group and Latin-1 `handleData` allocates a filter buffer of `buf.len` and frees
it on return. This is **faithful to upstream** (uchardet allocates a filter buffer per
HandleData too), so it is not a divergence — but for a streaming consumer feeding many
small chunks it is one alloc/free per chunk. If the perf review shows filtering dominates,
a reusable scratch buffer on the prober (cleared per call) would remove the churn without
changing behavior. Note only.

### `cli/main.c:78-92` — `slurp` could spin on a non-conforming stream
**Dimension:** 11 (Error Handling)

The read loop breaks only on `feof`, and errors only on `ferror`. A stream that returns
`0` from `fread` without setting EOF or error (non-conforming, e.g. some exotic FIFOs)
would loop forever. Real files and pipes set EOF/error correctly, so this is theoretical;
flagged for completeness. A bounded "N consecutive zero-reads → treat as EOF" guard would
close it.

### `cli/main.c:58-59` — `--simple` / `--no-color` are documented no-ops
**Dimension:** 1 (API surface vs implementation)

Both flags are accepted and documented as "currently a no-op alias." The CLI output is
already plain text, so this is honest and harmless — but the `--help` text promises a
capability the code doesn't yet exercise. Fine to leave until ANSI/decoration is added;
the help string already hedges with "currently."

### `src/*` mapping/classifier tables not unit-tested per value
**Dimension:** 2 (Test Coverage)

The fixed 256-entry classifier tables (`Latin1_CharToClass`, the SBCS `char_to_order_map`s,
the per-charset `getOrder` byte-math) are validated *integrally* by the oracle + fuzz, but
there is no per-value classifier test over the full input set (the house rule: test filters
"as classifiers over sets, not predicates over single examples"). The oracle makes a
regression unlikely, but a small exhaustive table test (all 256 bytes → expected class) for
`Latin1_CharToClass` and a boundary sweep for each `getOrder` would catch a table-codegen
slip without needing the C++ oracle present. Low priority given the oracle.

### `tools/gen_tables/manifest.zig` + `tests/expected_divergences.json` — control files, blessed-hash guarded
**Dimension:** 10 (FFI/Boundary) / general

Noted as healthy, not a problem: both are MFIC control files guarded by
`scripts/check-blessed-hashes` (wired into `./test`). The fuzz ledger is intentionally
empty (strict-green). This is the desired posture; recorded here so the control surface is
explicit in the review.

---

## Dimensions with no findings

- **3 (Futile test coverage):** tests assert on real verdicts (charset names, confidences,
  state transitions) and the oracle/fuzz are non-vacuous (vacuity guard `checked > 0`).
- **5 (Disorganized code):** files are focused, one prober per file, consistent naming;
  longest source file is `detector.zig` at 317 lines.
- **7 (Files without purpose):** every file maps to a uchardet translation unit or a
  generator/test role; no orphans.
- **8 (Language features):** idiomatic Zig 0.16 — tagged `ProbingState`, non-exhaustive
  `SMState`, comptime `@export` blocks, `errdefer` in the filters, vtable erasure for the
  `Prober` interface.
- **9 (Memory safety):** clean (covered above; FFI uses `c_allocator`, WASM uses
  `wasm_allocator`, filters `defer`-free, tests leak-check).
- **10 (FFI correctness):** `ffi.zig` null-checks every handle, copies the charset name
  into a private NUL-terminated buffer (robust C-string contract), maps errors to C
  return codes consistently, and the C CLI dogfoods the exact ABI.
