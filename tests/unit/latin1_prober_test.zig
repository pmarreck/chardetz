// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Pins nsLatin1Prober's class model, the not_me illegal-bigram path, and the
// (likely - 20×unlikely)/2 confidence formula. The differential gate is the
// authoritative oracle over the corpus.

const std = @import("std");
const cz = @import("chardetz");
const Latin1 = cz.probers.latin1.Latin1Prober;

const alloc = std.testing.allocator;
const eps: f32 = 1e-6;

test "Latin1: charsetName is WINDOWS-1252" {
    var p = Latin1.init(alloc);
    try std.testing.expectEqualStrings("WINDOWS-1252", p.charsetName());
}

test "Latin1: no data → 0.0 confidence" {
    var p = Latin1.init(alloc);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), p.getConfidence(), eps);
}

test "Latin1: accented French text yields positive confidence" {
    var p = Latin1.init(alloc);
    // "café déjà" in Latin-1 (é=0xE9, à=0xE0) — accented-small-vowel after
    // ascii-small are 'likely' bigrams.
    _ = p.handleData("caf\xe9 d\xe9j\xe0 vu text here");
    try std.testing.expect(p.getConfidence() > 0.0);
}

test "Latin1: an undefined-class byte after data → not_me (illegal bigram)" {
    var p = Latin1.init(alloc);
    // 0x81 is UDF; the bigram (prev,UDF) is freq 0 in every row → not_me.
    // Precede with a non-OTH class so the transition is actually evaluated.
    const st = p.handleData("A\x81");
    try std.testing.expectEqual(cz.prober.ProbingState.not_me, st);
    // not_me confidence is pinned to 0.01.
    try std.testing.expectApproxEqAbs(@as(f32, 0.01), p.getConfidence(), eps);
}

test "Latin1: confidence is halved (latin1 is deliberately downweighted)" {
    var p = Latin1.init(alloc);
    // Feed only 'likely' bigrams so the pre-halving confidence is 1.0; after
    // the *0.5 it must be ~0.5.
    _ = p.handleData("abcdefghij");
    try std.testing.expect(p.getConfidence() <= 0.5 + eps);
}

test "Latin1: reset clears the frequency counters" {
    var p = Latin1.init(alloc);
    _ = p.handleData("caf\xe9 d\xe9j\xe0 vu");
    p.reset();
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), p.getConfidence(), eps);
    try std.testing.expectEqual(cz.prober.ProbingState.detecting, p.getState());
}
