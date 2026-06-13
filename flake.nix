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
        };

        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [ zig pkgs.hyperfine pkgs.jq ];
        };
      });
}
