const std = @import("std");

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
    } else {
        const fail = b.addFail("uchardetz source unknown: pass -Duchardet-src=PATH or run inside `nix develop`");
        gen_step.dependOn(&fail.step);
        gen_check_step.dependOn(&fail.step);
    }

    // -- Table generator tests (pure translation core) --
    for ([_][]const u8{ "tools/gen_tables/translate_test.zig", "tools/gen_tables/manifest_test.zig", "src/tables/types.zig", "src/tables/tables_test.zig", "tests/oracle/differential_test.zig" }) |path| {
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
}
