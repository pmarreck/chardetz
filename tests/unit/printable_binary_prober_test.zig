// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
//! Unit tests for the PRINTABLE-BINARY prober. Feeds the prober raw UTF-8 byte
//! buffers (PB glyph sequences + plain text) and asserts found_it / confidence per
//! the heuristic: ≥99% of codepoints in the PB set AND ≥10% distinctive AND ≥32
//! codepoints. Fixtures are real PB glyph codepoints written as UTF-8 literals.
const std = @import("std");
const cz = @import("chardetz");
const PBProber = cz.probers.printable_binary.PBProber;
const ProbingState = cz.prober.ProbingState;

// 10 distinctive glyphs (PB bytes 0x00..0x09: · ¯ « » ϟ ¿ ¡ ª ⌫ ⇥), repeated.
const distinctive10 = "·¯«»ϟ¿¡ª⌫⇥";

test "strong PB (all distinctive glyphs, >=32 cp) → found_it, high confidence" {
    const buf = distinctive10 ** 4; // 40 codepoints, 100% distinctive, 100% in-set
    var p = PBProber.init();
    const st = p.handleData(buf);
    try std.testing.expectEqual(ProbingState.found_it, st);
    try std.testing.expect(p.getConfidence() >= 0.95);
}

test "mixed PB (self-mapped letters + spaces + distinctive glyphs) → found_it" {
    // 24 neutral cp (letters+spaces) + 20 distinctive = 44 cp, ~45% distinctive.
    const buf = "hello world " ** 2 ++ distinctive10 ** 2;
    var p = PBProber.init();
    try std.testing.expectEqual(ProbingState.found_it, p.handleData(buf));
}

test "plain text (no distinctive glyphs) → NOT PB, low confidence" {
    // All letters + spaces are in the PB set but 0% distinctive → Condition B fails.
    const buf = "the quick brown fox jumps over the lazy dog today and tomorrow";
    var p = PBProber.init();
    try std.testing.expect(p.handleData(buf) != .found_it);
    try std.testing.expect(p.getConfidence() < 0.20); // below MINIMUM_THRESHOLD
}

test "text with commas → NOT PB (comma U+002C is not a PB glyph → fails 99% in-set)" {
    const buf = "hello, world. this, is, ordinary, text, with, many, commas, here, ok";
    var p = PBProber.init();
    try std.testing.expect(p.handleData(buf) != .found_it);
    try std.testing.expect(p.getConfidence() < 0.20);
}

test "too short (< 32 codepoints) → NOT found_it even if all distinctive" {
    const buf = distinctive10; // 10 codepoints, below the min-data guard
    var p = PBProber.init();
    try std.testing.expect(p.handleData(buf) != .found_it);
}

test "literal whitespace is neutral (covers preserve modes) — spaces don't add distinctiveness" {
    // 20 distinctive + many literal spaces; still >10% distinctive, all in-set → found_it.
    const buf = distinctive10 ** 2 ++ "                              "; // 30 spaces
    var p = PBProber.init();
    try std.testing.expectEqual(ProbingState.found_it, p.handleData(buf));
}

// ── Detector integration (PBProber wired as high-byte slot 0) ────────────────
test "detect(): strong PB content → PRINTABLE-BINARY" {
    const buf = distinctive10 ** 4;
    try std.testing.expectEqualStrings("PRINTABLE-BINARY", cz.detect(std.testing.allocator, buf));
}

test "detect(): PB mixed with legible text → PRINTABLE-BINARY" {
    const buf = "hello world " ** 2 ++ distinctive10 ** 2;
    try std.testing.expectEqualStrings("PRINTABLE-BINARY", cz.detect(std.testing.allocator, buf));
}

test "detect(): plain ASCII is unaffected → ASCII (PB prober never runs on pure-ASCII)" {
    const buf = "the quick brown fox jumps over the lazy dog today and tomorrow";
    try std.testing.expectEqualStrings("ASCII", cz.detect(std.testing.allocator, buf));
}

test "detect(): ordinary CJK UTF-8 is NOT mis-flagged as PB → UTF-8" {
    // CJK codepoints are not in the PB glyph set → Condition A fails → falls through.
    const buf = "你好世界这是一段普通的中文文字内容用来测试" ** 3;
    try std.testing.expectEqualStrings("UTF-8", cz.detect(std.testing.allocator, buf));
}
