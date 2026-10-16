// ***** BEGIN LICENSE BLOCK *****
// Version: MPL 1.1/GPL 2.0/LGPL 2.1
//
// The contents of this file are subject to the Mozilla Public License Version
// 1.1 (the "License"); you may not use this file except in compliance with
// the License. You may obtain a copy of the License at
// http://www.mozilla.org/MPL/
//
// Software distributed under the License is distributed on an "AS IS" basis,
// WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
// for the specific language governing rights and limitations under the
// License.
//
// The Original Code is Mozilla Universal charset detector code.
//
// The Initial Developer of the Original Code is
// Netscape Communications Corporation.
// Portions created by the Initial Developer are Copyright (C) 2001
// the Initial Developer. All Rights Reserved.
//
// Contributor(s):
//          Shy Shalom <shooshX@gmail.com>
//             Proofpoint, Inc.
//
// Alternatively, the contents of this file may be used under the terms of
// either the GNU General Public License Version 2 or later (the "GPL"), or
// the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
// in which case the provisions of the GPL or the LGPL are applicable instead
// of those above. If you wish to allow use of your version of this file only
// under the terms of either the GPL or the LGPL, and not to allow others to
// use your version of this file under the terms of the MPL, indicate your
// decision by deleting the provisions above and replace them with the notice
// and other provisions required by the GPL or the LGPL. If you do not delete
// the provisions above, a recipient may use your version of this file under
// the terms of any one of the MPL, the GPL or the LGPL.
//
// ***** END LICENSE BLOCK *****
//
// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Translated to Zig from uchardetz src/nsMBCSGroupProber.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/CharDistribution.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/JpCntx.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsSJISProber.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsEUCJPProber.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsGB2312Prober.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsEUCKRProber.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsBig5Prober.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsEUCTWProber.cpp @ abacfc1f.

//! Multibyte (CJK + UTF-8) detection: per-encoding coding state machines,
//! character-frequency distribution analysis, Japanese hiragana context
//! analysis and nsMBCSGroupProber, which feeds them runs of high bytes.
const std = @import("std");
const prober = @import("prober.zig");
const types = @import("tables/types.zig");
const t = @import("tables/all.zig");
const Utf8Prober = @import("utf8_prober.zig").Utf8Prober;

const enough_data_threshold = 1024;
const minimum_data_threshold = 4;
const sure_yes: f32 = 0.99;
const sure_no: f32 = 0.01;

pub const Encoding = enum { sjis, euc_jp, gb18030, euc_kr, big5, euc_tw };

