// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsEUCJPProber (.cpp/.h). Drives the EUC-JP coding state machine
// and feeds each completed char to BOTH an EUC-JP CharDistributionAnalysis and
// an EUC-JP JapaneseContextAnalysis. Confidence is the MAX of the two. Unlike
// SJIS, both analyzers receive the same slice (`mLastChar` at i==0, `aBuf+i-1`
// otherwise) — EUC-JP's lead byte and hiragana alignment coincide.

const std = @import("std");
const csm = @import("../coding_state_machine.zig");
const prober = @import("../prober.zig");
const tables = @import("../tables.zig");
const cda = @import("../char_distribution_analysis.zig");
const jca = @import("../jp_context_analysis.zig");

const ProbingState = prober.ProbingState;

pub const EUCJPProber = struct {
    coding_sm: csm.CodingStateMachine,
    state: ProbingState = .detecting,
    ctx: jca.JapaneseContextAnalysis,
    dist: cda.CharDistributionAnalysis,
    last_char: [2]u8 = .{ 0, 0 },

    pub fn init() EUCJPProber {
        return .{
            .coding_sm = csm.CodingStateMachine.init(&tables.mbcs_sm.EUCJPSMModel),
            .ctx = jca.JapaneseContextAnalysis.init(&tables.jp_context.jp2_context, .eucjp),
            .dist = cda.CharDistributionAnalysis.init(&tables.char_distribution.JISDistributionTable, .eucjp),
        };
    }

    pub fn reset(self: *EUCJPProber) void {
        self.coding_sm.reset();
        self.state = .detecting;
        self.ctx.reset(false);
        self.dist.reset(false);
    }

    /// nsEUCJPProber::HandleData.
    pub fn handleData(self: *EUCJPProber, buf: []const u8) ProbingState {
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
                    self.ctx.handleOneChar(&self.last_char, char_len);
                    self.dist.handleOneChar(&self.last_char, char_len);
                } else {
                    self.ctx.handleOneChar(buf[i - 1 ..], char_len);
                    self.dist.handleOneChar(buf[i - 1 ..], char_len);
                }
            }
        }
        self.last_char[0] = buf[buf.len - 1];
        if (self.state == .detecting) {
            if (self.ctx.gotEnoughData() and self.getConfidence() > prober.SHORTCUT_THRESHOLD) {
                self.state = .found_it;
            }
        }
        return self.state;
    }

    /// nsEUCJPProber::GetConfidence — max(context, distribution).
    pub fn getConfidence(self: *EUCJPProber) f32 {
        const ctx_cf = self.ctx.getConfidence();
        const dist_cf = self.dist.getConfidence();
        return if (ctx_cf > dist_cf) ctx_cf else dist_cf;
    }

    pub fn getState(self: *EUCJPProber) ProbingState {
        return self.state;
    }

    pub fn charsetName(_: *EUCJPProber) []const u8 {
        return "EUC-JP";
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

    pub fn asProber(self: *EUCJPProber) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
