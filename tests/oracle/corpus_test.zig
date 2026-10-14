//! Differential oracle gate over the upstream seed corpus. For every corpus
//! file: the C++ oracle must agree with the filename label (upstream's own
//! ground truth), and the Zig candidate must agree with the oracle, be pending,
//! or match a fence in tests/expected_divergences.json.
const std = @import("std");
const options = @import("oracle_options");
const oracle = @import("oracle.zig");
const differential = @import("differential.zig");
const chardetz = @import("chardetz");

const gpa = std.testing.allocator;
const io = std.testing.io;

/// Corpus files (test/<language>/<file>) at the pinned revision, counted with
/// `find test -mindepth 2 -type f`. Any other count means the corpus path or
/// pin changed, and a smaller one would let the gate pass vacuously.
const expected_corpus_files = 59;
const max_file_bytes = 16 << 20;
/// Upstream's own test runner reads in 64 KiB chunks.
const upstream_chunk = 65536;

test "differential oracle gate over the seed corpus" {
    const ledger_json = try std.Io.Dir.cwd().readFileAlloc(io, options.ledger_path, gpa, .limited(max_file_bytes));
    defer gpa.free(ledger_json);
    var ledger = try differential.Ledger.parse(gpa, ledger_json);
    defer ledger.deinit();

    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var corpus = try std.Io.Dir.cwd().openDir(io, options.corpus_dir, .{ .iterate = true });
    defer corpus.close(io);
    var walker = try corpus.walk(gpa);
    defer walker.deinit();

    var report: differential.Report = .{};
    defer report.deinit(gpa);
    var label_mismatches: std.ArrayList([]const u8) = .empty;
    var files: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.indexOfScalar(u8, entry.path, '/') == null) continue; // runner sources live at top level
        const path = try arena.dupe(u8, entry.path);
        const bytes = try entry.dir.readFileAlloc(io, entry.basename, arena, .limited(max_file_bytes));
        files += 1;

        const answer = try oracle.detect(arena, bytes, upstream_chunk);
        const lowered = try std.ascii.allocLowerString(arena, answer);
        if (!std.mem.eql(u8, lowered, differential.labelFromPath(path))) {
            try label_mismatches.append(arena, try std.fmt.allocPrint(arena, "{s}: oracle says {s}", .{ path, answer }));
        }
        try report.record(gpa, &ledger, path, answer, chardetz.detectCharset(bytes));
    }

    try std.testing.expectEqual(@as(usize, expected_corpus_files), files);
    for (label_mismatches.items) |m| std.debug.print("label mismatch: {s}\n", .{m});
    try std.testing.expectEqual(@as(usize, 0), label_mismatches.items.len);
    for (report.divergences.items) |d| std.debug.print("divergence: {s}: oracle {s}, chardetz {s}\n", .{ d.file, d.oracle, d.candidate });
    const unused = try report.unusedFences(gpa, &ledger);
    defer gpa.free(unused);
    for (unused) |f| std.debug.print("stale fence: {s}\n", .{f.file});
    try std.testing.expect(report.passed(&ledger));
    try std.testing.expectEqual(files, report.agree + report.pending + report.fenced);
}
