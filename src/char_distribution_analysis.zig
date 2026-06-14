// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of CharDistributionAnalysis (.cpp/.h) — the CJK confidence
// engine. It converts each completed 2-byte character into an encoding-specific
// "order" (a dense index over the encoding's character space) via a per-charset
// GetOrder byte-math function, then looks that order up in a frequency-rank
// table. Characters whose rank is < 512 are "frequent"; the ratio of frequent
// to infrequent characters (scaled by a per-charset typical-distribution ratio)
// is the confidence. Multiple encodings of one language share one frequency
// table because the order is a language-level index, not a byte pattern.

const std = @import("std");
const char_distribution = @import("char_distribution.zig");

const DistributionTable = char_distribution.DistributionTable;

/// SURE_YES 0.99f — CharDistribution.cpp. Confidence is clamped to this even
/// when the raw ratio would exceed it ("we don't want to be 100% sure").
pub const SURE_YES: f32 = 0.99;
/// SURE_NO 0.01f — CharDistribution.cpp. Returned when there is no usable data.
pub const SURE_NO: f32 = 0.01;

/// Which per-charset GetOrder byte-math to apply. Each variant is a distinct
/// CharDistributionAnalysis subclass in the upstream (Big5/GB2312/EUCTW/EUCKR/
/// SJIS/EUCJP). The order math differs per encoding; see `getOrder`.
pub const Charset = enum {
    big5,
    gb2312,
    euctw,
    euckr,
    sjis,
    eucjp,
};

