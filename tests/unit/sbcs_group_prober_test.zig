// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Pins nsSBCSGroupProber: the 35-slot construction, sub-prober dispatch,
// not_me deactivation, and best-guess name selection. The differential gate is
// the authoritative oracle over the corpus.

const std = @import("std");
const cz = @import("chardetz");
const Group = cz.probers.sbcs_group.SBCSGroupProber;

const alloc = std.testing.allocator;

test "SBCSGroup: exactly 35 prober slots, all active after construction" {
    try std.testing.expectEqual(@as(usize, 35), cz.probers.sbcs_group.NUM_OF_SBCS_PROBERS);
    var g = Group.init(alloc);
    try std.testing.expectEqual(@as(u32, 35), g.active_num);
    try std.testing.expectEqual(cz.prober.ProbingState.detecting, g.getState());
}

test "SBCSGroup: detecting state confidence is in [0,1]" {
    var g = Group.init(alloc);
    _ = g.handleData("\xef\xf0\xe8\xe2\xe5\xf2 \xef\xf0\xe8\xe2\xe5\xf2");
    const cf = g.getConfidence();
    try std.testing.expect(cf >= 0.0 and cf <= 1.0);
}

test "SBCSGroup: Russian windows-1251 text picks a Cyrillic charset name" {
    var g = Group.init(alloc);
    // Repeated Cyrillic words in windows-1251.
    const word = "\xef\xf0\xe8\xe2\xe5\xf2 ";
    var buf: [4096]u8 = undefined;
    var w: usize = 0;
    while (w + word.len <= buf.len) : (w += word.len) {
        @memcpy(buf[w .. w + word.len], word);
    }
    _ = g.handleData(buf[0..w]);
    const name = g.charsetName();
    // The winner must be one of the Cyrillic single-byte charsets, never empty.
    const cyrillic = [_][]const u8{ "WINDOWS-1251", "KOI8-R", "ISO-8859-5", "MAC-CYRILLIC", "IBM866", "IBM855" };
    var ok = false;
    for (cyrillic) |c| {
        if (std.mem.eql(u8, name, c)) ok = true;
    }
    try std.testing.expect(ok);
}

test "SBCSGroup: charsetName defaults to slot 0 when nothing is positive" {
    var g = Group.init(alloc);
    // No data fed → no best guess → defaults to slot 0 (WINDOWS-1251).
    try std.testing.expectEqualStrings("WINDOWS-1251", g.charsetName());
}

test "SBCSGroup: reset reactivates all probers" {
    var g = Group.init(alloc);
    _ = g.handleData("\xef\xf0\xe8\xe2\xe5\xf2");
    g.reset();
    try std.testing.expectEqual(@as(u32, 35), g.active_num);
    try std.testing.expectEqual(cz.prober.ProbingState.detecting, g.getState());
}

test "SBCSGroup: asProber vtable round-trips through the interface" {
    var g = Group.init(alloc);
    const iface = g.asProber();
    _ = iface.handleData("\xef\xf0\xe8\xe2\xe5\xf2 \xef\xf0\xe8\xe2\xe5\xf2");
    const cf = iface.getConfidence();
    try std.testing.expect(cf >= 0.0 and cf <= 1.0);
}
