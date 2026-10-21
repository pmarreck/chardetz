const std = @import("std");
const gen_manifest = @import("tools/gen_tables/manifest.zig");

/// Corpus files (test/<language>/<file>) in the pinned uchardetz tree, counted
/// with `find test -mindepth 2 -type f`. Both corpus tests require exactly this
/// many, so a wrong corpus path or a changed pin cannot pass vacuously.
const seed_corpus_files = 59;

const version = "0.2.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Optimization mode (default: ReleaseFast)",
    ) orelse .ReleaseFast;
    const fuzz_seed = b.option(u64, "fuzz-seed", "Seed for the randomized differential") orelse 0x63686172_6465747a;
    const fuzz_cases = b.option(usize, "fuzz-cases", "Cases in the randomized differential") orelse 20_000;

    const test_step = b.step("test", "Run every test (unit, generator, oracle gates, C ABI, CLI)");

    // -- The Zig module downstream projects import (pure, no I/O) --
    const chardetz_mod = b.addModule("chardetz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // -- C ABI: uchardet-compatible exports plus the one-shot WASM entry points --
    const ffi_mod = b.createModule(.{
        .root_source_file = b.path("src/ffi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = !target.result.cpu.arch.isWasm(),
    });

    if (target.result.cpu.arch.isWasm()) {
        // wasm32-freestanding: no libc, no entry point, exports only.
        const wasm = b.addExecutable(.{ .name = "chardetz", .root_module = ffi_mod });
        wasm.entry = .disabled;
        wasm.rdynamic = true;
        b.installArtifact(wasm);
        return;
    }

    const lib = b.addLibrary(.{ .name = "chardetz", .linkage = .static, .root_module = ffi_mod });
    b.installArtifact(lib);
    b.installFile("include/uchardet.h", "include/uchardet.h");

    // -- C CLI: reaches the detector only through include/uchardet.h --
    const cli = addCProgram(b, "chardetz", "cli/main.c", lib, target, optimize);
    b.installArtifact(cli);
    const run_cli = b.addRunArtifact(cli);
    if (b.args) |args| run_cli.addArgs(args);
    b.step("run", "Run the chardetz CLI").dependOn(&run_cli.step);

    // -- C ABI contract test --
    const ffi_test = addCProgram(b, "ffi-test", "tests/ffi/ffi_test.c", lib, target, optimize);
    const run_ffi_test = b.addRunArtifact(ffi_test);
    run_ffi_test.expectExitCode(0);
    test_step.dependOn(&run_ffi_test.step);

    // Pinned uchardetz checkout: translation source, oracle and seed corpus.
    // The flake dev shell and checks export CHARDETZ_UCHARDET_SRC.
    const uchardet_src = b.option([]const u8, "uchardet-src", "Path to the pinned uchardetz source tree") orelse
        b.graph.environ_map.get("CHARDETZ_UCHARDET_SRC");

    // -- Table generator (build-host tool) --
    const gen_exe = b.addExecutable(.{
        .name = "gen-tables",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/gen_tables/main.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    });
    const gen_step = b.step("gen-tables", "Regenerate src/tables from the pinned uchardetz source");
    const gen_check_step = b.step("gen-tables-check", "Fail if committed src/tables differ from regeneration");
    if (uchardet_src) |src_root| {
        for ([_]*std.Build.Step{ gen_step, gen_check_step }, [_]bool{ false, true }) |step, check| {
            const run = b.addRunArtifact(gen_exe);
            run.addFileArg(b.path("tools/gen_tables/manifest.txt"));
            run.addArg(src_root);
            run.addArg(b.pathFromRoot("src/tables"));
            if (check) run.addArg("--check");
            run.has_side_effects = true;
            step.dependOn(&run.step);
        }
        test_step.dependOn(gen_check_step);
        const oracle_lib = addOracleLibrary(b, src_root, target, optimize);
        addOracleGate(b, test_step, oracle_lib, chardetz_mod, src_root, fuzz_seed, fuzz_cases, target, optimize);
        addCliParity(b, test_step, oracle_lib, cli, src_root, target, optimize);
        addTableDifferential(b, test_step, gen_exe, chardetz_mod, src_root, target, optimize);
        addBench(b, oracle_lib, chardetz_mod, target, optimize);
    } else {
        const fail = b.addFail("uchardetz source unknown: pass -Duchardet-src=PATH or run inside `nix develop`");
        gen_step.dependOn(&fail.step);
        gen_check_step.dependOn(&fail.step);
        test_step.dependOn(&fail.step);
    }

    // -- Pure unit tests --
    for ([_][]const u8{
        "tools/gen_tables/translate_test.zig",
        "tools/gen_tables/manifest_test.zig",
        "src/tables/types.zig",
        "src/tables/tables_test.zig",
        "tests/oracle/differential_test.zig",
        "src/root.zig",
    }) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
    // Tests written against the public module (PRINTABLE-BINARY extension).
    for ([_][]const u8{"tests/pb_tests.zig"}) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "chardetz", .module = chardetz_mod }},
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}

