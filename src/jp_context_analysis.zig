// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of JapaneseContextAnalysis (JpCntx.cpp/.h) — a second confidence
// signal for the two Japanese encodings (SHIFT_JIS, EUC-JP). It looks only at
// hiragana 2-char sequences: each completed char is reduced to a hiragana
// "order" via the encoding-specific GetOrder, and every consecutive
// (lastOrder, order) pair is binned into one of NUM_OF_CATEGORY frequency
// categories via the static 83x83 jp2CharContext table. Confidence is the
// fraction of pairs that fell outside category 0 (the "never used" bucket).

const std = @import("std");
const jp_context = @import("jp_context.zig");

const ContextTable = jp_context.ContextTable;

/// DONT_KNOW (float)-1 — JpCntx.cpp. GetConfidence returns this before enough
/// data; the prober treats a negative confidence as "no signal".
pub const DONT_KNOW: f32 = -1.0;

/// Which Japanese encoding's GetOrder byte-math to apply (the two subclasses
/// SJISContextAnalysis / EUCJPContextAnalysis).
pub const Charset = enum { sjis, eucjp };

/// Port of JapaneseContextAnalysis. Accumulates per-category hiragana-bigram
/// counts in `rel_sample`; confidence is (totalRel - rel_sample[0]) / totalRel.
pub const JapaneseContextAnalysis = struct {
    table: *const ContextTable,
    charset: Charset,

    /// Per-category sequence counts (NUM_OF_CATEGORY buckets).
    rel_sample: [jp_context.NUM_OF_CATEGORY]u32 = .{ 0, 0, 0, 0, 0, 0 },
    /// Total 2-char sequences received.
    total_rel: u32 = 0,
    /// Sequences needed before a verdict (0 if preferred language).
    data_threshold: u32 = MINIMUM_DATA_THRESHOLD,
    /// Order of the previous char (-1 = none / not hiragana).
    last_char_order: i32 = -1,
    /// Bytes to skip at the start of the next buffer (mid-character carry-over).
    need_to_skip_char_num: u32 = 0,
    done: bool = false,

    /// MINIMUM_DATA_THRESHOLD 4 — JpCntx.cpp.
    pub const MINIMUM_DATA_THRESHOLD: u32 = 4;

    pub fn init(table: *const ContextTable, charset: Charset) JapaneseContextAnalysis {
        return .{ .table = table, .charset = charset };
    }

    /// JapaneseContextAnalysis::Reset(aIsPreferredLanguage).
    pub fn reset(self: *JapaneseContextAnalysis, is_preferred: bool) void {
        self.total_rel = 0;
        self.rel_sample = .{ 0, 0, 0, 0, 0, 0 };
        self.need_to_skip_char_num = 0;
        self.last_char_order = -1;
        self.done = false;
        self.data_threshold = if (is_preferred) 0 else MINIMUM_DATA_THRESHOLD;
    }

    /// JapaneseContextAnalysis::HandleOneChar (the inline form from JpCntx.h).
    /// The prober drives this per completed char with the already-known length.
    pub fn handleOneChar(self: *JapaneseContextAnalysis, str: []const u8, char_len: u32) void {
        // If we received enough data, stop here.
        if (self.total_rel > jp_context.MAX_REL_THRESHOLD) self.done = true;
        if (self.done) return;

        const order: i32 = if (char_len == 2) self.getOrderSingle(str) else -1;
        if (order != -1 and self.last_char_order != -1) {
            self.total_rel += 1;
            const cat = self.table.jis2_char_context[
                @as(usize, @intCast(self.last_char_order)) * 83 + @as(usize, @intCast(order))
            ];
            self.rel_sample[cat] += 1;
        }
        self.last_char_order = order;
    }

    /// JapaneseContextAnalysis::GetConfidence. (totalRel - rel_sample[0]) /
    /// totalRel once past the data threshold; DONT_KNOW otherwise.
    pub fn getConfidence(self: *const JapaneseContextAnalysis) f32 {
        if (self.total_rel > self.data_threshold) {
            return @as(f32, @floatFromInt(self.total_rel - self.rel_sample[0])) /
                @as(f32, @floatFromInt(self.total_rel));
        }
        return DONT_KNOW;
    }

    /// GotEnoughData(): totalRel > ENOUGH_REL_THRESHOLD.
    pub fn gotEnoughData(self: *const JapaneseContextAnalysis) bool {
        return self.total_rel > jp_context.ENOUGH_REL_THRESHOLD;
    }

    /// The one-arg GetOrder (hiragana order only) — SJISContextAnalysis /
    /// EUCJPContextAnalysis::GetOrder(const char*). Returns -1 if not hiragana.
    fn getOrderSingle(self: *const JapaneseContextAnalysis, str: []const u8) i32 {
        return switch (self.charset) {
            // SJIS: first byte '\202' (0x82), second byte 0x9f..0xf1 → b1-0x9f.
            .sjis => if (str[0] == 0x82 and str[1] >= 0x9f and str[1] <= 0xf1)
                @as(i32, @intCast(str[1])) - 0x9f
            else
                -1,
            // EUC-JP: first byte '\244' (0xa4), second byte 0xa1..0xf3 → b1-0xa1.
            .eucjp => if (str[0] == 0xa4 and str[1] >= 0xa1 and str[1] <= 0xf3)
                @as(i32, @intCast(str[1])) - 0xa1
            else
                -1,
        };
    }
};
