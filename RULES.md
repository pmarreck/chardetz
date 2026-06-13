# RULES — invariants (never violate without an explicit, documented reason)

1. **License preservation.** Ported files (logic AND generated data tables)
   carry the MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later tri-license header +
   `SPDX-License-Identifier`. NEVER relicense ported code/tables as BSD/MIT — a
   translation is a derivative work. See `COPYING`, `PROVENANCE.md`.

2. **jj only, never raw git.** Branch: `yolo`. Use `jj git push`/`fetch` for
   GitHub. `gh` is allowed for PRs/issues/releases only.

3. **The differential gate is the spec.** Any UN-fenced divergence from the
   uchardetz oracle is a porting BUG to fix — not to fence. Fence only in
   `tests/expected_divergences.json`, each entry with a documented reason. No
   false greens.

4. **Control files (blessed-hash guarded).** Changing one requires a deliberate
   re-bless (`scripts/bless-hashes`) + human review of the tiny diff:
   - `tools/gen_tables/manifest.zig` (pinned upstream sources @ commit)
   - `tests/expected_divergences.json` (fence ledger)

5. **Generated tables are committed; never hand-edited.** Regenerate via
   `zig build gen-tables`. Each generated file carries the license header + a
   `@generated from <file> @ abacfc1f` provenance line.

6. **Builds.** ReleaseFast default in `build.zig`. Verify via `./build` / `./test`
   (nix-based) — NEVER `nix develop -c zig build` for native (host-OS libSystem
   stub breakage). Cross-compilation goes through the flake's per-target packages.

7. **No Python anywhere.** The oracle is C/Zig; harnesses are Bash/Zig.

8. **Performance.** Throughput is the selling point (large corpora). Hot paths
   declare `// complexity: O(...)`; the scaling-ratio gate (N/2N/4N/8N) and the
   two-sided constant-factor bench live in `./bm` (ReleaseFast only, never Debug).
