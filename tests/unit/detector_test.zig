// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Pins UniversalDetector dispatch: BOM detection, the BOM-less UTF-16 NUL
// heuristic, input classification, and the UTF-8 high-byte path. The
// differential gate (chardetz.detect vs uchardet over the corpus) is the
// authoritative oracle; these are fast white-box checks of the control flow.

const std = @import("std");
const cz = @import("chardetz");

fn detect(bytes: []const u8) []const u8 {
    return cz.detect(std.testing.allocator, bytes);
}

test "BOM: EF BB BF → UTF-8" {
    try std.testing.expectEqualStrings("UTF-8", detect("\xEF\xBB\xBFhello"));
}

test "BOM: FE FF → UTF-16 (big endian)" {
    try std.testing.expectEqualStrings("UTF-16", detect("\xFE\xFF\x00h\x00i"));
}

test "BOM: FF FE (not 00 00) → UTF-16 (little endian)" {
    try std.testing.expectEqualStrings("UTF-16", detect("\xFF\xFEh\x00i\x00"));
}

test "BOM: FF FE 00 00 → UTF-32 (LE)" {
    try std.testing.expectEqualStrings("UTF-32", detect("\xFF\xFE\x00\x00rest"));
}

test "BOM: 00 00 FE FF → UTF-32 (BE)" {
    try std.testing.expectEqualStrings("UTF-32", detect("\x00\x00\xFE\xFFrest"));
}

test "pure ASCII → ASCII" {
    try std.testing.expectEqualStrings("ASCII", detect("Hello, world! Just plain ASCII text."));
}

test "empty input → empty charset (no data)" {
    try std.testing.expectEqualStrings("", detect(""));
}

test "BOM-less UTF-16BE heuristic: NULs at even positions → UTF-16BE" {
    // "Hello" as UTF-16BE (no BOM): 00 48 00 65 00 6C 00 6C 00 6F → high byte
    // (even index) is 0x00 for every BMP code unit.
    const be = "\x00H\x00e\x00l\x00l\x00o";
    try std.testing.expectEqualStrings("UTF-16BE", detect(be));
}

test "BOM-less UTF-16LE heuristic: NULs at odd positions → UTF-16LE" {
    // "Hello" as UTF-16LE (no BOM): 48 00 65 00 6C 00 6C 00 6F 00.
    const le = "H\x00e\x00l\x00l\x00o\x00";
    try std.testing.expectEqualStrings("UTF-16LE", detect(le));
}

test "high-byte UTF-8 text → UTF-8 via the UTF8 prober" {
    // Several valid 2-byte sequences ('é' = C3 A9) interleaved with ASCII →
    // the UTF8 prober gains confidence and wins.
    const s = "caf\xC3\xA9 \xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9 text";
    try std.testing.expectEqualStrings("UTF-8", detect(s));
}

test "detector reset clears detected charset and prober state" {
    var det = cz.detector.UniversalDetector.init();
    det.handleData("\xEF\xBB\xBFhi");
    det.dataEnd();
    try std.testing.expectEqualStrings("UTF-8", det.getCharset());
    det.reset();
    try std.testing.expectEqualStrings("", det.getCharset());
    try std.testing.expectEqual(false, det.done);
    try std.testing.expectEqual(true, det.start);
}