/// CharDistributionAnalysis: share of characters among the 512 most frequent.
fn Distribution(comptime enc: Encoding) type {
    const table: []const i16, const table_size: u32, const ratio: f32 = switch (enc) {
        .sjis, .euc_jp => .{ &t.jis_freq.JISCharToFreqOrder, t.jis_freq.JIS_TABLE_SIZE, t.jis_freq.JIS_TYPICAL_DISTRIBUTION_RATIO },
        .gb18030 => .{ &t.gb2312_freq.GB2312CharToFreqOrder, t.gb2312_freq.GB2312_TABLE_SIZE, t.gb2312_freq.GB2312_TYPICAL_DISTRIBUTION_RATIO },
        .euc_kr => .{ &t.euckr_freq.EUCKRCharToFreqOrder, t.euckr_freq.EUCKR_TABLE_SIZE, t.euckr_freq.EUCKR_TYPICAL_DISTRIBUTION_RATIO },
        .big5 => .{ &t.big5_freq.Big5CharToFreqOrder, t.big5_freq.BIG5_TABLE_SIZE, t.big5_freq.BIG5_TYPICAL_DISTRIBUTION_RATIO },
        .euc_tw => .{ &t.euctw_freq.EUCTWCharToFreqOrder, t.euctw_freq.EUCTW_TABLE_SIZE, t.euctw_freq.EUCTW_TYPICAL_DISTRIBUTION_RATIO },
    };
    return struct {
        const Self = @This();

        freq_chars: u32 = 0,
        total_chars: u32 = 0,
        data_threshold: u32 = minimum_data_threshold,

        fn reset(self: *Self, is_preferred_language: bool) void {
            self.total_chars = 0;
            self.freq_chars = 0;
            self.data_threshold = if (is_preferred_language) 0 else minimum_data_threshold;
        }

        fn order(s: [2]u8) i32 {
            const b0: i32 = s[0];
            const b1: i32 = s[1];
            switch (enc) {
                .euc_tw => return if (b0 >= 0xc4) 94 * (b0 - 0xc4) + b1 - 0xa1 else -1,
                .euc_kr => return if (b0 >= 0xb0) 94 * (b0 - 0xb0) + b1 - 0xa1 else -1,
                .gb18030 => return if (b0 >= 0xb0 and b1 >= 0xa1) 94 * (b0 - 0xb0) + b1 - 0xa1 else -1,
                .big5 => {
                    if (b0 < 0xa4) return -1;
                    return if (b1 >= 0xa1) 157 * (b0 - 0xa4) + b1 - 0xa1 + 63 else 157 * (b0 - 0xa4) + b1 - 0x40;
                },
                .sjis => {
                    var o: i32 = if (b0 >= 0x81 and b0 <= 0x9f)
                        188 * (b0 - 0x81)
                    else if (b0 >= 0xe0 and b0 <= 0xef)
                        188 * (b0 - 0xe0 + 31)
                    else
                        return -1;
                    o += b1 - 0x40;
                    if (b1 > 0x7f) o -= 1;
                    return o;
                },
                .euc_jp => return if (b0 >= 0xa0) 94 * (b0 - 0xa1) + b1 - 0xa1 else -1,
            }
        }

        /// `pair` is meaningful only when `char_len == 2`.
        fn handleOneChar(self: *Self, pair: [2]u8, char_len: u32) void {
            const o: i32 = if (char_len == 2) order(pair) else -1;
            if (o < 0) return;
            self.total_chars += 1;
            const idx: u32 = @intCast(o);
            // Upstream checks only the declared TABLE_SIZE. EUCTW_TABLE_SIZE
            // (8102) exceeds its array (5376 entries), so upstream reads past
            // the array there; chardetz treats such orders as infrequent.
            if (idx < table_size and idx < table.len and table[idx] < 512) self.freq_chars += 1;
        }

        fn confidence(self: *const Self) f32 {
            if (self.total_chars == 0 or self.freq_chars <= self.data_threshold) return sure_no;
            if (self.total_chars != self.freq_chars) {
                const r = prober.f(self.freq_chars) / (prober.f(self.total_chars - self.freq_chars) * ratio);
                if (r < sure_yes) return r;
            }
            return sure_yes;
        }

        fn gotEnoughData(self: *const Self) bool {
            return self.total_chars > enough_data_threshold;
        }
    };
}

const num_of_category = 6;
const enough_rel_threshold = 100;
const max_rel_threshold = 1000;
const dont_know = prober.f32FromDouble(-1);

