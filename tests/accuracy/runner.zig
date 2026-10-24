//! accuracy-runner: feeds every generated accuracy case to the C++ uchardet
//! and to chardetz (whole, one byte at a time, and after 64 KiB of ASCII),
//! attributes each difference to an accuracy fix, and then either checks the
//! committed report and ledger or writes fresh ones.
//!
//! Usage: accuracy-runner CORPUS_TAR_ZST REPORT LEDGER UDHR_REV UCHARDET_REV
//!            (--check | --write OUT_REPORT OUT_LEDGER [--allow-regression])
//!
//! Fails when chardetz is wrong on a case where uchardet is right, when a
//! check finds the committed files stale, or when a write would lower
//! chardetz's correct count in any feeding mode (unless --allow-regression).
const std = @import("std");
const cz = @import("chardetz");
const oracle = @import("oracle");
const report = @import("report.zig");
const archive = @import("archive");

const max_file_bytes = 16 << 20;
const max_archive_bytes = 64 << 20;
const block = 65536;

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.File.stderr().writer(io, &err_buf);
    const stderr = &err_w.interface;
    defer stderr.flush() catch {};

    const check = args.len == 7 and std.mem.eql(u8, args[6], "--check");
    const write = (args.len == 9 or args.len == 10) and std.mem.eql(u8, args[6], "--write");
    const allow_regression = args.len == 10 and std.mem.eql(u8, args[9], "--allow-regression");
    if (!check and !write) {
        try stderr.writeAll("usage: accuracy-runner CORPUS_TAR_ZST REPORT LEDGER UDHR_REV UCHARDET_REV (--check | --write OUT_REPORT OUT_LEDGER [--allow-regression])\n");
        return 2;
    }
    const cwd = std.Io.Dir.cwd();
    const corpus = try archive.unpack(arena, try cwd.readFileAlloc(io, args[1], arena, .limited(max_archive_bytes)));
    const member = struct {
        fn get(files: archive.Files, name: []const u8) error{MissingMember}![]const u8 {
            return files.get(name) orelse error.MissingMember;
        }
    }.get;

    const summary = try member(corpus, "summary.txt");
    const meta: report.Meta = .{
        .udhr_rev = args[4],
        .uchardet_rev = args[5],
        .cases = summaryValue(summary, "cases"),
        .normalized = summaryValue(summary, "normalized"),
        .lossy = summaryValue(summary, "lossy"),
    };
    const prefix = try member(corpus, "prefix.txt");
    const manifest = try member(corpus, "cases.tsv");

    var rows: std.ArrayList(report.Row) = .empty;
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var cols = std.mem.splitScalar(u8, line, '\t');
        const id = cols.next().?;
        const language = cols.next().?;
        const encoding = cols.next().?;
        const length = cols.next().?;
        const ok = try splitList(arena, cols.next().?);
        const prefixed_ok = cols.next().?;
        const fidelity = cols.next().?;
        const file = try std.fmt.allocPrint(arena, "{s}.bin", .{id});
        const bytes = try member(corpus, file);
        const base: report.Row = .{ .id = id, .language = language, .encoding = encoding, .length = length, .fidelity = fidelity, .mode = .whole, .acceptable = ok, .upstream = "", .chardetz = "", .fix = "" };

        try rows.append(arena, try run(arena, base, .whole, bytes, @max(bytes.len, 1)));
        try rows.append(arena, try run(arena, base, .bytewise, bytes, 1));
        if (!std.mem.eql(u8, prefixed_ok, "-")) {
            var p = base;
            p.acceptable = try splitList(arena, prefixed_ok);
            const joined = try std.mem.concat(arena, u8, &.{ prefix, bytes });
            try rows.append(arena, try run(arena, p, .ascii_prefix, joined, block));
        }
    }
    if (rows.items.len == 0) {
        try stderr.writeAll("accuracy-runner: the corpus has no cases\n");
        return 1;
    }

    const regs = try report.regressions(arena, rows.items);
    for (regs[0..@min(regs.len, 20)]) |r| try stderr.print("REGRESSION {s} {s}: uchardet {s} (right), chardetz {s} (wrong)\n", .{ r.mode.slug(), r.id, r.upstream, r.chardetz });
    if (regs.len > 0) {
        try stderr.print("accuracy-runner: chardetz is wrong where uchardet is right in {d} case(s)\n", .{regs.len});
        return 1;
    }

    const text = try report.renderReport(arena, rows.items, meta);
    const ledger = try report.renderLedger(arena, rows.items);
    const committed = cwd.readFileAlloc(io, args[2], arena, .limited(max_file_bytes)) catch |e| switch (e) {
        error.FileNotFound => "",
        else => return e,
    };
    const committed_ledger = cwd.readFileAlloc(io, args[3], arena, .limited(max_file_bytes)) catch |e| switch (e) {
        error.FileNotFound => "",
        else => return e,
    };

    if (check) {
        var stale = false;
        for ([_][]const u8{ args[2], args[3] }, [_][]const u8{ committed, committed_ledger }, [_][]const u8{ text, ledger }) |path, old, new| {
            if (std.mem.eql(u8, old, new)) continue;
            stale = true;
            try stderr.print("accuracy-runner: {s} is stale (first difference at line {d}); review and run `zig build accuracy-report`\n", .{ path, firstDifferentLine(old, new) });
        }
        return if (stale) 1 else 0;
    }

    if (report.parseRatchet(committed)) |old| {
        const new = report.parseRatchet(text).?;
        var lowered = false;
        inline for (std.meta.fields(report.Mode)) |f| {
            const m: report.Mode = @enumFromInt(f.value);
            if (new.get(m) < old.get(m)) {
                lowered = true;
                try stderr.print("accuracy-runner: chardetz right in {s}: {d}, was {d}\n", .{ m.slug(), new.get(m), old.get(m) });
            }
        }
        if (lowered and !allow_regression) {
            try stderr.writeAll("accuracy-runner: refusing to lower the recorded accuracy; pass -Daccuracy-allow-regression=true to accept\n");
            return 1;
        }
    }
    try cwd.writeFile(io, .{ .sub_path = args[7], .data = text });
    try cwd.writeFile(io, .{ .sub_path = args[8], .data = ledger });
    return 0;
}