fn addCProgram(b: *std.Build, name: []const u8, source: []const u8, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    mod.addCSourceFile(.{
        .file = b.path(source),
        .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", b.fmt("-DCHARDETZ_VERSION=\"{s}\"", .{version}) },
    });
    mod.addIncludePath(b.path("include"));
    mod.linkLibrary(lib);
    return b.addExecutable(.{ .name = name, .root_module = mod });
}

/// Upstream uchardet C++ sources compiled for the test-only oracle library,
/// as listed in uchardetz's own build.zig at the pinned revision.
const oracle_sources = [_][]const u8{
    "src/CharDistribution.cpp",              "src/JpCntx.cpp",
    "src/LangModels/LangArabicModel.cpp",    "src/LangModels/LangBulgarianModel.cpp",
    "src/LangModels/LangDanishModel.cpp",    "src/LangModels/LangEsperantoModel.cpp",
    "src/LangModels/LangFrenchModel.cpp",    "src/LangModels/LangGermanModel.cpp",
    "src/LangModels/LangGreekModel.cpp",     "src/LangModels/LangHebrewModel.cpp",
    "src/LangModels/LangHungarianModel.cpp", "src/LangModels/LangRussianModel.cpp",
    "src/LangModels/LangSpanishModel.cpp",   "src/LangModels/LangThaiModel.cpp",
    "src/LangModels/LangTurkishModel.cpp",   "src/LangModels/LangVietnameseModel.cpp",
    "src/nsHebrewProber.cpp",                "src/nsCharSetProber.cpp",
    "src/nsBig5Prober.cpp",                  "src/nsEUCJPProber.cpp",
    "src/nsEUCKRProber.cpp",                 "src/nsEUCTWProber.cpp",
    "src/nsEscCharsetProber.cpp",            "src/nsEscSM.cpp",
    "src/nsGB2312Prober.cpp",                "src/nsMBCSGroupProber.cpp",
    "src/nsMBCSSM.cpp",                      "src/nsSBCSGroupProber.cpp",
    "src/nsSBCharSetProber.cpp",             "src/nsSJISProber.cpp",
    "src/nsUTF8Prober.cpp",                  "src/nsLatin1Prober.cpp",
    "src/nsUniversalDetector.cpp",           "src/uchardet.cpp",
};

/// The original C++ detector as a static library. Test and benchmark time
/// only: chardetz itself never depends on C++.
fn addOracleLibrary(b: *std.Build, src_root: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        // Upstream relies on out-of-range enum values (valid C++), which
        // Zig's C sanitizer flags; uchardetz disables it for the same reason.
        .sanitize_c = .off,
    });
    mod.addCSourceFiles(.{
        .root = .{ .cwd_relative = src_root },
        .files = &oracle_sources,
        .flags = &.{"-DVERSION=\"0.0.6\""},
    });
    return b.addLibrary(.{ .name = "uchardet-oracle", .linkage = .static, .root_module = mod });
}

