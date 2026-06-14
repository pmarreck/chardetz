const std = @import("std");
const cz = @import("chardetz");
const jca = cz.jp_context_analysis;
const tables = cz.tables;

test "SJIS hiragana GetOrder: first byte 0x82, second 0x9f..0xf1" {
    var a = jca.JapaneseContextAnalysis.init(&tables.jp_context.jp2_context, .sjis);
    a.reset(true);
    // First hiragana sets last_char_order but does not bump total_rel.
    a.handleOneChar(&[_]u8{ 0x82, 0x9f }, 2); // order 0
    try std.testing.expectEqual(@as(u32, 0), a.total_rel);
    // Second hiragana forms a pair → total_rel++.
    a.handleOneChar(&[_]u8{ 0x82, 0xa0 }, 2); // order 1
    try std.testing.expectEqual(@as(u32, 1), a.total_rel);
}

test "SJIS non-hiragana resets the pair chain (order -1)" {
    var a = jca.JapaneseContextAnalysis.init(&tables.jp_context.jp2_context, .sjis);
    a.reset(true);
    a.handleOneChar(&[_]u8{ 0x82, 0x9f }, 2); // hiragana, order 0
    a.handleOneChar(&[_]u8{ 0x83, 0x40 }, 2); // not hiragana (first byte != 0x82)
    a.handleOneChar(&[_]u8{ 0x82, 0xa0 }, 2); // hiragana again
    // The middle char broke the chain, so no pair was ever counted.
    try std.testing.expectEqual(@as(u32, 0), a.total_rel);
}

test "EUC-JP hiragana GetOrder: first byte 0xa4, second 0xa1..0xf3" {
    var a = jca.JapaneseContextAnalysis.init(&tables.jp_context.jp2_context, .eucjp);
    a.reset(true);
    a.handleOneChar(&[_]u8{ 0xa4, 0xa1 }, 2); // order 0
    a.handleOneChar(&[_]u8{ 0xa4, 0xa2 }, 2); // order 1
    try std.testing.expectEqual(@as(u32, 1), a.total_rel);
}

test "GetConfidence is DONT_KNOW before threshold" {
    var a = jca.JapaneseContextAnalysis.init(&tables.jp_context.jp2_context, .sjis);
    try std.testing.expectEqual(jca.DONT_KNOW, a.getConfidence());
}

test "GetConfidence = (totalRel - relSample[0]) / totalRel" {
    var a = jca.JapaneseContextAnalysis.init(&tables.jp_context.jp2_context, .sjis);
    a.reset(true); // threshold 0
    // Build a chain of hiragana pairs. We don't assert the exact value (depends
    // on the table categories) but it must be in [0,1] once past threshold.
    var i: usize = 0;
    while (i < 10) : (i += 1) a.handleOneChar(&[_]u8{ 0x82, @intCast(0x9f + (i % 0x50)) }, 2);
    const c = a.getConfidence();
    try std.testing.expect(c >= 0.0 and c <= 1.0);
    try std.testing.expect(a.total_rel > 0);
}

test "Reset clears state" {
    var a = jca.JapaneseContextAnalysis.init(&tables.jp_context.jp2_context, .sjis);
    a.handleOneChar(&[_]u8{ 0x82, 0x9f }, 2);
    a.reset(false);
    try std.testing.expectEqual(@as(u32, 0), a.total_rel);
    try std.testing.expectEqual(@as(i32, -1), a.last_char_order);
}