/// One row: both detectors' answers in one feeding mode, plus the fix that
/// explains a difference.
fn run(arena: std.mem.Allocator, base: report.Row, mode: report.Mode, input: []const u8, chunk: usize) !report.Row {
    var r = base;
    r.mode = mode;
    r.upstream = try oracle.detect(arena, input, chunk);
    r.chardetz = try detectWith(cz.Detector, arena, input, chunk);
    if (r.differs()) r.fix = try attribute(arena, input, chunk, r.chardetz);
    return r;
}

fn detectWith(comptime D: type, gpa: std.mem.Allocator, input: []const u8, chunk: usize) ![]const u8 {
    var d: D = .init(gpa);
    defer d.deinit();
    var rest = input;
    while (rest.len > 0) {
        const n = @min(rest.len, chunk);
        try d.handleData(rest[0..n]);
        rest = rest[n..];
    }
    d.dataEnd();
    return d.charset();
}

/// The single fix whose effect alone produces chardetz's answer, or the
/// combination "a+b" when no single fix does.
fn attribute(arena: std.mem.Allocator, input: []const u8, chunk: usize, answer: []const u8) ![]const u8 {
    const fields = std.meta.fields(cz.Fixes);
    var names: std.ArrayList(u8) = .empty;
    inline for (fields) |f| {
        const only = comptime blk: {
            var x = cz.Fixes.none;
            @field(x, f.name) = true;
            break :blk x;
        };
        const got = try detectWith(cz.DetectorWith(only), arena, input, chunk);
        if (std.mem.eql(u8, got, answer)) {
            if (names.items.len > 0) try names.appendSlice(arena, " or ");
            try names.appendSlice(arena, f.name);
        }
    }
    if (names.items.len > 0) return names.items;
    inline for (fields, 0..) |f, i| {
        if (i > 0) try names.append(arena, '+');
        try names.appendSlice(arena, f.name);
    }
    return names.items;
}

fn splitList(arena: std.mem.Allocator, s: []const u8) ![]const []const u8 {
    if (std.mem.eql(u8, s, "-")) return &.{};
    var out: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, s, ',');
    while (it.next()) |n| try out.append(arena, n);
    return out.items;
}

fn summaryValue(summary: []const u8, key: []const u8) usize {
    var lines = std.mem.splitScalar(u8, summary, '\n');
    while (lines.next()) |line| {
        var words = std.mem.tokenizeScalar(u8, line, ' ');
        const k = words.next() orelse continue;
        if (std.mem.eql(u8, k, key)) return std.fmt.parseInt(usize, words.next() orelse "0", 10) catch 0;
    }
    return 0;
}

fn firstDifferentLine(a: []const u8, b: []const u8) usize {
    var line: usize = 1;
    for (a[0..@min(a.len, b.len)], b[0..@min(a.len, b.len)]) |x, y| {
        if (x != y) return line;
        if (x == '\n') line += 1;
    }
    return line;
}
