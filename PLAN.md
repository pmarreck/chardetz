# PLAN

Completed items retire to `docs/PLAN_LOG.md`. Purpose: `INTENT.md`. Accuracy policy: `docs/ACCURACY.md`.

## 2026-10-21 (BDFN request): merge both translations; accuracy over bug-for-bug fidelity
- [x] Check the original development machine for the June working copy: no unpushed code, only an uncommitted wind-down note (done 2026-10-21 14:00 EDT)
- [ ] Merge the October port and the June repo (engine and gates from October; PRINTABLE-BINARY, WASM ABI, bench, fuzz edge cases from June)
- [ ] Two-mode detector: compile-time Fixes; UpstreamDetector runs every oracle gate, Detector (all fixes) is the default everywhere
- [ ] Fix: chunk invariance by re-chunking input internally into fixed 64 KiB blocks (BOM, BOM-less UTF-16 and early-exit checks no longer depend on caller chunking)
- [ ] Fix: an ASCII verdict from early all-ASCII input must not survive later high bytes
- [ ] Default-mode tests: corpus ground-truth labels at every chunk size, chunk invariance over the randomized campaign
- [ ] Evaluate further fixes with evidence: SBCS unsigned wrap on control-heavy input; EUC-TW orders past its frequency table
- [ ] Push to GitHub, provision the Mechatron Prime CI webhook, verify the badge reports passing
- [ ] Hand accuracy fixes and upstream defects to uchardetz, including its native-CPU Nix build that crashes with SIGILL on CPUs without AVX-512
- [ ] Tell docscan that detect() now returns an error union (module name and charset names unchanged)
- [ ] Report to the BDFN

## Later
- [ ] Silence the sandbox-only Zig warning "cannot build new glibc version 2.44.0" when linking the test-only oracle CLI
- [ ] Apply the cross-platform-project-build-arch layout to ./build
- [ ] Decide CLI i18n (uchardetz's CLI is localized; chardetz's is English only)
