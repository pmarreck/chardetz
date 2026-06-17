// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
//! Metamorphic gate for the PRINTABLE-BINARY prober (the primary, oracle-free
//! validation). The fixtures in ../fixtures/pb/ are REAL printable-binary CLI
//! output over fixed inputs (binary + legible-text-mixed), across the default and
//! preserve/format modes (-s/-w/-f). The encoder is the independent truth source;
//! chardetz must round-trip them to PRINTABLE-BINARY. Regenerate via
//! ../fixtures/pb/gen.sh (see that file for provenance).
const std = @import("std");
const cz = @import("chardetz");

fn expectPB(comptime path: []const u8) !void {
    const bytes = @embedFile(path);
    try std.testing.expectEqualStrings("PRINTABLE-BINARY", cz.detect(std.testing.allocator, bytes));
}

test "metamorphic: real PB output of a binary file → PRINTABLE-BINARY (default/-s/-w/-f)" {
    try expectPB("../fixtures/pb/bin_default.pbtxt");
    try expectPB("../fixtures/pb/bin_s.pbtxt");
    try expectPB("../fixtures/pb/bin_w.pbtxt");
    try expectPB("../fixtures/pb/bin_f.pbtxt");
}

test "metamorphic: real PB output of legible text+binary mix → PRINTABLE-BINARY (default/-w)" {
    try expectPB("../fixtures/pb/mix_default.pbtxt");
    try expectPB("../fixtures/pb/mix_w.pbtxt");
}
