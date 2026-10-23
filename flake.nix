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
		# Pinned multilingual text (the UDHR in about 500 languages, UTF-8 XML) from
		# which the accuracy corpus is generated with iconv. See docs/ACCURACY.md.
		udhr-src = {
			url = "github:eric-muller/udhr/588b3f4b2d0467aff54842a4b926551b69d5a66a";
			flake = false;
		};
	};

	outputs = { self, nixpkgs, flake-utils, uchardetz-src, udhr-src }:
		flake-utils.lib.eachDefaultSystem (system:
			let
				pkgs = nixpkgs.legacyPackages.${system};
				pname = "chardetz";
				version = "0.2.0";
				zig = pkgs.zig_0_16;
				darwinUnset = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "unset NIX_CFLAGS_COMPILE NIX_LDFLAGS";

				# Static library, header and CLI for one Zig target. Native builds use
				# -Dcpu=baseline so the output does not depend on the build machine's
				# CPU (a native-CPU build can crash elsewhere with SIGILL).
				mkChardetz = { target ? null, suffix ? "", optimize ? "ReleaseFast" }: pkgs.stdenvNoCC.mkDerivation {
					pname = "${pname}${suffix}";
					inherit version;
					src = ./.;
					nativeBuildInputs = [ zig ];
					dontConfigure = true;
					dontFixup = true;
					buildPhase = ''
						export HOME=$TMPDIR
						export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
						${darwinUnset}
						zig build -Doptimize=${optimize} --prefix $out \
							${if target != null then "-Dtarget=${target}" else "-Dcpu=baseline"}
					'';
					dontInstall = true;
				};

				# The five supported platforms, plus WebAssembly (one-shot ABI, see
				# docs/wasm_abi.md).
				crossTargets = {
					aarch64-macos = { target = "aarch64-macos"; suffix = "-aarch64-macos"; };
					aarch64-linux = { target = "aarch64-linux-musl"; suffix = "-aarch64-linux"; };
					x86_64-linux = { target = "x86_64-linux-musl"; suffix = "-x86_64-linux"; };
					aarch64-windows = { target = "aarch64-windows-gnu"; suffix = "-aarch64-windows"; };
					x86_64-windows = { target = "x86_64-windows-gnu"; suffix = "-x86_64-windows"; };
				};
				cross = builtins.mapAttrs (_: mkChardetz) crossTargets;
				wasm = mkChardetz { target = "wasm32-freestanding"; suffix = "-wasm"; optimize = "ReleaseSmall"; };
			in {
				packages = cross // {
					default = mkChardetz { };
					inherit wasm;
				};

				checks = {
					build = self.packages.${system}.default;
					# Every supported platform and the WebAssembly module build.
					cross = pkgs.linkFarm "chardetz-cross" (pkgs.lib.mapAttrsToList (name: drv: { inherit name; path = drv; }) (cross // { inherit wasm; }));
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
							export CHARDETZ_UDHR_SRC=${udhr-src}
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
					packages = [ zig pkgs.hyperfine pkgs.nodejs ];
					CHARDETZ_UCHARDET_SRC = "${uchardetz-src}";
					CHARDETZ_UDHR_SRC = "${udhr-src}";
				};
			});
}
