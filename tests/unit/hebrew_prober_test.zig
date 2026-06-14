// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Pins nsHebrewProber's final-letter heuristic and logical-vs-visual decision.
// These are fully deterministic (no model lookup) so they are hand-verifiable.

const std = @import("std");
const cz = @import("chardetz");
const Hebrew = cz.probers.hebrew.HebrewProber;

// Code points used by the heuristic (windows-1255 / ISO-8859-8).
const FINAL_MEM = "\xed"; // a final-form letter
const NORMAL_MEM = "\xee"; // its non-final form
const A = "\xe0"; // an ordinary Hebrew letter (aleph)

test "Hebrew: confidence is always 0.0 (helper prober, never decides alone)" {
    var p = Hebrew.init();
    try std.testing.expectEqual(@as(f32, 0.0), p.getConfidence());
}

test "Hebrew: word ending in a FINAL letter scores Logical → WINDOWS-1255" {
    var p = Hebrew.init();
    // Five 2-letter words each ending in a final letter → logical score 5,
    // which meets MIN_FINAL_CHAR_DISTANCE (5) → Logical wins decisively.
    const w = A ++ FINAL_MEM ++ " ";
    _ = p.handleData(w ++ w ++ w ++ w ++ w);
    try std.testing.expectEqualStrings("WINDOWS-1255", p.charsetName());
}

test "Hebrew: word ending in a NON-FINAL form scores Visual → ISO-8859-8" {
    var p = Hebrew.init();
    // Words ending in the non-final form of a final-capable letter → visual.
    const w = A ++ NORMAL_MEM ++ " ";
    _ = p.handleData(w ++ w ++ w ++ w ++ w);
    try std.testing.expectEqualStrings("ISO-8859-8", p.charsetName());
}

test "Hebrew: word STARTING with a final letter scores Visual" {
    var p = Hebrew.init();
    // [space][final letter][ordinary letter] repeated → case (3): +visual.
    const w = FINAL_MEM ++ A ++ " ";
    _ = p.handleData(w ++ w ++ w ++ w ++ w);
    try std.testing.expectEqualStrings("ISO-8859-8", p.charsetName());
}

test "Hebrew: reset clears the accumulated scores" {
    var p = Hebrew.init();
    const w = A ++ FINAL_MEM ++ " ";
    _ = p.handleData(w ++ w ++ w ++ w ++ w);
    p.reset();
    // With no scores and no model probers, the decision defaults to Logical.
    try std.testing.expectEqualStrings("WINDOWS-1255", p.charsetName());
}

test "Hebrew: with no model probers wired, getState is not_me" {
    var p = Hebrew.init();
    try std.testing.expectEqual(cz.prober.ProbingState.not_me, p.getState());
}
