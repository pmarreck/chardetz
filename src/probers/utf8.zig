// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsUTF8Prober (.cpp/.h). Drives the UTF8 coding state machine
// over the input, counting completed multibyte characters; confidence rises
// geometrically with the count of multibyte chars (each one is strong evidence
// of genuine UTF-8), saturating once at least 6 have been seen.

const std = @import("std");
const state_machine = @import("../state_machine.zig");
const csm = @import("../coding_state_machine.zig");
const prober = @import("../prober.zig");
const tables = @import("../tables.zig");

const SMState = csm.SMState;
const ProbingState = prober.ProbingState;

/// #define ONE_CHAR_PROB (float)0.50 — nsUTF8Prober.cpp.
const ONE_CHAR_PROB: f32 = 0.50;

/// Port of nsUTF8Prober. Owns a CodingStateMachine bound to the UTF8SMModel and
/// a running count of multibyte characters; GetConfidence/HandleData reproduce
/// the upstream formulas byte-for-byte.
pub const UTF8Prober = struct {
    coding_sm: csm.CodingStateMachine,
    state: ProbingState = .detecting,
    num_mb_char: u32 = 0,

    pub fn init() UTF8Prober {
        return .{ .coding_sm = csm.CodingStateMachine.init(&tables.mbcs_sm.UTF8SMModel) };
    }

    /// nsUTF8Prober::Reset.
    pub fn reset(self: *UTF8Prober) void {
        self.coding_sm.reset();
        self.num_mb_char = 0;
        self.state = .detecting;
    }

    /// nsUTF8Prober::HandleData. For each byte: advance the SM; on eItsMe the
    /// prober is sure (found_it); on completing a char (back to start) with a
    /// multibyte length, bump the multibyte counter. After the loop, if still
    /// detecting and confidence cleared SHORTCUT_THRESHOLD, shortcut to found_it.
    pub fn handleData(self: *UTF8Prober, buf: []const u8) ProbingState {
        for (buf) |b| {
            const coding_state = self.coding_sm.nextState(b);
            if (coding_state == .its_me) {
                self.state = .found_it;
                break;
            }
            if (coding_state == .start) {
                if (self.coding_sm.getCurrentCharLen() >= 2) {
                    self.num_mb_char += 1;
                }
            }
        }

        if (self.state == .detecting) {
            if (self.getConfidence() > prober.SHORTCUT_THRESHOLD) {
                self.state = .found_it;
            }
        }
        return self.state;
    }

    /// nsUTF8Prober::GetConfidence. unlike starts at 0.99 and is halved once per
    /// multibyte char (capped at 6); confidence is 1 - unlike, so each multibyte
    /// char roughly halves the remaining doubt. ≥6 multibyte chars saturates at
    /// 0.99.
    pub fn getConfidence(self: *UTF8Prober) f32 {
        var unlike: f32 = 0.99;
        if (self.num_mb_char < 6) {
            var i: u32 = 0;
            while (i < self.num_mb_char) : (i += 1) {
                unlike *= ONE_CHAR_PROB;
            }
            return 1.0 - unlike;
        } else {
            return 0.99;
        }
    }

    pub fn getState(self: *UTF8Prober) ProbingState {
        return self.state;
    }

    pub fn charsetName(_: *UTF8Prober) []const u8 {
        return "UTF-8";
    }

    // ── Prober vtable glue ──────────────────────────────────────────────────
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

    /// Erase this prober into the polymorphic Prober handle the dispatcher holds.
    pub fn asProber(self: *UTF8Prober) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
