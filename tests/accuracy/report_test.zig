const std = @import("std");
const report = @import("report.zig");

const gpa = std.testing.allocator;

test "correct: case-insensitive membership; an empty answer is never correct" {
    const ok = [_][]const u8{ "ISO-8859-1", "WINDOWS-1252" };
    try std.testing.expect(report.correct("windows-1252", &ok));
    try std.testing.expect(report.correct("ISO-8859-1", &ok));
    try std.testing.expect(!report.correct("ISO-8859-15", &ok));
    try std.testing.expect(!report.correct("", &ok));
    try std.testing.expect(!report.correct("", &.{}));
}

fn row(id: []const u8, mode: report.Mode, encoding: []const u8, ok: []const []const u8, upstream: []const u8, chardetz: []const u8, fix: []const u8) report.Row {
    return .{ .id = id, .language = "xx", .encoding = encoding, .length = std.fs.path.basename(id), .fidelity = "exact", .mode = mode, .acceptable = ok, .upstream = upstream, .chardetz = chardetz, .fix = fix };
}

const koi = [_][]const u8{"KOI8-R"};
const utf16 = [_][]const u8{"UTF-16"};
const sample = [_]report.Row{
    row("rus/KOI8-R/16", .whole, "KOI8-R", &koi, "KOI8-R", "KOI8-R", ""),
    row("rus/KOI8-R/16", .bytewise, "KOI8-R", &koi, "KOI8-R", "KOI8-R", ""),
    row("rus/KOI8-R/16", .ascii_prefix, "KOI8-R", &koi, "ASCII", "KOI8-R", "revisable_ascii"),
    row("fra/UTF-16/16", .whole, "UTF-16", &utf16, "UTF-16", "UTF-16", ""),
    row("fra/UTF-16/16", .bytewise, "UTF-16", &utf16, "WINDOWS-1252", "UTF-16", "fixed_blocks"),
    row("fra/UTF-16/8", .whole, "UTF-16", &utf16, "", "", ""),
};

test "regressions are rows where chardetz is wrong and uchardet right" {
    const bad = [_]report.Row{
        row("a", .whole, "KOI8-R", &koi, "KOI8-R", "IBM866", "x"),
        row("b", .whole, "KOI8-R", &koi, "IBM866", "KOI8-R", "x"),
        row("c", .whole, "KOI8-R", &koi, "IBM866", "IBM855", "x"),
    };
    const r = try report.regressions(gpa, &bad);
    defer gpa.free(r);
    try std.testing.expectEqual(@as(usize, 1), r.len);
    try std.testing.expectEqualStrings("a", r[0].id);
}

test "ledger lists every difference, one tab-separated line each" {
    const text = try report.renderLedger(gpa, &sample);
    defer gpa.free(text);
    try std.testing.expectEqualStrings(
        "# feeding\tcase\tuchardet\tuchardet_correct\tchardetz\tchardetz_correct\tfix\n" ++
            "ascii-prefix\trus/KOI8-R/16\tASCII\tno\tKOI8-R\tyes\trevisable_ascii\n" ++
            "bytewise\tfra/UTF-16/16\tWINDOWS-1252\tno\tUTF-16\tyes\tfixed_blocks\n",
        text,
    );
}

test "summary counts per feeding mode" {
    const s = report.summarize(&sample, .whole);
    try std.testing.expectEqual(@as(usize, 3), s.cases);
    try std.testing.expectEqual(@as(usize, 2), s.chardetz_right);
    try std.testing.expectEqual(@as(usize, 2), s.upstream_right);
    try std.testing.expectEqual(@as(usize, 1), s.both_wrong);
    const p = report.summarize(&sample, .ascii_prefix);
    try std.testing.expectEqual(@as(usize, 1), p.chardetz_only);
    try std.testing.expectEqual(@as(usize, 0), p.upstream_only);
}

test "ratchet line round-trips through the rendered report" {
    const meta: report.Meta = .{ .udhr_rev = "u", .uchardet_rev = "c", .cases = 3, .normalized = 0, .lossy = 0 };
    const text = try report.renderReport(gpa, &sample, meta);
    defer gpa.free(text);
    const counts = report.parseRatchet(text).?;
    try std.testing.expectEqual(@as(usize, 2), counts.get(.whole));
    try std.testing.expectEqual(@as(usize, 2), counts.get(.bytewise));
    try std.testing.expectEqual(@as(usize, 1), counts.get(.ascii_prefix));
    try std.testing.expectEqual(@as(?report.Counts, null), report.parseRatchet("no marker here"));
}

test "report names every difference group and every both-wrong group" {
    const meta: report.Meta = .{ .udhr_rev = "u", .uchardet_rev = "c", .cases = 3, .normalized = 0, .lossy = 0 };
    const text = try report.renderReport(gpa, &sample, meta);
    defer gpa.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "| after 64 KiB of ASCII | KOI8-R | ASCII | KOI8-R | 1 | chardetz | `revisable_ascii` |") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "| 1-byte chunks | UTF-16 | WINDOWS-1252 | UTF-16 | 1 | chardetz | `fixed_blocks` |") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "| UTF-16 | (none) | 1 | 8 (1) |") != null);
}
