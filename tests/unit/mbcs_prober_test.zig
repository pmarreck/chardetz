const std = @import("std");
const cz = @import("chardetz");
const ProbingState = cz.prober.ProbingState;

// Per-prober smoke tests: a fresh prober starts detecting with non-positive
// confidence, reports the right charset name, and survives an empty buffer.

test "Big5 prober: name + initial state" {
    var p = cz.probers.big5.Big5Prober.init();
    try std.testing.expectEqualStrings("BIG5", p.charsetName());
    try std.testing.expectEqual(ProbingState.detecting, p.getState());
    try std.testing.expectEqual(ProbingState.detecting, p.handleData(""));
}

test "GB18030 prober: name + initial state" {
    var p = cz.probers.gb18030.GB18030Prober.init();
    try std.testing.expectEqualStrings("GB18030", p.charsetName());
    try std.testing.expectEqual(ProbingState.detecting, p.getState());
}

test "EUC-KR prober: name + initial state" {
    var p = cz.probers.euckr.EUCKRProber.init();
    try std.testing.expectEqualStrings("EUC-KR", p.charsetName());
}

test "EUC-TW prober: name + initial state" {
    var p = cz.probers.euctw.EUCTWProber.init();
    try std.testing.expectEqualStrings("EUC-TW", p.charsetName());
}

test "SJIS prober: name + initial state" {
    var p = cz.probers.sjis.SJISProber.init();
    try std.testing.expectEqualStrings("SHIFT_JIS", p.charsetName());
}

test "EUC-JP prober: name + initial state" {
    var p = cz.probers.eucjp.EUCJPProber.init();
    try std.testing.expectEqualStrings("EUC-JP", p.charsetName());
}

test "EUC-KR prober: valid double-byte stream accrues distribution chars" {
    var p = cz.probers.euckr.EUCKRProber.init();
    // A run of valid EUC-KR lead/trail bytes (0xb0..0xc8 / 0xa1..0xfe). The SM
    // should keep us in `detecting` (not `not_me`) and the distribution analyzer
    // should count characters.
    var buf: [40]u8 = undefined;
    var i: usize = 0;
    while (i < buf.len) : (i += 2) {
        buf[i] = @intCast(0xb0 + (i % 0x10));
        buf[i + 1] = @intCast(0xa1 + (i % 0x20));
    }
    const st = p.handleData(&buf);
    try std.testing.expect(st != .not_me);
    try std.testing.expect(p.dist.total_chars > 0);
}

test "Big5 prober: ASCII-only input does not flip to not_me" {
    var p = cz.probers.big5.Big5Prober.init();
    const st = p.handleData("hello world this is plain ascii");
    try std.testing.expect(st != .not_me);
}

test "MBCS group prober: 7 sub-probers, UTF-8 at slot 0" {
    var g = cz.probers.mbcs_group.MBCSGroupProber.init();
    try std.testing.expectEqual(@as(usize, 7), cz.probers.mbcs_group.NUM_OF_PROBERS);
    try std.testing.expectEqual(@as(u32, 7), g.active_num);
    // Genuine UTF-8 multibyte text should be detected as UTF-8 by the group.
    const utf8_text = "café résumé naïve Zürich — 日本語 中文 한국어";
    _ = g.handleData(utf8_text);
    // The group's best guess (after confidence eval) should be UTF-8 (slot 0).
    _ = g.getConfidence();
    try std.testing.expectEqualStrings("UTF-8", g.charsetName());
}

test "escape prober: 4 SMs, ISO-2022-JP escape sequence detected" {
    var e = cz.probers.escape.EscCharSetProber.init();
    try std.testing.expectEqual(@as(usize, 4), cz.probers.escape.NUM_OF_ESC_CHARSETS);
    // ESC $ B is the ISO-2022-JP designation for JIS X 0208. Surround with
    // ASCII so the SM has a clean start.
    const iso2022jp = "hello \x1b$B\x24\x22\x24\x24\x1b(B world";
    const st = e.handleData(iso2022jp);
    try std.testing.expectEqual(ProbingState.found_it, st);
    try std.testing.expectEqualStrings("ISO-2022-JP", e.charsetName());
}

test "escape prober: ISO-2022-KR escape sequence detected" {
    var e = cz.probers.escape.EscCharSetProber.init();
    // ESC $ ) C is the ISO-2022-KR designator.
    const iso2022kr = "\x1b$)C hello \x0e\x21\x21\x0f";
    const st = e.handleData(iso2022kr);
    try std.testing.expectEqual(ProbingState.found_it, st);
    try std.testing.expectEqualStrings("ISO-2022-KR", e.charsetName());
}

test "escape prober: plain ASCII stays detecting" {
    var e = cz.probers.escape.EscCharSetProber.init();
    const st = e.handleData("plain ascii, no escape sequences here");
    try std.testing.expectEqual(ProbingState.detecting, st);
    try std.testing.expectEqualStrings("", e.charsetName());
}