/// JapaneseContextAnalysis: hiragana 2-character sequence plausibility.
fn JapaneseContext(comptime enc: Encoding) type {
    return struct {
        const Self = @This();

        rel_sample: [num_of_category]u32 = @splat(0),
        total_rel: u32 = 0,
        data_threshold: u32 = minimum_data_threshold,
        last_char_order: i32 = -1,
        done: bool = false,

        fn reset(self: *Self, is_preferred_language: bool) void {
            self.* = .{ .data_threshold = if (is_preferred_language) 0 else minimum_data_threshold };
        }

        fn order(s: [2]u8) i32 {
            return switch (enc) {
                .sjis => if (s[0] == 0x82 and s[1] >= 0x9f and s[1] <= 0xf1) @as(i32, s[1]) - 0x9f else -1,
                .euc_jp => if (s[0] == 0xa4 and s[1] >= 0xa1 and s[1] <= 0xf3) @as(i32, s[1]) - 0xa1 else -1,
                else => @compileError("no Japanese context for this encoding"),
            };
        }

        fn handleOneChar(self: *Self, pair: [2]u8, char_len: u32) void {
            if (self.total_rel > max_rel_threshold) self.done = true;
            if (self.done) return;
            const o: i32 = if (char_len == 2) order(pair) else -1;
            if (o != -1 and self.last_char_order != -1) {
                self.total_rel += 1;
                self.rel_sample[t.jp_cntx.jp2CharContext[@intCast(self.last_char_order)][@intCast(o)]] += 1;
            }
            self.last_char_order = o;
        }

        fn confidence(self: *const Self) f32 {
            if (self.total_rel > self.data_threshold)
                return prober.f(self.total_rel - self.rel_sample[0]) / prober.f(self.total_rel);
            return dont_know;
        }

        fn gotEnoughData(self: *const Self) bool {
            return self.total_rel > enough_rel_threshold;
        }
    };
}

/// One CJK prober (nsSJISProber, nsEUCJPProber, nsGB18030Prober,
/// nsEUCKRProber, nsBig5Prober, nsEUCTWProber): state machine validity plus
/// distribution (and, for Japanese, context) confidence.
pub fn CjkProber(comptime enc: Encoding) type {
    const has_context = enc == .sjis or enc == .euc_jp;
    const model: *const types.SMModel, const charset: [:0]const u8 = switch (enc) {
        .sjis => .{ &t.mbcs_sm.SJISSMModel, "SHIFT_JIS" },
        .euc_jp => .{ &t.mbcs_sm.EUCJPSMModel, "EUC-JP" },
        .gb18030 => .{ &t.mbcs_sm.GB18030SMModel, "GB18030" },
        .euc_kr => .{ &t.mbcs_sm.EUCKRSMModel, "EUC-KR" },
        .big5 => .{ &t.mbcs_sm.Big5SMModel, "BIG5" },
        .euc_tw => .{ &t.mbcs_sm.EUCTWSMModel, "EUC-TW" },
    };
    return struct {
        const Self = @This();
        pub const name = charset;

        sm: prober.CodingStateMachine = .init(model),
        state: prober.State = .detecting,
        context: if (has_context) JapaneseContext(enc) else void = if (has_context) .{} else {},
        distribution: Distribution(enc) = .{},
        /// Upstream never resets this across Reset(); neither do we.
        last_char: [2]u8 = .{ 0, 0 },
        is_preferred_language: bool = false,

        pub fn reset(self: *Self) void {
            self.sm.reset();
            self.state = .detecting;
            if (has_context) self.context.reset(self.is_preferred_language);
            self.distribution.reset(self.is_preferred_language);
        }

        // complexity: O(n)
        pub fn handleData(self: *Self, buf: []const u8) prober.State {
            for (buf, 0..) |c, i| {
                const coding_state = self.sm.nextState(c);
                if (coding_state == prober.sm_its_me) {
                    self.state = .found_it;
                    break;
                }
                if (coding_state == prober.sm_start) {
                    const char_len = self.sm.current_char_len;
                    // The two bytes ending at i; across a call boundary the
                    // first comes from the previous call (mLastChar).
                    const pair: [2]u8 = if (i == 0) blk: {
                        self.last_char[1] = buf[0];
                        break :blk self.last_char;
                    } else .{ buf[i - 1], buf[i] };
                    if (has_context) self.context.handleOneChar(pair, char_len);
                    self.distribution.handleOneChar(pair, char_len);
                }
            }
            self.last_char[0] = buf[buf.len - 1];
            if (self.state == .detecting) {
                const enough = if (has_context) self.context.gotEnoughData() else self.distribution.gotEnoughData();
                if (enough and self.confidence() > prober.shortcut_threshold) self.state = .found_it;
            }
            return self.state;
        }

        pub fn confidence(self: *const Self) f32 {
            const distrib_cf = self.distribution.confidence();
            if (!has_context) return distrib_cf;
            const contxt_cf = self.context.confidence();
            return if (contxt_cf > distrib_cf) contxt_cf else distrib_cf;
        }
    };
}

