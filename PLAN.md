# PLAN

Completed items retire to `docs/PLAN_LOG.md`. Purpose: `INTENT.md`. Accuracy policy: `docs/ACCURACY.md`.

## 2026-10-21 (BDFN request): merge both translations; accuracy over bug-for-bug fidelity
- [x] Check the original development machine for the June working copy: no unpushed code, only an uncommitted wind-down note (done 2026-10-21 14:00 EDT)
- [x] Merge the October port and the June repo (engine and gates from October; PRINTABLE-BINARY, WASM ABI, bench, fuzz edge cases from June) (done 2026-10-21 14:20 EDT, db53518)
- [x] Two-mode detector: compile-time Fixes; UpstreamDetector runs every oracle gate, Detector (all fixes) is the default everywhere (done 2026-10-21 14:45 EDT)
- [x] Fix: chunk invariance by re-chunking input internally into fixed 64 KiB blocks (BOM, BOM-less UTF-16 and early-exit checks no longer depend on caller chunking) (done 2026-10-21 14:45 EDT)
- [x] Fix: an ASCII verdict from early all-ASCII input must not survive later high bytes (done 2026-10-21 14:45 EDT)
- [x] Default-mode tests: corpus ground-truth labels at every chunk size, chunk invariance over the randomized campaign; upstream behavior misses 59 of 295 corpus runs, default 0 (done 2026-10-21 14:45 EDT)
- [ ] Evaluate further fixes with labeled evidence: SBCS unsigned wrap on control-heavy input; EUC-TW orders past its frequency table (recorded as candidates in docs/ACCURACY.md)
- [ ] Push to GitHub, provision the Mechatron Prime CI webhook, verify the badge reports passing
- [x] Hand accuracy fixes and upstream defects to uchardetz, including its native-CPU Nix build that crashes with SIGILL on CPUs without AVX-512 (done 2026-10-21 14:55 EDT, llmsend)
- [x] Tell docscan that detect() now returns an error union (module name and charset names unchanged) (done 2026-10-21 14:55 EDT, llmsend)
- [ ] Report to the BDFN

## Later
- [ ] Silence the Zig warning "cannot build new glibc version 2.44.0" in the Nix native build (shown as a step failure in the log although the build exits 0)
- [ ] Apply the cross-platform-project-build-arch layout to ./build
- [ ] Decide CLI i18n (uchardetz's CLI is localized; chardetz's is English only)
