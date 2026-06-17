// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
//! Unit tests for the PRINTABLE-BINARY glyph table (comptime-built from the
//! vendored character_map.txt). Asserts membership + distinctive classification
//! over known codepoints, including the boundary cases that make the heuristic
//! non-intrusive (literal comma is NOT a PB glyph; literal whitespace is neutral).
const std = @import("std");
const cz = @import("chardetz");
const pbt = cz.printable_binary_table;

test "PB table: membership and distinctive classification over known codepoints" {
    // byte 0x00 → · (U+00B7): a control-byte glyph → allowed AND distinctive.
    try std.testing.expectEqual(@as(?bool, true), pbt.lookup(0x00B7));
    // ␣ (U+2423), the glyph for byte 0x20 (space) → allowed AND distinctive.
    try std.testing.expectEqual(@as(?bool, true), pbt.lookup(0x2423));
    // byte 0x7F → ⌦ (U+2326): a control-byte glyph → distinctive.
    try std.testing.expectEqual(@as(?bool, true), pbt.lookup(0x2326));

    // Self-mapped plain ASCII: allowed but NOT distinctive.
    try std.testing.expectEqual(@as(?bool, false), pbt.lookup('A')); // U+0041
    try std.testing.expectEqual(@as(?bool, false), pbt.lookup('z')); // U+007A
    try std.testing.expectEqual(@as(?bool, false), pbt.lookup('0')); // U+0030
    try std.testing.expectEqual(@as(?bool, false), pbt.lookup('.')); // U+002E

    // Literal whitespace: neutral-allowed (covers -s/-t/-n/-w/-f), NOT distinctive.
    try std.testing.expectEqual(@as(?bool, false), pbt.lookup(0x0020)); // space
    try std.testing.expectEqual(@as(?bool, false), pbt.lookup(0x0009)); // tab
    try std.testing.expectEqual(@as(?bool, false), pbt.lookup(0x000A)); // LF
    try std.testing.expectEqual(@as(?bool, false), pbt.lookup(0x000D)); // CR

    // NOT in the set: literal comma (U+002C; the PB glyph for byte ',' is U+066B,
    // a different codepoint) — this is why normal prose fails Condition A.
    try std.testing.expectEqual(@as(?bool, null), pbt.lookup(0x002C));
    // Emoji far outside the set.
    try std.testing.expectEqual(@as(?bool, null), pbt.lookup(0x1F600));

    // 256 distinct glyphs + 4 literal-whitespace codepoints = 260.
    try std.testing.expectEqual(@as(usize, 260), pbt.allowed_count);
}