/// Port of CharDistributionAnalysis. Owns the running counters and a pointer to
/// the per-charset frequency table; `getOrder` dispatches on `charset`.
pub const CharDistributionAnalysis = struct {
    table: *const DistributionTable,
    charset: Charset,

    /// PR_TRUE once a conclusion has been reached (unused by the current path
    /// but kept for fidelity; GotEnoughData is the live gate).
    done: bool = false,
    /// Number of characters whose frequency order is < 512.
    freq_chars: u32 = 0,
    /// Total characters encountered (those with a valid order).
    total_chars: u32 = 0,
    /// Hi-byte characters needed before a verdict (0 if preferred language).
    data_threshold: u32 = char_distribution.MINIMUM_DATA_THRESHOLD,

    /// CharDistributionAnalysis(): Reset(PR_FALSE). is_preferred → threshold 0.
    pub fn init(table: *const DistributionTable, charset: Charset) CharDistributionAnalysis {
        return .{ .table = table, .charset = charset };
    }

    /// nsXXXDistributionAnalysis::Reset(aIsPreferredLanguage).
    pub fn reset(self: *CharDistributionAnalysis, is_preferred: bool) void {
        self.done = false;
        self.total_chars = 0;
        self.freq_chars = 0;
        self.data_threshold = if (is_preferred) 0 else char_distribution.MINIMUM_DATA_THRESHOLD;
    }

    /// CharDistributionAnalysis::HandleOneChar. Only 2-byte chars are scored:
    /// order = GetOrder(str); if valid (>= 0) bump totalChars, and if its rank
    /// is < 512 also bump freqChars.
    pub fn handleOneChar(self: *CharDistributionAnalysis, str: []const u8, char_len: u32) void {
        const order: i32 = if (char_len == 2) self.getOrder(str) else -1;
        if (order >= 0) {
            self.total_chars += 1;
            const uorder: u32 = @intCast(order);
            // Upstream guards on `order < table_size`, but some tables declare a
            // table_size larger than the compiled char_to_freq_order array
            // (notably EUC-TW: table_size 8102 vs ~5378 entries, and orders can
            // reach ~5545). C++ reads OOB there (UB → effectively a large
            // value, never "frequent"); Zig would panic. Clamp to the actual
            // array length to reproduce the effective behavior safely.
            if (uorder < self.table.table_size and uorder < self.table.char_to_freq_order.len) {
                if (self.table.char_to_freq_order[uorder] < 512) {
                    self.freq_chars += 1;
                }
            }
        }
    }

    /// CharDistributionAnalysis::GetConfidence. With no data (or below the
    /// freq-char threshold) → SURE_NO. Otherwise r = freq / ((total-freq) *
    /// ratio), clamped to SURE_YES.
    pub fn getConfidence(self: *const CharDistributionAnalysis) f32 {
        if (self.total_chars == 0 or self.freq_chars <= self.data_threshold) {
            return SURE_NO;
        }
        if (self.total_chars != self.freq_chars) {
            const r: f32 = @as(f32, @floatFromInt(self.freq_chars)) /
                (@as(f32, @floatFromInt(self.total_chars - self.freq_chars)) *
                self.table.typical_distribution_ratio);
            if (r < SURE_YES) return r;
        }
        return SURE_YES;
    }

    /// GotEnoughData(): totalChars > ENOUGH_DATA_THRESHOLD.
    pub fn gotEnoughData(self: *const CharDistributionAnalysis) bool {
        return self.total_chars > char_distribution.ENOUGH_DATA_THRESHOLD;
    }

    /// Per-charset GetOrder. Each branch ports the corresponding subclass's
    /// byte-math from CharDistribution.h verbatim. `str` is the 2-byte char
    /// (str[0] high byte, str[1] low byte). Returns -1 for out-of-range.
    fn getOrder(self: *const CharDistributionAnalysis, str: []const u8) i32 {
        const b0: u32 = str[0];
        const b1: u32 = str[1];
        return switch (self.charset) {
            // EUC-TW: first byte >= 0xc4 → 94*(b0-0xc4) + b1 - 0xa1.
            .euctw => if (b0 >= 0xc4)
                @as(i32, @intCast(94 * (b0 - 0xc4) + b1)) - 0xa1
            else
                -1,
            // EUC-KR: first byte >= 0xb0 → 94*(b0-0xb0) + b1 - 0xa1.
            .euckr => if (b0 >= 0xb0)
                @as(i32, @intCast(94 * (b0 - 0xb0) + b1)) - 0xa1
            else
                -1,
            // GB2312: b0 >= 0xb0 AND b1 >= 0xa1 → 94*(b0-0xb0) + b1 - 0xa1.
            .gb2312 => if (b0 >= 0xb0 and b1 >= 0xa1)
                @as(i32, @intCast(94 * (b0 - 0xb0) + b1)) - 0xa1
            else
                -1,
            // Big5: b0 >= 0xa4. If b1 >= 0xa1: 157*(b0-0xa4)+b1-0xa1+63,
            // else 157*(b0-0xa4)+b1-0x40.
            .big5 => if (b0 >= 0xa4)
                (if (b1 >= 0xa1)
                    @as(i32, @intCast(157 * (b0 - 0xa4) + b1)) - 0xa1 + 63
                else
                    @as(i32, @intCast(157 * (b0 - 0xa4) + b1)) - 0x40)
            else
                -1,
            // SJIS: 0x81..0x9f → 188*(b0-0x81); 0xe0..0xef → 188*(b0-0xe0+31);
            // else -1. Then order += b1 - 0x40; if b1 > 0x7f, order--.
            .sjis => blk: {
                var order: i32 = undefined;
                if (b0 >= 0x81 and b0 <= 0x9f) {
                    order = @intCast(188 * (b0 - 0x81));
                } else if (b0 >= 0xe0 and b0 <= 0xef) {
                    order = @intCast(188 * (b0 - 0xe0 + 31));
                } else {
                    break :blk -1;
                }
                order += @as(i32, @intCast(b1)) - 0x40;
                if (b1 > 0x7f) order -= 1;
                break :blk order;
            },
            // EUC-JP: first byte >= 0xa0 → 94*(b0-0xa1) + b1 - 0xa1.
            .eucjp => if (b0 >= 0xa0)
                @as(i32, @intCast(94 * (@as(i32, @intCast(b0)) - 0xa1) + @as(i32, @intCast(b1)))) - 0xa1
            else
                -1,
        };
    }
};
