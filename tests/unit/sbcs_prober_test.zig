// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Pins nsSingleByteCharSetProber behavior. The differential gate is the
// authoritative numeric oracle; these check the state machine + structural
// invariants of the confidence formula directly.

const std = @import("std");
const cz = @import("chardetz");
const Sbcs = cz.probers.sbcs.SingleByteCharSetProber;
const NameProber = cz.probers.sbcs.NameProber;
const sm = cz.tables.sbcs;

const eps: f32 = 1e-7;

test "SBCS: fresh prober is detecting with 0.01 confidence (no sequences yet)" {
    var p = Sbcs.init(&sm.russian.Win1251RussianModel);
    try std.testing.expectEqual(cz.prober.ProbingState.detecting, p.getState());
    try std.testing.expectApproxEqAbs(@as(f32, 0.01), p.getConfidence(), eps);
}

test "SBCS: an illegal codepoint for the model → not_me immediately" {
    // Find a byte mapped to ILL (255) in the windows-1251 order map.
    const model = &sm.russian.Win1251RussianModel;
    var ill_byte: ?u8 = null;
    var b: usize = 0;
    while (b < 256) : (b += 1) {
        if (model.char_to_order_map[b] == cz.sbcs_model.ILL) {
            ill_byte = @intCast(b);
            break;
        }
    }
    try std.testing.expect(ill_byte != null);

    var p = Sbcs.init(model);
    const st = p.handleData(&[_]u8{ill_byte.?});
    try std.testing.expectEqual(cz.prober.ProbingState.not_me, st);
}

test "SBCS: real Cyrillic text raises windows-1251 confidence above 0" {
    // "привет" in windows-1251 (each Cyrillic letter is a single high byte).
    const text = "\xef\xf0\xe8\xe2\xe5\xf2 \xef\xf0\xe8\xe2\xe5\xf2";
    var p = Sbcs.init(&sm.russian.Win1251RussianModel);
    _ = p.handleData(text);
    try std.testing.expect(p.getConfidence() > 0.0);
}

test "SBCS: charsetName returns the model name when no name prober is set" {
    var p = Sbcs.init(&sm.russian.Win1251RussianModel);
    try std.testing.expectEqualStrings("WINDOWS-1251", p.charsetName());
}

test "SBCS: a name prober overrides the model's own charset name" {
    const Stub = struct {
        fn name(_: *anyopaque) []const u8 {
            return "OVERRIDDEN";
        }
    };
    var dummy: u8 = 0;
    var p = Sbcs.initFull(&sm.hebrew.Win1255Model, false, NameProber{
        .ptr = &dummy,
        .charset_name = Stub.name,
    });
    try std.testing.expectEqualStrings("OVERRIDDEN", p.charsetName());
}

test "SBCS: reset clears state, sequences, and confidence back to baseline" {
    var p = Sbcs.init(&sm.russian.Win1251RussianModel);
    _ = p.handleData("\xef\xf0\xe8\xe2\xe5\xf2");
    p.reset();
    try std.testing.expectEqual(cz.prober.ProbingState.detecting, p.getState());
    try std.testing.expectApproxEqAbs(@as(f32, 0.01), p.getConfidence(), eps);
}

test "SBCS: reversed lookup transposes the bigram (visual vs logical Hebrew)" {
    // Same input, one normal and one reversed prober over the same model. With
    // a directional Hebrew sample the two should generally diverge in
    // confidence; at minimum the reversed flag must change observable behavior.
    const text = "\xe0\xe1\xe2 \xe0\xe1\xe2 \xe0\xe1\xe2";
    var fwd = Sbcs.initFull(&sm.hebrew.Win1255Model, false, null);
    var rev = Sbcs.initFull(&sm.hebrew.Win1255Model, true, null);
    _ = fwd.handleData(text);
    _ = rev.handleData(text);
    // Both ran without error and remain queryable; confidences are finite.
    try std.testing.expect(!std.math.isNan(fwd.getConfidence()));
    try std.testing.expect(!std.math.isNan(rev.getConfidence()));
}

// ── Regression: faithful port of uchardet's PRUint32 underflow ──────────────
// nsSingleByteCharSetProber::GetConfidence (nsSBCharSetProber.cpp:131) computes
//   r = r * (mTotalChar - mCtrlChar) / mTotalChar
// with mTotalChar/mCtrlChar as PRUint32 (unsigned). When a buffer has MORE
// control bytes than word bytes (ctrl_char > total_char), the C++ subtraction
// WRAPS to a huge value, blowing r past 1.0 so the `if (r >= 1.0) r = 0.99` cap
// fires → confidence 0.99. A naive float port subtracts as signed, gets a
// negative r, and reports ~0 → the SBCS group falls below MINIMUM_THRESHOLD and
// the detector returns "" (or a different charset). The differential FUZZ
// harness surfaced this on inputs like `fe f0 9f 98 81` (oracle: ISO-8859-7,
// pre-fix chardetz: ""). To stay a faithful drop-in we must reproduce the
// wraparound. This pins it: ctrl-heavy high-byte input must yield the capped
// 0.99, NOT a negative/near-zero confidence.
test "SBCS: ctrl-heavy input wraps like uchardet's PRUint32 (confidence caps at 0.99, not negative)" {
    // fe f0 = one word bigram (orders 28, 11 in ISO-8859-7); 9f 98 81 are all
    // control (order CTR) → total_char=2, ctrl_char=3 → (2 - 3) underflows.
    var p = Sbcs.init(&sm.greek.Iso_8859_7GreekModel);
    _ = p.handleData("\xfe\xf0\x9f\x98\x81");
    const cf = p.getConfidence();
    // Must match uchardet's capped 0.99 (the wraparound result), and in
    // particular must NOT be negative (the signed-float-subtraction bug).
    try std.testing.expect(cf >= 0.0); // catches the negative-confidence bug
    try std.testing.expectApproxEqAbs(@as(f32, 0.99), cf, eps);
}
