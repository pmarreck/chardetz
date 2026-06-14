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
}
