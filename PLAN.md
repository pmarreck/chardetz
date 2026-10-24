# PLAN

Completed items retire to `docs/PLAN_LOG.md`. Purpose: `INTENT.md`. Accuracy policy: `docs/ACCURACY.md`.

## 2026-10-21 (BDFN request): merge both translations; accuracy over bug-for-bug fidelity
- [x] Two-mode detector: compile-time Fixes; UpstreamDetector runs every oracle gate, Detector (all fixes) is the default everywhere (done 2026-10-21 14:45 EDT)
- [x] Fix: chunk invariance by re-chunking input internally into fixed 64 KiB blocks (BOM, BOM-less UTF-16 and early-exit checks no longer depend on caller chunking) (done 2026-10-21 14:45 EDT)
- [x] Fix: an ASCII verdict from early all-ASCII input must not survive later high bytes (done 2026-10-21 14:45 EDT)
- [x] Default-mode tests: corpus ground-truth labels at every chunk size, chunk invariance over the randomized campaign; upstream behavior misses 59 of 295 corpus runs, default 0 (done 2026-10-21 14:45 EDT)
- [ ] Evaluate further fixes with labeled evidence: SBCS unsigned wrap on control-heavy input; EUC-TW orders past its frequency table (recorded as candidates in docs/ACCURACY.md)
- [ ] Push to GitHub, provision the Mechatron Prime CI webhook, verify the badge reports passing
- [x] Hand accuracy fixes and upstream defects to uchardetz, including its native-CPU Nix build that crashes with SIGILL on CPUs without AVX-512 (done 2026-10-21 14:55 EDT, llmsend)
- [x] Tell docscan that detect() now returns an error union (module name and charset names unchanged) (done 2026-10-21 14:55 EDT, llmsend)
- [ ] Report to the BDFN

## 2026-10-23 (BDFN request): larger accuracy suite
- [x] Larger labeled test corpus: 4,737 iconv-generated UDHR cases, ground truth by decoding, three feeding modes; differences ledger, generated report, never-worse-than-uchardet rule and ratchet in ./test (done 2026-10-23 19:05 EDT)
- [x] Fix valid_utf8: valid multibyte UTF-8 is reported as UTF-8; whole-input accuracy 93.8% to 99.2% on the generated corpus (done 2026-10-23 19:05 EDT)
- [x] Commit the generated accuracy corpus as tests/accuracy/corpus.tar.zst (2.1 MB, read in memory in 0.3 s) so ./test needs no iconv; regenerate-and-compare freshness check on Linux and in a cached Nix check (done 2026-10-24 00:35 EDT)
- [ ] Speed up corpus generation (about 80 s, mostly repeated iconv decodes for the acceptable sets); only the freshness check pays it now
- [ ] Investigate ISO-2022-CN reported as ASCII at every length (8 cases in docs/ACCURACY_REPORT.md)
- [ ] Evaluate a fix for BOM-less UTF-16 in non-Latin scripts (16 cases)
- [x] Hand valid_utf8 and the accuracy corpus approach to uchardetz (done 2026-10-23 19:20 EDT, llmsend)

## 2026-10-23 (BDFN request): conform to cross-platform-project-build-arch
- [ ] Inventory current outputs and entrypoints (result, result-*, zig-out, no bin/) and agree target matrix, profiles and rollback before moving anything
- [ ] Rename project-controlled platform names to PF: flake cross packages and output links become macos-arm64, linux-amd64, linux-arm64, mswin-amd64, mswin-arm64 (compiler triples unchanged inside the build)
- [ ] Record VARIANT where it applies: linux targets musl, mswin targets gnu, native Linux build gnu; record actual target and CPU baseline in build metadata
- [ ] Decide and document the WebAssembly product's namespace (outside the five-PF matrix)
- [ ] ./build: Nix by default, retained output link .nix-out/<PF>/<profile>, publish bin/<PF>/chardetz only after success, previous selection kept on failure, publications serialized; --backend=direct installs to zig-out/<PF>/[<VARIANT>/]<profile>/
- [ ] ./build --all-plats / --all-platforms replaces ./build-all; update README, docs/wasm_abi.md and other callers together
- [ ] Add ./run (ensure current host build, then exec bin/<PF>/chardetz)
- [ ] Narrow .gitignore rules for bin/<PF>/, .nix-out/, .build-work/ and dist/ without hiding tracked scripts
- [ ] Tests for build/publication: stubbed builder records calls; failure keeps previous entrypoint; cross build does not retarget the host entrypoint; header check (ELF/Mach-O/PE) of every published product
- [ ] Runtime evidence per platform: linux-amd64 here, macos-arm64 on the Mac, mswin pending a Windows host (cross-compile is compile evidence only)

## Later
- [ ] Silence the Zig warning "cannot build new glibc version 2.44.0" in the Nix native build (shown as a step failure in the log although the build exits 0)
- [ ] Decide CLI i18n (uchardetz's CLI is localized; chardetz's is English only)
