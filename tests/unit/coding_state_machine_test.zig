// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Pins the CodingStateMachine driver mechanics against the GENERATED UTF8SMModel.
// The authoritative oracle is the differential gate (chardetz.detect vs uchardet);
// this unit test only proves the DFA driver wiring (class lookup, charLen capture,
// state transition) behaves like nsCodingStateMachine on the UTF-8 model.

const std = @import("std");
const cz = @import("chardetz");
const CodingStateMachine = cz.coding_state_machine.CodingStateMachine;
const SMState = cz.coding_state_machine.SMState;

test "UTF-8 SM: ASCII byte stays at start with char len 1" {
    var sm = CodingStateMachine.init(&cz.tables.mbcs_sm.UTF8SMModel);
    // 'A' (0x41) is a single-byte (ASCII) character: charLen 1, returns to start.
    try std.testing.expectEqual(SMState.start, sm.nextState(0x41));
    try std.testing.expectEqual(@as(u32, 1), sm.getCurrentCharLen());
}

test "UTF-8 SM: valid 2-byte sequence (0xC3 0xA9 = 'é') completes back to start" {
    var sm = CodingStateMachine.init(&cz.tables.mbcs_sm.UTF8SMModel);
    // First byte of a 2-byte char: charLen becomes 2, state leaves start.
    const s1 = sm.nextState(0xC3);
    try std.testing.expect(s1 != .@"error");
    try std.testing.expectEqual(@as(u32, 2), sm.getCurrentCharLen());
    // Continuation byte completes the character → back to start.
    try std.testing.expectEqual(SMState.start, sm.nextState(0xA9));
}

test "UTF-8 SM: valid 3-byte sequence (0xE2 0x82 0xAC = '€') completes back to start" {
    var sm = CodingStateMachine.init(&cz.tables.mbcs_sm.UTF8SMModel);
    try std.testing.expect(sm.nextState(0xE2) != .@"error");
    try std.testing.expectEqual(@as(u32, 3), sm.getCurrentCharLen());
    try std.testing.expect(sm.nextState(0x82) != .@"error");
    try std.testing.expectEqual(SMState.start, sm.nextState(0xAC));
}

test "UTF-8 SM: invalid sequence (lead byte then ASCII) reaches error" {
    var sm = CodingStateMachine.init(&cz.tables.mbcs_sm.UTF8SMModel);
    _ = sm.nextState(0xC3); // expects a continuation byte next
    try std.testing.expectEqual(SMState.@"error", sm.nextState(0x41)); // ASCII instead → error
}

test "UTF-8 SM: reset returns to start" {
    var sm = CodingStateMachine.init(&cz.tables.mbcs_sm.UTF8SMModel);
    _ = sm.nextState(0xC3);
    sm.reset();
    try std.testing.expectEqual(SMState.start, sm.current_state);
    // After reset a fresh valid char parses cleanly.
    try std.testing.expect(sm.nextState(0xC3) != .@"error");
    try std.testing.expectEqual(SMState.start, sm.nextState(0xA9));
}

test "UTF-8 SM: model name is UTF-8" {
    var sm = CodingStateMachine.init(&cz.tables.mbcs_sm.UTF8SMModel);
    try std.testing.expectEqualStrings("UTF-8", sm.getCodingStateMachine());
}
