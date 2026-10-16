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

/// Exact corpus size, defined once in build.zig (seed_corpus_files).
const expected_corpus_files = options.expected_corpus_files;
const max_file_bytes = 16 << 20;
/// Upstream's own test runner reads in 64 KiB chunks.
const upstream_chunk = 65536;
/// Every file is also fed in these chunk sizes, because probers carry state
/// across `handle_data` calls. Ledger keys for these runs are "path@N".
const extra_chunks = [_]usize{ 1, 7, 4096 };

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
        try report.record(gpa, &ledger, path, answer, try detectChunked(bytes, upstream_chunk));
        for (extra_chunks) |chunk| {
            const key = try std.fmt.allocPrint(arena, "{s}@{d}", .{ path, chunk });
            const chunked = try oracle.detect(arena, bytes, chunk);
            try report.record(gpa, &ledger, key, chunked, try detectChunked(bytes, chunk));
        }
    }

    try std.testing.expectEqual(@as(usize, expected_corpus_files), files);
    for (label_mismatches.items) |m| std.debug.print("label mismatch: {s}\n", .{m});
    try std.testing.expectEqual(@as(usize, 0), label_mismatches.items.len);
    for (report.divergences.items) |d| std.debug.print("divergence: {s}: oracle {s}, chardetz {s}\n", .{ d.file, d.oracle, d.candidate });
    const unused = try report.unusedFences(gpa, &ledger);
    defer gpa.free(unused);
    for (unused) |f| std.debug.print("stale fence: {s}\n", .{f.file});
    try std.testing.expect(report.passed(&ledger));
    try std.testing.expectEqual(@as(usize, 0), report.pending);
    try std.testing.expectEqual(files * (1 + extra_chunks.len), report.agree + report.pending + report.fenced);
}

/// Runs the Zig detector the way the oracle runs: same chunking, then
/// data_end. Returns uchardet's charset name (static storage).
fn detectChunked(bytes: []const u8, chunk_len: usize) ![]const u8 {
    var d: chardetz.Detector = .init(gpa);
    defer d.deinit();
    var rest = bytes;
    while (rest.len > 0) {
        const n = @min(rest.len, chunk_len);
        try d.handleData(rest[0..n]);
        rest = rest[n..];
    }
    d.dataEnd();
    return d.charset();
}

/// Seeded so every run (and every failure report) is reproducible.
const fuzz_seed: u64 = 0x63686172_6465747a; // "chardetz"
const fuzz_cases = 20_000;
const fuzz_chunks = [_]usize{ 1, 2, 3, 7, 64, 4096, 65536 };

/// Builds one adversarial input: random bytes over a few alphabets, a corpus
/// file with byte flips, two files spliced, or a random slice of one file.
fn fuzzInput(r: std.Random, arena: std.mem.Allocator, corpus: []const []const u8) ![]u8 {
    switch (r.uintLessThan(u8, 4)) {
        0 => {
            const out = try arena.alloc(u8, r.uintLessThan(usize, 4097));
            const alphabet = r.uintLessThan(u8, 3);
            for (out) |*b| b.* = switch (alphabet) {
                0 => r.int(u8),
                1 => 0x80 | r.int(u8), // high bytes only
                else => if (r.boolean()) 0x20 + r.uintLessThan(u8, 0x5f) else 0x80 | r.int(u8),
            };
            return out;
        },
        1 => {
            const src = corpus[r.uintLessThan(usize, corpus.len)];
            const out = try arena.dupe(u8, src);
            if (out.len == 0) return out;
            for (0..1 + r.uintLessThan(usize, 32)) |_| out[r.uintLessThan(usize, out.len)] = r.int(u8);
            return out;
        },
        2 => {
            const a = corpus[r.uintLessThan(usize, corpus.len)];
            const b = corpus[r.uintLessThan(usize, corpus.len)];
            const a_end = r.uintAtMost(usize, a.len);
            const b_start = r.uintAtMost(usize, b.len);
            return std.mem.concat(arena, u8, &.{ a[0..a_end], b[b_start..] });
        },
        else => {
            const src = corpus[r.uintLessThan(usize, corpus.len)];
            const lo = r.uintAtMost(usize, src.len);
            const hi = lo + r.uintAtMost(usize, src.len - lo);
            return arena.dupe(u8, src[lo..hi]);
        },
    }
}

test "randomized differential: generated, mutated and spliced inputs in random chunks" {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    var corpus_dir = try std.Io.Dir.cwd().openDir(io, options.corpus_dir, .{ .iterate = true });
    defer corpus_dir.close(io);
    var walker = try corpus_dir.walk(gpa);
    defer walker.deinit();
    var corpus: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or std.mem.indexOfScalar(u8, entry.path, '/') == null) continue;
        try corpus.append(arena, try entry.dir.readFileAlloc(io, entry.basename, arena, .limited(max_file_bytes)));
    }
    try std.testing.expectEqual(@as(usize, expected_corpus_files), corpus.items.len);

    var case_arena = std.heap.ArenaAllocator.init(gpa);
    defer case_arena.deinit();
    var prng = std.Random.DefaultPrng.init(fuzz_seed);
    const r = prng.random();
    var mismatches: usize = 0;
    for (0..fuzz_cases) |case| {
        _ = case_arena.reset(.retain_capacity);
        const ca = case_arena.allocator();
        const input = try fuzzInput(r, ca, corpus.items);
        const chunk = if (r.boolean()) fuzz_chunks[r.uintLessThan(usize, fuzz_chunks.len)] else 1 + r.uintLessThan(usize, @max(input.len, 1));
        const want = try oracle.detect(ca, input, chunk);
        const got = try detectChunked(input, chunk);
        if (!std.mem.eql(u8, want, got)) {
            mismatches += 1;
            if (mismatches <= 10) std.debug.print("fuzz case {d} (len {d}, chunk {d}): oracle {s}, chardetz {s}\n", .{ case, input.len, chunk, want, got });
        }
    }
    try std.testing.expectEqual(@as(usize, 0), mismatches);
}
