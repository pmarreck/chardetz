// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsMBCSGroupProber (.cpp/.h). Holds the 7 multibyte sub-probers
// in the EXACT upstream constructor order [UTF8, SJIS, EUCJP, GB18030, EUCKR,
// Big5, EUCTW]. Unlike the SBCS group, it does NOT filter out English letters;
// instead it slices the buffer into high-byte runs (a high byte arms a 2-byte
// keepNext window; chunks `[start, pos+1)` are fed once two non-high bytes
// follow) and feeds each chunk to every active sub-prober. A sub-prober reaching
// found_it wins (shortcut). GetConfidence returns the max sub-prober confidence
// (recording best_guess); GetCharSetName returns the best sub-prober's name.
//
// Note: HandleData never deactivates sub-probers (no eNotMe path) — faithful to
// upstream, which only deactivates them via Reset.

const std = @import("std");
const prober = @import("../prober.zig");
const utf8 = @import("utf8.zig");
const sjis = @import("sjis.zig");
const eucjp = @import("eucjp.zig");
const gb18030 = @import("gb18030.zig");
const euckr = @import("euckr.zig");
const big5 = @import("big5.zig");
const euctw = @import("euctw.zig");

const ProbingState = prober.ProbingState;
const Prober = prober.Prober;

/// NUM_OF_PROBERS — nsMBCSGroupProber.h.
pub const NUM_OF_PROBERS: usize = 7;

pub const MBCSGroupProber = struct {
    state: ProbingState = .detecting,

    // Concrete sub-probers in the upstream constructor order.
    utf8: utf8.UTF8Prober,
    sjis: sjis.SJISProber,
    eucjp: eucjp.EUCJPProber,
    gb18030: gb18030.GB18030Prober,
    euckr: euckr.EUCKRProber,
    big5: big5.Big5Prober,
    euctw: euctw.EUCTWProber,

    is_active: [NUM_OF_PROBERS]bool = [_]bool{true} ** NUM_OF_PROBERS,
    active_num: u32 = NUM_OF_PROBERS,
    best_guess: i32 = -1,
    /// Carry-over of the keepNext high-byte window across HandleData calls.
    keep_next: u32 = 0,

    /// Polymorphic handles (re)built per dispatch against the current address.
    prober_storage: [NUM_OF_PROBERS]Prober = undefined,

    pub fn init() MBCSGroupProber {
        return .{
            .utf8 = utf8.UTF8Prober.init(),
            .sjis = sjis.SJISProber.init(),
            .eucjp = eucjp.EUCJPProber.init(),
            .gb18030 = gb18030.GB18030Prober.init(),
            .euckr = euckr.EUCKRProber.init(),
            .big5 = big5.Big5Prober.init(),
            .euctw = euctw.EUCTWProber.init(),
        };
    }

    /// (Re)build the polymorphic handles in constructor order against the
    /// CURRENT address of self (init returns by value, so handles must never be
    /// captured before the struct settles). Cheap; called per dispatch.
    fn proberSlice(self: *MBCSGroupProber) []Prober {
        self.prober_storage[0] = self.utf8.asProber();
        self.prober_storage[1] = self.sjis.asProber();
        self.prober_storage[2] = self.eucjp.asProber();
        self.prober_storage[3] = self.gb18030.asProber();
        self.prober_storage[4] = self.euckr.asProber();
        self.prober_storage[5] = self.big5.asProber();
        self.prober_storage[6] = self.euctw.asProber();
        return self.prober_storage[0..];
    }

    /// nsMBCSGroupProber::Reset.
    pub fn reset(self: *MBCSGroupProber) void {
        const slice = self.proberSlice();
        self.active_num = 0;
        var i: usize = 0;
        while (i < NUM_OF_PROBERS) : (i += 1) {
            slice[i].reset();
            self.is_active[i] = true;
            self.active_num += 1;
        }
        self.best_guess = -1;
        self.state = .detecting;
        self.keep_next = 0;
    }

    /// nsMBCSGroupProber::HandleData — the incremental high-byte slicing filter.
    pub fn handleData(self: *MBCSGroupProber, buf: []const u8) ProbingState {
        const slice = self.proberSlice();
        var start: usize = 0;
        var keep_next = self.keep_next;

        var pos: usize = 0;
        while (pos < buf.len) : (pos += 1) {
            if (buf[pos] & 0x80 != 0) {
                if (keep_next == 0) start = pos;
                keep_next = 2;
            } else if (keep_next != 0) {
                keep_next -= 1;
                if (keep_next == 0) {
                    var i: usize = 0;
                    while (i < NUM_OF_PROBERS) : (i += 1) {
                        if (!self.is_active[i]) continue;
                        const st = slice[i].handleData(buf[start .. pos + 1]);
                        if (st == .found_it) {
                            self.best_guess = @intCast(i);
                            self.state = .found_it;
                            return self.state;
                        }
                    }
                }
            }
        }

        if (keep_next != 0) {
            var i: usize = 0;
            while (i < NUM_OF_PROBERS) : (i += 1) {
                if (!self.is_active[i]) continue;
                const st = slice[i].handleData(buf[start..]);
                if (st == .found_it) {
                    self.best_guess = @intCast(i);
                    self.state = .found_it;
                    return self.state;
                }
            }
        }
        self.keep_next = keep_next;
        return self.state;
    }

    /// nsMBCSGroupProber::GetConfidence — max active sub-prober confidence.
    pub fn getConfidence(self: *MBCSGroupProber) f32 {
        switch (self.state) {
            .found_it => return 0.99,
            .not_me => return 0.01,
            .detecting => {
                const slice = self.proberSlice();
                var best_conf: f32 = 0.0;
                var i: usize = 0;
                while (i < NUM_OF_PROBERS) : (i += 1) {
                    if (!self.is_active[i]) continue;
                    const cf = slice[i].getConfidence();
                    if (best_conf < cf) {
                        best_conf = cf;
                        self.best_guess = @intCast(i);
                    }
                }
                return best_conf;
            },
        }
    }

    pub fn getState(self: *MBCSGroupProber) ProbingState {
        return self.state;
    }

    /// nsMBCSGroupProber::GetCharSetName. If no best guess yet, compute one;
    /// if still none, default to slot 0 (UTF-8).
    pub fn charsetName(self: *MBCSGroupProber) []const u8 {
        if (self.best_guess == -1) {
            _ = self.getConfidence();
            if (self.best_guess == -1) self.best_guess = 0;
        }
        const slice = self.proberSlice();
        return slice[@intCast(self.best_guess)].charsetName();
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

    pub fn asProber(self: *MBCSGroupProber) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
