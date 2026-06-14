// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Pins nsUTF8Prober's confidence formula and state behavior. The differential
// gate is the authoritative oracle; this checks the math directly.

const std = @import("std");
const cz = @import("chardetz");
const UTF8Prober = cz.probers.utf8.UTF8Prober;

const eps: f32 = 1e-7;

test "UTF8 confidence: zero multibyte chars → 1 - 0.99 = 0.01" {
    var p = UTF8Prober.init();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 - 0.99), p.getConfidence(), eps);
}

test "UTF8 confidence: 3 multibyte chars → 1 - 0.99*0.5^3" {
    var p = UTF8Prober.init();
    // Feed three valid 2-byte sequences (0xC3 0xA9 = 'é').
    _ = p.handleData("\xC3\xA9\xC3\xA9\xC3\xA9");
    const expected: f32 = 1.0 - 0.99 * 0.5 * 0.5 * 0.5;
    try std.testing.expectApproxEqAbs(expected, p.getConfidence(), eps);
}

test "UTF8 confidence: 6+ multibyte chars saturates at 0.99" {
    var p = UTF8Prober.init();
    // Eight valid 2-byte sequences → num_mb_char = 8 ≥ 6.
    _ = p.handleData("\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9");
    try std.testing.expectApproxEqAbs(@as(f32, 0.99), p.getConfidence(), eps);
}

test "UTF8 prober: many multibyte chars shortcut to found_it past SHORTCUT_THRESHOLD" {
    var p = UTF8Prober.init();
    // 1 - 0.99*0.5^5 ≈ 0.969 > 0.95 → found_it via the shortcut.
    const st = p.handleData("\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9");
    try std.testing.expectEqual(cz.prober.ProbingState.found_it, st);
}

test "UTF8 prober: invalid UTF-8 (lead byte then ASCII) does NOT reach found_it" {
    var p = UTF8Prober.init();
    // 0xC3 expects a continuation; 0x41 ('A') breaks it → SM hits error, not its_me.
    const st = p.handleData("\xC3\x41");
    try std.testing.expect(st != .found_it);
}

test "UTF8 prober: charsetName is UTF-8 and reset clears state" {
    var p = UTF8Prober.init();
    try std.testing.expectEqualStrings("UTF-8", p.charsetName());
    _ = p.handleData("\xC3\xA9\xC3\xA9");
    p.reset();
    try std.testing.expectEqual(cz.prober.ProbingState.detecting, p.getState());
    try std.testing.expectApproxEqAbs(@as(f32, 0.01), p.getConfidence(), eps);
}

test "UTF8 prober: asProber vtable round-trips through the interface" {
    var p = UTF8Prober.init();
    const iface = p.asProber();
    _ = iface.handleData("\xC3\xA9\xC3\xA9\xC3\xA9");
    const expected: f32 = 1.0 - 0.99 * 0.5 * 0.5 * 0.5;
    try std.testing.expectApproxEqAbs(expected, iface.getConfidence(), eps);
    try std.testing.expectEqualStrings("UTF-8", iface.charsetName());
}
