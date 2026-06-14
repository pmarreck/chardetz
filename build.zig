const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	// House rule: ReleaseFast default (NOT standardOptimizeOption, which defaults to Debug).
	const optimize = b.option(
		std.builtin.OptimizeMode,
		"optimize",
		"Optimization mode (default: ReleaseFast)",
	) orelse .ReleaseFast;

	// ── Core module (pure Zig, no I/O) — exposed to downstream Zig consumers ──
	// Also imported by the test aggregator under the name "chardetz" (Zig 0.16
	// forbids `@import("../src/..")` across module roots, so tests reach the
	// core via this named import, never relative paths).
	const core_mod = b.addModule("chardetz", .{
		.root_source_file = b.path("src/chardetz.zig"),
		.target = target,
		.optimize = optimize,
	});

	// Generator module — imported by generator unit tests.
	const gen_mod = b.addModule("gen_tables", .{
		.root_source_file = b.path("tools/gen_tables/root.zig"),
		.target = target,
		.optimize = optimize,
	});

	// ── Static library (compilation artifact; the uchardet-compatible C FFI lands in M5) ──
	const lib = b.addLibrary(.{
		.name = "chardetz",
		.linkage = .static,
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/chardetz.zig"),
			.target = target,
			.optimize = optimize,
		}),
	});
	b.installArtifact(lib);

	// Generator executable — runs natively to write src/tables/
	const gen_exe = b.addExecutable(.{
		.name = "gen-tables",
		.root_module = b.createModule(.{
			.root_source_file = b.path("tools/gen_tables/main.zig"),
			.target = b.graph.host,
			.optimize = optimize,
		}),
	});
	b.installArtifact(gen_exe);

	b.step("gen-tables", "Generate SBCS tables from uchardet source").dependOn(&b.addRunArtifact(gen_exe).step);

	// ── Unit + generator tests (aggregated via tests/all.zig) ──
	const tests = b.addTest(.{
		.root_module = b.createModule(.{
			.root_source_file = b.path("tests/all.zig"),
			.target = target,
			.optimize = optimize,
			.imports = &.{
				.{ .name = "chardetz", .module = core_mod },
				.{ .name = "gen_tables", .module = gen_mod },
			},
		}),
	});
	// Zig 0.16 self-hosted backend can SEGV compiling tests on x86_64 Debug; force LLVM.
	tests.use_llvm = true;
	const run_tests = b.addRunArtifact(tests);
	b.step("test", "Run unit + generator tests").dependOn(&run_tests.step);

	// ── Phase 8: differential oracle test (opt-in; links uchardetz C++) ──
	// Off by default so the hermetic `test` step stays pure-Zig. Enabled via
	// `-Dwith-oracle` and run through the dedicated `test-oracle` step (and the
	// flake's oracle-test check). Links uchardetz's `uchardet-static` artifact
	// (C++, link_libcpp) and exposes its C ABI through a translate-c module
	// (Zig 0.16 deprecates source-level @cImport).
	const with_oracle = b.option(
		bool,
		"with-oracle",
		"Build the differential oracle test (links uchardetz C++)",
	) orelse false;
	if (with_oracle) {
		const uz = b.dependency("uchardetz", .{ .target = target, .optimize = optimize });
		const uz_lib = uz.artifact("uchardet-static");

		// translate-c: turn uchardet.h into an importable Zig module named "c".
		const translate_c = b.addTranslateC(.{
			.root_source_file = b.path("tests/differential/c_imports.h"),
			.target = target,
			.optimize = optimize,
		});
		translate_c.addIncludePath(uz.path("src")); // where uchardet.h lives
		const c_mod = translate_c.createModule();

		const diff_mod = b.createModule(.{
			.root_source_file = b.path("tests/differential/oracle_link_test.zig"),
			.target = target,
			.optimize = optimize,
			.link_libcpp = true, // uchardet is C++
			.imports = &.{
				.{ .name = "chardetz", .module = core_mod },
				.{ .name = "c", .module = c_mod },
			},
		});
		diff_mod.linkLibrary(uz_lib); // brings in symbols + propagates include path

		const diff_tests = b.addTest(.{ .root_module = diff_mod });
		diff_tests.use_llvm = true; // same SEGV-avoidance as the main test step
		const run_diff = b.addRunArtifact(diff_tests);
		b.step("test-oracle", "Run the differential oracle test (links uchardetz C++)").dependOn(&run_diff.step);
	}
}
