// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsEscCharSetProber (.cpp/.h). Holds 4 CodingStateMachines for
// the escape-sequence encodings [HZ, ISO-2022-CN, ISO-2022-JP, ISO-2022-KR].
// HandleData walks every byte while still detecting, running each SM from the
// highest index down; the first SM to reach eItsMe wins and the detected
// charset is that SM model's name (GetCodingStateMachine() → model.name).
// Confidence is a fixed 0.99 once detecting (the SMs are exact, not statistical).

const std = @import("std");
const csm = @import("../coding_state_machine.zig");
const prober = @import("../prober.zig");
const tables = @import("../tables.zig");

const ProbingState = prober.ProbingState;

/// NUM_OF_ESC_CHARSETS — nsEscCharsetProber.h.
pub const NUM_OF_ESC_CHARSETS: usize = 4;

pub const EscCharSetProber = struct {
    coding_sm: [NUM_OF_ESC_CHARSETS]csm.CodingStateMachine,
    active_sm: u32 = NUM_OF_ESC_CHARSETS,
    state: ProbingState = .detecting,
    detected_charset: []const u8 = "",

    pub fn init() EscCharSetProber {
        return .{
            .coding_sm = .{
                csm.CodingStateMachine.init(&tables.esc_sm.HZSMModel),
                csm.CodingStateMachine.init(&tables.esc_sm.ISO2022CNSMModel),
                csm.CodingStateMachine.init(&tables.esc_sm.ISO2022JPSMModel),
                csm.CodingStateMachine.init(&tables.esc_sm.ISO2022KRSMModel),
            },
        };
    }

    pub fn reset(self: *EscCharSetProber) void {
        self.state = .detecting;
        for (&self.coding_sm) |*sm| sm.reset();
        self.active_sm = NUM_OF_ESC_CHARSETS;
        self.detected_charset = "";
    }

    /// nsEscCharSetProber::HandleData. Iterate every byte while still detecting;
    /// for each, run the active SMs from the top down. First eItsMe wins.
    pub fn handleData(self: *EscCharSetProber, buf: []const u8) ProbingState {
        var i: usize = 0;
        while (i < buf.len and self.state == .detecting) : (i += 1) {
            var j: i64 = @as(i64, @intCast(self.active_sm)) - 1;
            while (j >= 0) : (j -= 1) {
                const idx: usize = @intCast(j);
                const cs = self.coding_sm[idx].nextState(buf[i]);
                if (cs == .its_me) {
                    self.state = .found_it;
                    self.detected_charset = self.coding_sm[idx].getCodingStateMachine();
                    return self.state;
                }
            }
        }
        return self.state;
    }

    /// nsEscCharSetProber::GetConfidence — fixed 0.99.
    pub fn getConfidence(_: *EscCharSetProber) f32 {
        return 0.99;
    }

    pub fn getState(self: *EscCharSetProber) ProbingState {
        return self.state;
    }

    /// nsEscCharSetProber::GetCharSetName — the winning SM model's name ("" until found).
    pub fn charsetName(self: *EscCharSetProber) []const u8 {
        return self.detected_charset;
    }

    fn vtHandleData(ptr: *anyopaque, buf: []const u8) ProbingState {
        return handleData(@ptrCast(@alignCast(ptr)), buf);
    }
    fn vtGetConfidence(ptr: *anyopaque) f32 {
        return getConfidence(@ptrCast(@alignCast(ptr)));
    }
    fn vtGetState(ptr: *anyopaque) ProbingState {
        return getState(@ptrCast(@alignCast(ptr)));
    }
    fn vtReset(ptr: *anyopaque) void {
        return reset(@ptrCast(@alignCast(ptr)));
    }
    fn vtCharsetName(ptr: *anyopaque) []const u8 {
        return charsetName(@ptrCast(@alignCast(ptr)));
    }

    const vtable = prober.Prober.VTable{
        .handle_data = vtHandleData,
        .get_confidence = vtGetConfidence,
        .get_state = vtGetState,
        .reset = vtReset,
        .charset_name = vtCharsetName,
    };

    pub fn asProber(self: *EscCharSetProber) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
