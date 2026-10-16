const std = @import("std");
const gen_manifest = @import("tools/gen_tables/manifest.zig");

/// Corpus files (test/<language>/<file>) in the pinned uchardetz tree, counted
/// with `find test -mindepth 2 -type f`. Both corpus tests require exactly this
/// many, so a wrong corpus path or a changed pin cannot pass vacuously.
const seed_corpus_files = 59;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Optimization mode (default: ReleaseFast)",
    ) orelse .ReleaseFast;

    const test_step = b.step("test", "Run all Zig unit tests");

    // -- Core library (pure Zig; the C FFI exports land here in M5) --
    const lib = b.addLibrary(.{
        .name = "chardetz",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lib);

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
        addOracleGate(b, test_step, src_root, target, optimize);
        addTableDifferential(b, test_step, gen_exe, src_root, target, optimize);
    } else {
        const fail = b.addFail("uchardetz source unknown: pass -Duchardet-src=PATH or run inside `nix develop`");
        gen_step.dependOn(&fail.step);
        gen_check_step.dependOn(&fail.step);
    }

    // -- Table generator tests (pure translation core) --
    for ([_][]const u8{ "tools/gen_tables/translate_test.zig", "tools/gen_tables/manifest_test.zig", "src/tables/types.zig", "src/tables/tables_test.zig", "tests/oracle/differential_test.zig", "src/root.zig" }) |path| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
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

/// Differential oracle gate: links the original C++ detector (test time only;
/// chardetz itself never depends on C++) and runs the seed corpus through it
/// and through the Zig core.
fn addOracleGate(b: *std.Build, test_step: *std.Build.Step, src_root: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const oracle_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        // Upstream relies on out-of-range enum values (valid C++), which
        // Zig's C sanitizer flags; uchardetz disables it for the same reason.
        .sanitize_c = .off,
    });
    oracle_mod.addCSourceFiles(.{
        .root = .{ .cwd_relative = src_root },
        .files = &oracle_sources,
        .flags = &.{"-DVERSION=\"0.0.6\""},
    });
    const oracle_lib = b.addLibrary(.{ .name = "uchardet-oracle", .linkage = .static, .root_module = oracle_mod });

    const options = b.addOptions();
    options.addOption([]const u8, "corpus_dir", b.fmt("{s}/test", .{src_root}));
    options.addOption([]const u8, "ledger_path", b.pathFromRoot("tests/expected_divergences.json"));
    options.addOption(usize, "expected_corpus_files", seed_corpus_files);

    const chardetz_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
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
    b.step("oracle-gate", "Run the differential oracle gate over the seed corpus").dependOn(&run_gate.step);
    test_step.dependOn(&run_gate.step);

    // The C++ uchardet CLI (test-only, never installed) for CLI-vs-CLI parity.
    // Until the chardetz CLI exists (M5), the parity harness is exercised by
    // its self-test against this oracle and deliberately wrong candidates.
    const oracle_cli_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libcpp = true });
    oracle_cli_mod.addCSourceFiles(.{
        .root = .{ .cwd_relative = src_root },
        .files = &.{ "src/tools/uchardet.cpp", "src/tools/i18n.cpp" },
        .flags = &.{"-DVERSION=\"0.0.6\""},
    });
    oracle_cli_mod.addIncludePath(.{ .cwd_relative = b.fmt("{s}/src", .{src_root}) });
    oracle_cli_mod.linkLibrary(oracle_lib);
    const oracle_cli = b.addExecutable(.{ .name = "uchardet-oracle", .root_module = oracle_cli_mod });
    const parity = b.addSystemCommand(&.{ "bash", "tests/cli/parity_test" });
    parity.addArtifactArg(oracle_cli);
    parity.addArg(b.fmt("{s}/test", .{src_root}));
    parity.addArg(b.fmt("{d}", .{seed_corpus_files}));
    parity.addFileInput(b.path("tests/cli/parity"));
    parity.addFileInput(b.path("tests/cli/parity_test"));
    parity.expectExitCode(0);
    b.step("cli-parity", "Self-test the CLI-vs-CLI parity harness against the C++ oracle CLI").dependOn(&parity.step);
    test_step.dependOn(&parity.step);
}

/// Table-level differential: gen-tables writes one C++ shim per upstream table
/// file that `#include`s it verbatim, so the C++ compiler evaluates every
/// table. Those files are compiled only through their shims (never twice); the
/// remaining upstream sources resolve any symbols they need. A Zig test then
/// compares every declaration in src/tables with the compiler's bytes.
fn addTableDifferential(b: *std.Build, test_step: *std.Build.Step, gen_exe: *std.Build.Step.Compile, src_root: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
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

    const chardetz_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
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