/// Differential oracle gate: the seed corpus (whole and chunked) and a seeded
/// randomized campaign, each run through the C++ oracle and the Zig core.
fn addOracleGate(b: *std.Build, test_step: *std.Build.Step, oracle_lib: *std.Build.Step.Compile, chardetz_mod: *std.Build.Module, src_root: []const u8, fuzz_seed: u64, fuzz_cases: usize, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const options = b.addOptions();
    options.addOption([]const u8, "corpus_dir", b.fmt("{s}/test", .{src_root}));
    options.addOption([]const u8, "ledger_path", b.pathFromRoot("tests/expected_divergences.json"));
    options.addOption(usize, "expected_corpus_files", seed_corpus_files);
    options.addOption(u64, "fuzz_seed", fuzz_seed);
    options.addOption(usize, "fuzz_cases", fuzz_cases);

    const gate_mod = b.createModule(.{
        .root_source_file = b.path("tests/oracle/corpus_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "oracle_options", .module = options.createModule() },
            .{ .name = "chardetz", .module = chardetz_mod },
        },
    });
    gate_mod.linkLibrary(oracle_lib);
    const gate = b.addTest(.{ .name = "oracle-gate", .root_module = gate_mod });
    const run_gate = b.addRunArtifact(gate);
    b.step("oracle-gate", "Run the differential oracle gate (corpus and randomized)").dependOn(&run_gate.step);
    test_step.dependOn(&run_gate.step);
}

/// CLI-vs-CLI parity: the C++ uchardet CLI (test-only, never installed) and the
/// chardetz CLI must print the same thing for every corpus file. The parity
/// harness is also self-tested against deliberately wrong candidates.
fn addCliParity(b: *std.Build, test_step: *std.Build.Step, oracle_lib: *std.Build.Step.Compile, cli: *std.Build.Step.Compile, src_root: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const oracle_cli_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libcpp = true });
    oracle_cli_mod.addCSourceFiles(.{
        .root = .{ .cwd_relative = src_root },
        .files = &.{ "src/tools/uchardet.cpp", "src/tools/i18n.cpp" },
        .flags = &.{"-DVERSION=\"0.0.6\""},
    });
    oracle_cli_mod.addIncludePath(.{ .cwd_relative = b.fmt("{s}/src", .{src_root}) });
    oracle_cli_mod.linkLibrary(oracle_lib);
    const oracle_cli = b.addExecutable(.{ .name = "uchardet-oracle", .root_module = oracle_cli_mod });
    const corpus = b.fmt("{s}/test", .{src_root});

    const self_test = b.addSystemCommand(&.{ "bash", "tests/cli/parity_test" });
    self_test.addArtifactArg(oracle_cli);
    self_test.addArg(corpus);
    self_test.addArg(b.fmt("{d}", .{seed_corpus_files}));
    self_test.addFileInput(b.path("tests/cli/parity"));
    self_test.addFileInput(b.path("tests/cli/parity_test"));
    self_test.expectExitCode(0);

    const parity = b.addSystemCommand(&.{ "bash", "tests/cli/parity" });
    parity.addArtifactArg(oracle_cli);
    parity.addArtifactArg(cli);
    parity.addArg(corpus);
    parity.addFileInput(b.path("tests/cli/parity"));
    parity.expectStdOutEqual(b.fmt("parity: {d} files, 0 mismatches\n", .{seed_corpus_files}));

    const step = b.step("cli-parity", "chardetz CLI vs the C++ uchardet CLI over the corpus");
    step.dependOn(&self_test.step);
    step.dependOn(&parity.step);
    test_step.dependOn(step);
}

