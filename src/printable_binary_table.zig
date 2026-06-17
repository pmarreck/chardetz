// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
//! PRINTABLE-BINARY glyph table — comptime-built from the vendored
//! `printable_binary_map.txt` (byte-identical to printable_binary's source-of-truth
//! character_map.txt). Provides the membership + "distinctive" classifier the PB
//! prober uses for its heuristic.
//!
//! A codepoint is "allowed" iff it is one of the 256 PB glyphs OR a literal
//! whitespace char (space/tab/LF/CR — the optional preserve-mode forms). It is
//! "distinctive" iff it is a PB glyph whose codepoint differs from its source byte
//! (i.e. NOT a self-mapped plain-ASCII alnum/period, and not literal whitespace) —
//! these are the control/punctuation/high-byte glyphs that mark content as PB.
const std = @import("std");

/// The source-of-truth map (one glyph per non-comment line, byte order).
const map_src = @embedFile("printable_binary_map.txt");

const Entry = struct { cp: u21, distinctive: bool };

/// Literal whitespace codepoints permitted by the preserve flags (-s/-t/-n/-w) and
/// formatting. Neutral: allowed but never "distinctive".
pub const literal_whitespace = [_]u21{ 0x20, 0x09, 0x0A, 0x0D };

const built = blk: {
    @setEvalBranchQuota(1_000_000);
    var entries: [260]Entry = undefined;
    var byte_idx: usize = 0;
    var it = std.mem.splitScalar(u8, map_src, '\n');
    while (it.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "##")) continue; // full-line comment
        // The glyph is the first whitespace-delimited token.
        var end: usize = 0;
        while (end < trimmed.len and trimmed[end] != ' ' and trimmed[end] != '\t') : (end += 1) {}
        const tok = trimmed[0..end];
        const seq_len = std.unicode.utf8ByteSequenceLength(tok[0]) catch unreachable;
        const cp = std.unicode.utf8Decode(tok[0..seq_len]) catch unreachable;
        if (byte_idx >= 256) @compileError("printable_binary_map.txt has more than 256 glyph lines");
        // Self-mapped iff the glyph codepoint equals its source byte (plain ASCII
        // alnum/period); everything else is a distinctive glyph.
        entries[byte_idx] = .{ .cp = cp, .distinctive = (@as(usize, cp) != byte_idx) };
        byte_idx += 1;
    }
    if (byte_idx != 256) @compileError("printable_binary_map.txt must have exactly 256 glyph lines");
    for (literal_whitespace) |w| {
        entries[byte_idx] = .{ .cp = w, .distinctive = false };
        byte_idx += 1;
    }
    std.mem.sort(Entry, entries[0..byte_idx], {}, struct {
        fn lt(_: void, a: Entry, b: Entry) bool {
            return a.cp < b.cp;
        }
    }.lt);
    break :blk .{ .entries = entries, .n = byte_idx };
};

/// Total distinct allowed codepoints: 256 glyphs + 4 literal-whitespace = 260.
pub const allowed_count: usize = built.n;

/// lookup(cp) → null if `cp` is not an allowed PB codepoint; otherwise its
/// `distinctive` flag (true = a control/punctuation/high-byte glyph, false =
/// self-mapped ASCII or neutral literal whitespace). Binary search, O(log 260).
pub fn lookup(cp: u21) ?bool {
    var lo: usize = 0;
    var hi: usize = built.n;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = built.entries[mid];
        if (e.cp == cp) return e.distinctive;
        if (e.cp < cp) lo = mid + 1 else hi = mid;
    }
    return null;
}
