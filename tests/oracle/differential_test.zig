const std = @import("std");
const differential = @import("differential.zig");

const gpa = std.testing.allocator;

const fence_json =
    \\[
    \\  {"file": "ja/sjis.txt", "oracle": "SHIFT_JIS", "candidate": "CP932", "reason": "documented tie"}
    \\]
;

test "classifies agreement, divergence and pending candidates" {
    var ledger = try differential.Ledger.parse(gpa, "[]");
    defer ledger.deinit();
    var report: differential.Report = .{};
    defer report.deinit(gpa);

    try report.record(gpa, &ledger, "fr/utf-8.txt", "UTF-8", "UTF-8");
    try report.record(gpa, &ledger, "fr/windows-1252.txt", "WINDOWS-1252", "ISO-8859-1");
    try report.record(gpa, &ledger, "ja/euc-jp.txt", "EUC-JP", null);

    try std.testing.expectEqual(@as(usize, 1), report.agree);
    try std.testing.expectEqual(@as(usize, 1), report.pending);
    try std.testing.expectEqual(@as(usize, 1), report.divergences.items.len);
    try std.testing.expectEqualStrings("fr/windows-1252.txt", report.divergences.items[0].file);
    try std.testing.expect(!report.passed(&ledger));
}

test "comparison is exact, including case" {
    var ledger = try differential.Ledger.parse(gpa, "[]");
    defer ledger.deinit();
    var report: differential.Report = .{};
    defer report.deinit(gpa);
    try report.record(gpa, &ledger, "x", "UTF-8", "utf-8");
    try std.testing.expectEqual(@as(usize, 1), report.divergences.items.len);
}

test "a fence covers only its exact file, oracle and candidate triple" {
    var ledger = try differential.Ledger.parse(gpa, fence_json);
    defer ledger.deinit();
    var report: differential.Report = .{};
    defer report.deinit(gpa);

    try report.record(gpa, &ledger, "ja/sjis.txt", "SHIFT_JIS", "CP932");
    try report.record(gpa, &ledger, "ja/sjis.txt", "SHIFT_JIS", "EUC-JP");
    try std.testing.expectEqual(@as(usize, 1), report.fenced);
    try std.testing.expectEqual(@as(usize, 1), report.divergences.items.len);
    try std.testing.expect(!report.passed(&ledger));
}

test "a fence that matched nothing fails the run" {
    var ledger = try differential.Ledger.parse(gpa, fence_json);
    defer ledger.deinit();
    var report: differential.Report = .{};
    defer report.deinit(gpa);
    try report.record(gpa, &ledger, "fr/utf-8.txt", "UTF-8", "UTF-8");
    try std.testing.expect(!report.passed(&ledger));
    const unused = try report.unusedFences(gpa, &ledger);
    defer gpa.free(unused);
    try std.testing.expectEqual(@as(usize, 1), unused.len);
}

test "clean run with all fences used passes" {
    var ledger = try differential.Ledger.parse(gpa, fence_json);
    defer ledger.deinit();
    var report: differential.Report = .{};
    defer report.deinit(gpa);
    try report.record(gpa, &ledger, "ja/sjis.txt", "SHIFT_JIS", "CP932");
    try report.record(gpa, &ledger, "fr/utf-8.txt", "UTF-8", "UTF-8");
    try std.testing.expect(report.passed(&ledger));
}

test "ledger entries require a non-empty reason and known fields" {
    try std.testing.expectError(error.BadLedger, differential.Ledger.parse(gpa,
        \\[{"file": "a", "oracle": "X", "candidate": "Y", "reason": ""}]
    ));
    try std.testing.expectError(error.BadLedger, differential.Ledger.parse(gpa,
        \\[{"file": "a", "oracle": "X", "candidate": "Y"}]
    ));
    try std.testing.expectError(error.BadLedger, differential.Ledger.parse(gpa, "{}"));
}

test "expected label comes from the corpus filename" {
    try std.testing.expectEqualStrings("utf-16", differential.labelFromPath("fr/utf-16.be"));
    try std.testing.expectEqualStrings("iso-8859-1", differential.labelFromPath("de/iso-8859-1.txt"));
    try std.testing.expectEqualStrings("ascii", differential.labelFromPath("ascii.txt"));
}