/// Table-level differential: gen-tables writes one C++ shim per upstream table
/// file that `#include`s it verbatim, so the C++ compiler evaluates every
/// table. Those files are compiled only through their shims (never twice); the
/// remaining upstream sources resolve any symbols they need. A Zig test then
/// compares every declaration in src/tables with the compiler's bytes.
fn addTableDifferential(b: *std.Build, test_step: *std.Build.Step, gen_exe: *std.Build.Step.Compile, chardetz_mod: *std.Build.Module, src_root: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const manifest_path = "tools/gen_tables/manifest.txt";
    const text = b.build_root.handle.readFileAlloc(b.graph.io, manifest_path, b.allocator, .limited(1 << 20)) catch |e|
        std.debug.panic("reading {s}: {s}", .{ manifest_path, @errorName(e) });
    const m = gen_manifest.parse(b.allocator, text) catch |e|
        std.debug.panic("parsing {s}: {s}", .{ manifest_path, @errorName(e) });

    const shim_run = b.addRunArtifact(gen_exe);
    shim_run.addFileArg(b.path(manifest_path));
    shim_run.addArg(src_root);
    const shim_dir = shim_run.addOutputDirectoryArg("shims");
    shim_run.addArg("--shims");

    var shim_files: std.ArrayList([]const u8) = .empty;
    for (m.tables) |t| shim_files.append(b.allocator, b.fmt("shim_{s}.cpp", .{t.stem})) catch @panic("OOM");
    var other_sources: std.ArrayList([]const u8) = .empty;
    outer: for (oracle_sources) |src| {
        for (m.tables) |t| if (std.mem.eql(u8, t.source, src)) continue :outer;
        other_sources.append(b.allocator, src) catch @panic("OOM");
    }

    const lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .sanitize_c = .off,
    });
    lib_mod.addIncludePath(b.path("tests/oracle"));
    lib_mod.addCSourceFiles(.{
        .root = .{ .cwd_relative = src_root },
        .files = other_sources.items,
        .flags = &.{"-DVERSION=\"0.0.6\""},
    });
    lib_mod.addCSourceFiles(.{
        .root = shim_dir,
        .files = shim_files.items,
        // The .tab frequency tables expect nscore.h's typedefs to precede them.
        .flags = &.{ "-include", b.fmt("{s}/src/nscore.h", .{src_root}) },
    });
    const lib = b.addLibrary(.{ .name = "uchardet-table-oracle", .linkage = .static, .root_module = lib_mod });

    const diff_options = b.addOptions();
    diff_options.addOption(usize, "table_modules", m.tables.len);
    const diff_mod = b.createModule(.{
        .root_source_file = b.path("tests/oracle/tables_diff_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "chardetz", .module = chardetz_mod },
            .{ .name = "table_options", .module = diff_options.createModule() },
        },
    });
    diff_mod.linkLibrary(lib);
    const diff = b.addTest(.{ .name = "table-differential", .root_module = diff_mod });
    const run_diff = b.addRunArtifact(diff);
    b.step("table-differential", "Compare every generated table with the C++ compiler's evaluation").dependOn(&run_diff.step);
    test_step.dependOn(&run_diff.step);
}

/// `zig build bench` (driven by ./bm): scaling-ratio gate plus chardetz-vs-C++
/// throughput. ReleaseFast only; links the oracle for the comparison.
fn addBench(b: *std.Build, oracle_lib: *std.Build.Step.Compile, chardetz_mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const c_mod = b.createModule(.{ .root_source_file = b.path("bench/oracle_c.zig"), .target = target, .optimize = optimize });
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("bench/bench.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "chardetz", .module = chardetz_mod },
            .{ .name = "c", .module = c_mod },
        },
    });
    bench_mod.linkLibrary(oracle_lib);
    const bench_exe = b.addExecutable(.{ .name = "chardetz-bench", .root_module = bench_mod });
    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.has_side_effects = true;
    if (b.args) |args| run_bench.addArgs(args);
    b.step("bench", "Run the benchmark harness (chardetz vs the C++ original)").dependOn(&run_bench.step);
}
