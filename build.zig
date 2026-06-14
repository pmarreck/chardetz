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

	const is_wasm = target.result.cpu.arch.isWasm();

	if (is_wasm) {
		// ── WASM target: freestanding, exports the one-shot chardetz_detect ABI. ──
		// `-Dtarget=wasm32-freestanding`. The FFI uses std.heap.wasm_allocator
		// here (no libc). ReleaseSmall keeps the .wasm tiny. Export symbols come
		// from src/lib.zig → ffi.zig. The C CLI / libc static lib are NOT built
		// for WASM (freestanding has no libc).
		const wasm_mod = b.createModule(.{
			.root_source_file = b.path("src/lib.zig"),
			.target = target,
			.optimize = optimize,
		});
		const wasm = b.addExecutable(.{ .name = "chardetz", .root_module = wasm_mod });
		wasm.entry = .disabled; // no _start; we export functions
		wasm.rdynamic = true; // keep exported symbols
		b.installArtifact(wasm);
	} else {
		// ── Static library: the uchardet-compatible C FFI (drop-in ABI) ──
		// Root is src/lib.zig (core + ffi exports). Links libc because the FFI's
		// handle allocator is std.heap.c_allocator (malloc/free) on non-WASM
		// targets. The C CLI below links this library and #includes uchardet.h,
		// dogfooding the FFI boundary.
		const lib_mod = b.createModule(.{
			.root_source_file = b.path("src/lib.zig"),
			.target = target,
			.optimize = optimize,
		});
		lib_mod.link_libc = true;
		const lib = b.addLibrary(.{
			.name = "chardetz",
			.linkage = .static,
			.root_module = lib_mod,
		});
		lib.installHeader(b.path("include/uchardet.h"), "uchardet.h");
		b.installArtifact(lib);

		// ── C CLI: dogfoods the FFI. Pure C, #includes uchardet.h, links the lib. ──
		const cli_mod = b.createModule(.{
			.target = target,
			.optimize = optimize,
		});
		cli_mod.link_libc = true;
		cli_mod.addCSourceFile(.{ .file = b.path("cli/main.c"), .flags = &.{"-std=c11"} });
		cli_mod.addIncludePath(b.path("include"));
		cli_mod.linkLibrary(lib);
		const cli = b.addExecutable(.{ .name = "chardetz", .root_module = cli_mod });
		b.installArtifact(cli);

		const run_cli = b.addRunArtifact(cli);
		if (b.args) |args| run_cli.addArgs(args);
		b.step("run", "Run the chardetz CLI").dependOn(&run_cli.step);
	}

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
	// link_libc: the core module now re-exports the FFI (src/ffi.zig), whose
	// non-WASM handle allocator is std.heap.c_allocator — so the test binary
	// must link libc to satisfy malloc/free.
	const test_mod = b.createModule(.{
		.root_source_file = b.path("tests/all.zig"),
		.target = target,
		.optimize = optimize,
		.imports = &.{
			.{ .name = "chardetz", .module = core_mod },
			.{ .name = "gen_tables", .module = gen_mod },
		},
	});
	test_mod.link_libc = true;
	const tests = b.addTest(.{ .root_module = test_mod });
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
