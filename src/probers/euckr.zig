// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsEUCKRProber (.cpp/.h). Drives the EUC-KR coding state
// machine; each completed 2-byte char feeds an EUC-KR CharDistributionAnalysis.
// Confidence is the distribution confidence.

const std = @import("std");
const csm = @import("../coding_state_machine.zig");
const prober = @import("../prober.zig");
const tables = @import("../tables.zig");
const cda = @import("../char_distribution_analysis.zig");

const ProbingState = prober.ProbingState;

pub const EUCKRProber = struct {
    coding_sm: csm.CodingStateMachine,
    state: ProbingState = .detecting,
    dist: cda.CharDistributionAnalysis,
    last_char: [2]u8 = .{ 0, 0 },

    pub fn init() EUCKRProber {
        return .{
            .coding_sm = csm.CodingStateMachine.init(&tables.mbcs_sm.EUCKRSMModel),
            .dist = cda.CharDistributionAnalysis.init(&tables.char_distribution.EUCKRDistributionTable, .euckr),
        };
    }

    pub fn reset(self: *EUCKRProber) void {
        self.coding_sm.reset();
        self.state = .detecting;
        self.dist.reset(false);
    }

    /// nsEUCKRProber::HandleData.
    pub fn handleData(self: *EUCKRProber, buf: []const u8) ProbingState {
        if (buf.len == 0) return self.state;
        for (buf, 0..) |b, i| {
            const cs = self.coding_sm.nextState(b);
            if (cs == .its_me) {
                self.state = .found_it;
                break;
            }
            if (cs == .start) {
                const char_len = self.coding_sm.getCurrentCharLen();
                if (i == 0) {
                    self.last_char[1] = buf[0];
                    self.dist.handleOneChar(&self.last_char, char_len);
                } else {
                    self.dist.handleOneChar(buf[i - 1 ..], char_len);
                }
            }
        }
        self.last_char[0] = buf[buf.len - 1];
        if (self.state == .detecting) {
            if (self.dist.gotEnoughData() and self.getConfidence() > prober.SHORTCUT_THRESHOLD) {
                self.state = .found_it;
            }
        }
        return self.state;
    }

    pub fn getConfidence(self: *EUCKRProber) f32 {
        return self.dist.getConfidence();
    }

    pub fn getState(self: *EUCKRProber) ProbingState {
        return self.state;
    }

    pub fn charsetName(_: *EUCKRProber) []const u8 {
        return "EUC-KR";
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

    pub fn asProber(self: *EUCKRProber) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