const num_of_probers = 7;

/// nsMBCSGroupProber with uchardet's C API language filter (NS_FILTER_ALL):
/// every member present, none a preferred language.
pub const MbcsGroupProber = struct {
    utf8: Utf8Prober = .{},
    sjis: CjkProber(.sjis) = .{},
    euc_jp: CjkProber(.euc_jp) = .{},
    gb18030: CjkProber(.gb18030) = .{},
    euc_kr: CjkProber(.euc_kr) = .{},
    big5: CjkProber(.big5) = .{},
    euc_tw: CjkProber(.euc_tw) = .{},
    is_active: [num_of_probers]bool = @splat(true),
    state: prober.State = .detecting,
    best_guess: i32 = -1,
    active_num: u32 = num_of_probers,
    keep_next: u32 = 0,

    const member_fields = [num_of_probers][]const u8{ "utf8", "sjis", "euc_jp", "gb18030", "euc_kr", "big5", "euc_tw" };

    pub fn reset(self: *MbcsGroupProber) void {
        inline for (member_fields) |field| @field(self, field).reset();
        self.is_active = @splat(true);
        self.active_num = num_of_probers;
        self.best_guess = -1;
        self.state = .detecting;
        self.keep_next = 0;
    }

    /// Feeds `buf` to each active member in order; true when one is sure.
    fn feedMembers(self: *MbcsGroupProber, buf: []const u8) bool {
        inline for (member_fields, 0..) |field, i| {
            if (self.is_active[i] and @field(self, field).handleData(buf) == .found_it) {
                self.best_guess = i;
                self.state = .found_it;
                return true;
            }
        }
        return false;
    }

    /// Members see only runs of high bytes plus the following ASCII byte;
    /// a run left open at the end of `buf` continues into the next call.
    // complexity: O(n * 7)
    pub fn handleData(self: *MbcsGroupProber, buf: []const u8) prober.State {
        var start: usize = 0;
        var keep_next = self.keep_next;
        for (buf, 0..) |c, pos| {
            if (c & 0x80 != 0) {
                if (keep_next == 0) start = pos;
                keep_next = 2;
            } else if (keep_next != 0) {
                keep_next -= 1;
                if (keep_next == 0 and self.feedMembers(buf[start .. pos + 1])) return self.state;
            }
        }
        if (keep_next != 0 and self.feedMembers(buf[start..])) return self.state;
        self.keep_next = keep_next;
        return self.state;
    }

    pub fn confidence(self: *MbcsGroupProber) f32 {
        switch (self.state) {
            .found_it => return prober.f32FromDouble(0.99),
            .not_me => return prober.f32FromDouble(0.01),
            .detecting => {
                var best_conf: f32 = 0.0;
                inline for (member_fields, 0..) |field, i| {
                    if (self.is_active[i]) {
                        const cf = @field(self, field).confidence();
                        if (best_conf < cf) {
                            best_conf = cf;
                            self.best_guess = i;
                        }
                    }
                }
                return best_conf;
            },
        }
    }

    pub fn charsetName(self: *MbcsGroupProber) [:0]const u8 {
        if (self.best_guess == -1) {
            _ = self.confidence();
            if (self.best_guess == -1) self.best_guess = 0;
        }
        inline for (member_fields, 0..) |field, i| {
            if (self.best_guess == i) return @TypeOf(@field(self, field)).name;
        }
        unreachable;
    }
};
