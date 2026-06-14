{
  description = "chardetz - pure-Zig character-encoding detector (uchardet port), no C/C++ dependency, WASM-able";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        zig = pkgs.zig_0_16; # PIN: bare pkgs.zig drifts and breaks CI silently.

        # ── Zig dependency cache (fixed-output derivation) ──
        # The oracle test (Phase 8) pulls in uchardetz via build.zig.zon. Nix's
        # build sandbox has no network, so we fetch the whole dependency tree
        # in a fixed-output derivation (network allowed because the output hash
        # is declared) and copy it into ZIG_GLOBAL_CACHE_DIR for the consumer.
        # Regenerate zigDepsHash whenever build.zig.zon .dependencies change:
        # set it to pkgs.lib.fakeHash, run `nix build`, copy the printed hash.
        zigDepsHash = "sha256-4J9q0uChnPo2P6plu35Jy5pPGTA252lNy9bfVRqp408=";
        zigDeps = pkgs.stdenvNoCC.mkDerivation {
          pname = "chardetz-zig-deps";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [ zig pkgs.git pkgs.cacert ];
          dontConfigure = true;
          dontFixup = true;
          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = zigDepsHash;
          buildPhase = ''
            export HOME=$TMPDIR
            export ZIG_GLOBAL_CACHE_DIR=$out
            export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            export GIT_SSL_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            zig build --fetch=all
          '';
          installPhase = "true";
        };

        # Build the static library for a Zig target triple (native when null).
        mkChardetz = { target ? null, suffix ? "" }: pkgs.stdenvNoCC.mkDerivation {
          pname = "chardetz${suffix}";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [ zig ];
          dontConfigure = true;
          dontFixup = true;
          buildPhase = ''
            export XDG_CACHE_HOME=$(mktemp -d)
            zig build -Doptimize=ReleaseFast --prefix $out \
              ${if target != null then "-Dtarget=${target}" else ""}
          '';
          installPhase = "true";
        };

        # WASM target: wasm32-freestanding, exports the one-shot chardetz_detect
        # ABI (see docs/wasm_abi.md). The C CLI / libc static lib are skipped in
        # build.zig when targeting wasm; this produces only the .wasm.
        mkWasm = pkgs.stdenvNoCC.mkDerivation {
          pname = "chardetz-wasm";
          version = "0.1.0";
          src = ./.;
          nativeBuildInputs = [ zig ];
          dontConfigure = true;
          dontFixup = true;
          buildPhase = ''
            export XDG_CACHE_HOME=$(mktemp -d)
            zig build -Doptimize=ReleaseSmall -Dtarget=wasm32-freestanding --prefix $out
          '';
          installPhase = "true";
        };

        # 5 house targets: macOS aarch64, Linux aarch64/x86_64, Windows aarch64/x86_64.
        crossTargets = {
          aarch64-macos   = { target = "aarch64-macos";       suffix = "-aarch64-macos"; };
          aarch64-linux   = { target = "aarch64-linux-musl";  suffix = "-aarch64-linux"; };
          x86_64-linux    = { target = "x86_64-linux-musl";   suffix = "-x86_64-linux"; };
          aarch64-windows = { target = "aarch64-windows-gnu"; suffix = "-aarch64-windows"; };
          x86_64-windows  = { target = "x86_64-windows-gnu";  suffix = "-x86_64-windows"; };
        };
      in
      {
        packages.default = mkChardetz {};
        packages.aarch64-macos   = mkChardetz crossTargets.aarch64-macos;
        packages.aarch64-linux   = mkChardetz crossTargets.aarch64-linux;
        packages.x86_64-linux    = mkChardetz crossTargets.x86_64-linux;
        packages.aarch64-windows = mkChardetz crossTargets.aarch64-windows;
        packages.x86_64-windows  = mkChardetz crossTargets.x86_64-windows;
        packages.wasm            = mkWasm;

        # Garnix auto-evaluates these. checks (not checks.${system}) — eachDefaultSystem
        # already nests per-system; double-nesting would yield checks.<sys>.<sys>.
        checks = {
          build = self.packages.${system}.default;
          test = pkgs.stdenvNoCC.mkDerivation {
            pname = "chardetz-test";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ zig ];
            dontConfigure = true;
            dontFixup = true;
            buildPhase = ''
              export XDG_CACHE_HOME=$(mktemp -d)
              timeout 600 zig build test || { echo "Tests failed"; exit 1; }
            '';
            installPhase = ''
              mkdir -p $out
              echo "tests passed" > $out/result
            '';
          };

          # Phase 8: differential oracle test. Links uchardetz's C++ (via the
          # zigDeps cache) and drives its C ABI from a Zig test. Separate from
          # `test` because it needs the network-fetched dep + C++ toolchain.
          oracle-test = pkgs.stdenvNoCC.mkDerivation {
            pname = "chardetz-oracle-test";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ zig ];
            dontConfigure = true;
            dontFixup = true;
            buildPhase = ''
              export HOME=$TMPDIR
              export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
              mkdir -p $ZIG_GLOBAL_CACHE_DIR
              cp -r ${zigDeps}/* $ZIG_GLOBAL_CACHE_DIR/
              chmod -R u+w $ZIG_GLOBAL_CACHE_DIR
              timeout 600 zig build test-oracle -Dwith-oracle \
                || { echo "Oracle test failed"; exit 1; }
            '';
            installPhase = ''
              mkdir -p $out
              echo "oracle test passed" > $out/result
            '';
          };

          # Differential FUZZ. Same C++ link as oracle-test (via the zigDeps
          # cache), but drives MANY generated/mutated buffers through BOTH
          # chardetz and the uchardet C ABI, asserting agreement. Seeded &
          # deterministic (CHARDETZ_FUZZ_SEED). Iteration budget is modest here
          # so CI stays fast; `./fuzz` can crank it via CHARDETZ_FUZZ_ITERS.
          fuzz = pkgs.stdenvNoCC.mkDerivation {
            pname = "chardetz-fuzz";
            version = "0.1.0";
            src = ./.;
            nativeBuildInputs = [ zig ];
            dontConfigure = true;
            dontFixup = true;
            buildPhase = ''
              export HOME=$TMPDIR
              export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
              mkdir -p $ZIG_GLOBAL_CACHE_DIR
              cp -r ${zigDeps}/* $ZIG_GLOBAL_CACHE_DIR/
              chmod -R u+w $ZIG_GLOBAL_CACHE_DIR
              export CHARDETZ_FUZZ_ITERS=''${CHARDETZ_FUZZ_ITERS:-6000}
              timeout 900 zig build test-fuzz -Dwith-fuzz \
                || { echo "Fuzz harness failed"; exit 1; }
            '';
            installPhase = ''
              mkdir -p $out
              echo "fuzz passed" > $out/result
            '';
          };
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [ zig pkgs.hyperfine pkgs.jq ];
        };
      });
}
