// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Pins nsHebrewProber's final-letter heuristic and logical-vs-visual decision.
// These are fully deterministic (no model lookup) so they are hand-verifiable.
//
// NOTE: nsHebrewProber::HandleData returns early (eNotMe) and scores NOTHING
// when both model probers are inactive (GetState). The group prober always
// wires two active model probers, so to exercise the heuristic in isolation we
// wire two stubs that report `detecting` (active) with 0.0 confidence. That
// isolates the final-letter scoring from the model-confidence tiebreak.

const std = @import("std");
const cz = @import("chardetz");
const Hebrew = cz.probers.hebrew.HebrewProber;
const ModelProber = cz.probers.hebrew.ModelProber;
const ProbingState = cz.prober.ProbingState;

// Code points used by the heuristic (windows-1255 / ISO-8859-8).
const FINAL_MEM = "\xed"; // a final-form letter
const NORMAL_MEM = "\xee"; // its non-final form
const A = "\xe0"; // an ordinary Hebrew letter (aleph)

// A stub model prober that stays active (detecting) with 0.0 confidence, so the
// Hebrew prober keeps scoring and the model-confidence tiebreak is a wash.
const Stub = struct {
    fn conf(_: *anyopaque) f32 {
        return 0.0;
    }
    fn state(_: *anyopaque) ProbingState {
        return .detecting;
    }
    fn modelProber(self: *@This()) ModelProber {
        return .{ .ptr = self, .get_confidence = conf, .get_state = state };
    }
};

fn wireActive(p: *Hebrew, s1: *Stub, s2: *Stub) void {
    p.setModelProbers(s1.modelProber(), s2.modelProber());
}

test "Hebrew: confidence is always 0.0 (helper prober, never decides alone)" {
    var p = Hebrew.init();
    try std.testing.expectEqual(@as(f32, 0.0), p.getConfidence());
}

test "Hebrew: word ending in a FINAL letter scores Logical → WINDOWS-1255" {
    var p = Hebrew.init();
    var s1 = Stub{};
    var s2 = Stub{};
    wireActive(&p, &s1, &s2);
    // Five 2-letter words each ending in a final letter → logical score 5,
    // which meets MIN_FINAL_CHAR_DISTANCE (5) → Logical wins decisively.
    const w = A ++ FINAL_MEM ++ " ";
    _ = p.handleData(w ++ w ++ w ++ w ++ w);
    try std.testing.expectEqualStrings("WINDOWS-1255", p.charsetName());
}

test "Hebrew: word ending in a NON-FINAL form scores Visual → ISO-8859-8" {
    var p = Hebrew.init();
    var s1 = Stub{};
    var s2 = Stub{};
    wireActive(&p, &s1, &s2);
    // Words ending in the non-final form of a final-capable letter → visual.
    const w = A ++ NORMAL_MEM ++ " ";
    _ = p.handleData(w ++ w ++ w ++ w ++ w);
    try std.testing.expectEqualStrings("ISO-8859-8", p.charsetName());
}

test "Hebrew: word STARTING with a final letter scores Visual" {
    var p = Hebrew.init();
    var s1 = Stub{};
    var s2 = Stub{};
    wireActive(&p, &s1, &s2);
    // [final letter][ordinary letter][space] repeated → case (3): +visual on the
    // [space][final][not-space] transition at each word boundary.
    const w = FINAL_MEM ++ A ++ " ";
    _ = p.handleData(w ++ w ++ w ++ w ++ w);
    try std.testing.expectEqualStrings("ISO-8859-8", p.charsetName());
}

test "Hebrew: reset clears the accumulated scores" {
    var p = Hebrew.init();
    var s1 = Stub{};
    var s2 = Stub{};
    wireActive(&p, &s1, &s2);
    const w = A ++ FINAL_MEM ++ " ";
    _ = p.handleData(w ++ w ++ w ++ w ++ w);
    p.reset();
    // With no scores and a wash on model confidence, the decision defaults to
    // Logical (finalsub == 0 → not < 0 → Logical).
    try std.testing.expectEqualStrings("WINDOWS-1255", p.charsetName());
}

test "Hebrew: with no model probers wired, getState is not_me and HandleData scores nothing" {
    var p = Hebrew.init();
    try std.testing.expectEqual(ProbingState.not_me, p.getState());
    // HandleData returns not_me immediately and accumulates no score.
    const w = A ++ NORMAL_MEM ++ " ";
    _ = p.handleData(w ++ w ++ w ++ w ++ w);
    try std.testing.expectEqual(@as(i32, 0), p.final_char_visual_score);
    try std.testing.expectEqual(@as(i32, 0), p.final_char_logical_score);
}
