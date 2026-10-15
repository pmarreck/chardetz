{
	description = "chardetz: pure-Zig translation of the uchardet character-encoding detector";

	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
		flake-utils.url = "github:numtide/flake-utils";
		# Pinned translation source, differential oracle and seed corpus.
		# Changing this pin is a deliberate act: see PROVENANCE.md.
		uchardetz-src = {
			url = "github:pmarreck/uchardetz/abacfc1fc86ef7618547d7dce7cc7501e756fa31";
			flake = false;
		};
	};

	outputs = { self, nixpkgs, flake-utils, uchardetz-src }:
		flake-utils.lib.eachDefaultSystem (system:
			let
				pkgs = nixpkgs.legacyPackages.${system};
				pname = "chardetz";
				version = "0.1.0";
				zig = pkgs.zig_0_16;
				darwinUnset = pkgs.lib.optionalString pkgs.stdenv.isDarwin "unset NIX_CFLAGS_COMPILE NIX_LDFLAGS";
			in {
				packages.default = pkgs.stdenvNoCC.mkDerivation {
					inherit pname version;
					src = ./.;
					nativeBuildInputs = [ zig ];
					dontConfigure = true;
					dontFixup = true;
					buildPhase = ''
						export HOME=$TMPDIR
						export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
						${darwinUnset}
						zig build -Doptimize=ReleaseFast --prefix $out
					'';
					dontInstall = true;
				};

				checks = {
					build = self.packages.${system}.default;
					test = pkgs.stdenvNoCC.mkDerivation {
						pname = "${pname}-test";
						inherit version;
						src = ./.;
						nativeBuildInputs = [ zig pkgs.bash ];
						dontConfigure = true;
						dontFixup = true;
						buildPhase = ''
							export HOME=$TMPDIR
							export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
							export CHARDETZ_UCHARDET_SRC=${uchardetz-src}
							${darwinUnset}
							patchShebangs ./test tests/cli
							# Tests run ReleaseSafe so runtime safety checks stay compiled in;
							# the shipped artifact stays ReleaseFast.
							timeout 900 ./test --no-nix || { echo "Tests failed"; exit 1; }
						'';
						installPhase = ''
							mkdir -p $out
							echo "tests passed" > $out/result
						'';
					};
				};

				devShells.default = pkgs.mkShell {
					packages = [ zig pkgs.hyperfine ];
					CHARDETZ_UCHARDET_SRC = "${uchardetz-src}";
				};
			});
}
