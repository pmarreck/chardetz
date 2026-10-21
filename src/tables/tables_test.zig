//! Smoke checks on the generated tables. Values below are read off upstream's
//! own row comments (e.g. "// a0 - a7"); full verification is the oracle gate.
const std = @import("std");
const all = @import("all.zig");
const types = @import("types.zig");

test "every generated table module compiles" {
    inline for (@typeInfo(all).@"struct".decls) |d| std.testing.refAllDecls(@field(all, d.name));
}

test "BIG5 byte classes match upstream rows" {
    const sm = all.mbcs_sm.Big5SMModel;
    const classOf = struct {
        fn f(m: types.SMModel, byte: u8) u32 {
            return types.getFromPck(byte, m.classTable);
        }
    }.f;
    try std.testing.expectEqual(@as(u32, 1), classOf(sm, 0x00)); // 0x00 allowed as legal
    try std.testing.expectEqual(@as(u32, 0), classOf(sm, 0x0e));
    try std.testing.expectEqual(@as(u32, 2), classOf(sm, 0x41));
    try std.testing.expectEqual(@as(u32, 1), classOf(sm, 0x7f));
    try std.testing.expectEqual(@as(u32, 4), classOf(sm, 0xa0));
    try std.testing.expectEqual(@as(u32, 3), classOf(sm, 0xa1));
    try std.testing.expectEqual(@as(u32, 0), classOf(sm, 0xff));
}

test "frequency tables have their declared sizes" {
    try std.testing.expectEqual(@as(usize, all.big5_freq.BIG5_TABLE_SIZE), all.big5_freq.Big5CharToFreqOrder.len);
    try std.testing.expectEqual(@as(usize, all.jis_freq.JIS_TABLE_SIZE), all.jis_freq.JISCharToFreqOrder.len);
}
