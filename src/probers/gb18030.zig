// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsGB18030Prober (nsGB2312Prober.cpp/.h). GB18030 is a superset
// of GB2312, so the prober drives the GB18030 coding state machine but scores
// chars with the GB2312 CharDistributionAnalysis. Confidence is the
// distribution confidence; the reported charset name is "GB18030".

const std = @import("std");
const csm = @import("../coding_state_machine.zig");
const prober = @import("../prober.zig");
const tables = @import("../tables.zig");
const cda = @import("../char_distribution_analysis.zig");

const ProbingState = prober.ProbingState;

pub const GB18030Prober = struct {
    coding_sm: csm.CodingStateMachine,
    state: ProbingState = .detecting,
    dist: cda.CharDistributionAnalysis,
    last_char: [2]u8 = .{ 0, 0 },

    pub fn init() GB18030Prober {
        return .{
            .coding_sm = csm.CodingStateMachine.init(&tables.mbcs_sm.GB18030SMModel),
            .dist = cda.CharDistributionAnalysis.init(&tables.char_distribution.GB2312DistributionTable, .gb2312),
        };
    }

    pub fn reset(self: *GB18030Prober) void {
        self.coding_sm.reset();
        self.state = .detecting;
        self.dist.reset(false);
    }

    /// nsGB18030Prober::HandleData.
    pub fn handleData(self: *GB18030Prober, buf: []const u8) ProbingState {
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

    pub fn getConfidence(self: *GB18030Prober) f32 {
        return self.dist.getConfidence();
    }

    pub fn getState(self: *GB18030Prober) ProbingState {
        return self.state;
    }

    pub fn charsetName(_: *GB18030Prober) []const u8 {
        return "GB18030";
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

    pub fn asProber(self: *GB18030Prober) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
