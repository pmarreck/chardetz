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
// Translated to Zig from uchardetz src/nsSBCSGroupProber.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsSBCharSetProber.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsHebrewProber.cpp @ abacfc1f.

//! Single-byte charset detection: nsSingleByteCharSetProber (bigram
//! frequency model per language/charset), nsHebrewProber (logical vs visual
//! Hebrew from final-letter evidence) and nsSBCSGroupProber, which feeds all
//! 35 of them text stripped of English words.
const prober = @import("prober.zig");
const filter = @import("filter.zig");
const types = @import("tables/types.zig");
const t = @import("tables/all.zig");

const ill: u8 = 255;
const ctr: u8 = 254;
const symbol_cat_order: u8 = 250;
const sb_enough_rel_threshold = 1024;
const positive_shortcut_threshold = prober.f32FromDouble(0.95);
const negative_shortcut_threshold = prober.f32FromDouble(0.05);
const positive_cat = 3;
const probable_cat = 2;

pub const SingleByteProber = struct {
    model: *const types.SequenceModel,
    /// Look up each pair backwards (visual Hebrew over the logical model).
    reversed: bool = false,
    /// The charset name comes from the group's Hebrew prober.
    has_name_prober: bool = false,
    state: prober.State = .detecting,
    last_order: u8 = 255,
    total_seqs: u32 = 0,
    seq_counters: [4]u32 = @splat(0),
    total_char: u32 = 0,
    ctrl_char: u32 = 0,
    freq_char: u32 = 0,

    pub fn reset(self: *SingleByteProber) void {
        self.* = .{ .model = self.model, .reversed = self.reversed, .has_name_prober = self.has_name_prober };
    }

    // complexity: O(n)
    pub fn handleData(self: *SingleByteProber, buf: []const u8) prober.State {
        const fcc = self.model.freqCharCount;
        for (buf) |c| {
            const order = self.model.charToOrderMap[c];
            if (order < symbol_cat_order) {
                self.total_char += 1;
            } else if (order == ill) {
                self.state = .not_me;
                break;
            } else if (order == ctr) {
                self.ctrl_char += 1;
            }
            if (order < fcc) {
                self.freq_char += 1;
                if (self.last_order < fcc) {
                    self.total_seqs += 1;
                    const idx = if (!self.reversed)
                        @as(usize, self.last_order) * fcc + order
                    else
                        @as(usize, order) * fcc + self.last_order;
                    self.seq_counters[self.model.precedenceMatrix[idx]] += 1;
                }
            }
            self.last_order = order;
        }
        if (self.state == .detecting and self.total_seqs > sb_enough_rel_threshold) {
            const cf = self.confidence();
            if (cf > positive_shortcut_threshold) {
                self.state = .found_it;
            } else if (cf < negative_shortcut_threshold) {
                self.state = .not_me;
            }
        }
        return self.state;
    }

    /// POSITIVE_APPROACH confidence, evaluated in the same f32 operation
    /// order as upstream (including its unsigned subtraction).
    pub fn confidence(self: *const SingleByteProber) f32 {
        if (self.total_seqs == 0) return prober.f32FromDouble(0.01);
        const f = prober.f;
        var r: f32 = prober.f32FromDouble(1.0) * f(self.seq_counters[positive_cat]) / f(self.total_seqs) / self.model.mTypicalPositiveRatio;
        r = r * (f(self.seq_counters[positive_cat]) + f(self.seq_counters[probable_cat]) / 4) / f(self.total_char);
        r = r * f(self.total_char -% self.ctrl_char) / f(self.total_char);
        r = r * f(self.freq_char) / f(self.total_char);
        if (r >= prober.f32FromDouble(1.00)) r = prober.f32FromDouble(0.99);
        return r;
    }
};

const final_kaf = 0xea;
const normal_kaf = 0xeb;
const final_mem = 0xed;
const normal_mem = 0xee;
const final_nun = 0xef;
const normal_nun = 0xf0;
const final_pe = 0xf3;
const normal_pe = 0xf4;
const final_tsadi = 0xf5;
const min_final_char_distance = 5;
const min_model_distance: f64 = 0.01;
const visual_hebrew_name: [:0]const u8 = "ISO-8859-8";
const logical_hebrew_name: [:0]const u8 = "WINDOWS-1255";

fn isFinal(c: u8) bool {
    return c == final_kaf or c == final_mem or c == final_nun or c == final_pe or c == final_tsadi;
}

fn isNonFinal(c: u8) bool {
    return c == normal_kaf or c == normal_mem or c == normal_nun or c == normal_pe;
}

/// nsHebrewProber. Never identifies a charset itself (confidence 0); it names
/// the winner when one of the two windows-1255 model probers is chosen.
pub const HebrewProber = struct {
    final_char_logical_score: i32 = 0,
    final_char_visual_score: i32 = 0,
    prev: u8 = ' ',
    before_prev: u8 = ' ',

    pub fn reset(self: *HebrewProber) void {
        self.* = .{};
    }

    pub fn state(logical: *const SingleByteProber, visual: *const SingleByteProber) prober.State {
        return if (logical.state == .not_me and visual.state == .not_me) .not_me else .detecting;
    }

    // complexity: O(n)
    pub fn handleData(self: *HebrewProber, buf: []const u8, logical: *const SingleByteProber, visual: *const SingleByteProber) prober.State {
        if (state(logical, visual) == .not_me) return .not_me;
        for (buf) |cur| {
            if (cur == ' ') {
                if (self.before_prev != ' ') {
                    if (isFinal(self.prev)) {
                        self.final_char_logical_score += 1;
                    } else if (isNonFinal(self.prev)) {
                        self.final_char_visual_score += 1;
                    }
                }
            } else if (self.before_prev == ' ' and isFinal(self.prev)) {
                self.final_char_visual_score += 1;
            }
            self.before_prev = self.prev;
            self.prev = cur;
        }
        return .detecting;
    }

    pub fn charsetName(self: *const HebrewProber, logical: *const SingleByteProber, visual: *const SingleByteProber) [:0]const u8 {
        const finalsub = self.final_char_logical_score - self.final_char_visual_score;
        if (finalsub >= min_final_char_distance) return logical_hebrew_name;
        if (finalsub <= -min_final_char_distance) return visual_hebrew_name;
        // Upstream compares a float difference against a double constant.
        const modelsub: f32 = logical.confidence() - visual.confidence();
        if (@as(f64, modelsub) > min_model_distance) return logical_hebrew_name;
        if (@as(f64, modelsub) < -min_model_distance) return visual_hebrew_name;
        if (finalsub < 0) return visual_hebrew_name;
        return logical_hebrew_name;
    }
};

const num_of_sbcs_probers = 35;
const hebrew_index = 10;
const logical_index = 11;
const visual_index = 12;

const Member = union(enum) {
    single: SingleByteProber,
    hebrew: HebrewProber,
};

fn sb(model: *const types.SequenceModel) Member {
    return .{ .single = .{ .model = model } };
}

/// Upstream's member order; ties go to the earlier member.
const initial_members = [num_of_sbcs_probers]Member{
    sb(&t.lang_russian_model.Win1251RussianModel),
    sb(&t.lang_russian_model.Koi8rRussianModel),
    sb(&t.lang_russian_model.Latin5RussianModel),
    sb(&t.lang_russian_model.MacCyrillicRussianModel),
    sb(&t.lang_russian_model.Ibm866RussianModel),
    sb(&t.lang_russian_model.Ibm855RussianModel),
    sb(&t.lang_greek_model.Iso_8859_7GreekModel),
    sb(&t.lang_greek_model.Windows_1253GreekModel),
    sb(&t.lang_bulgarian_model.Latin5BulgarianModel),
    sb(&t.lang_bulgarian_model.Win1251BulgarianModel),
    .{ .hebrew = .{} },
    .{ .single = .{ .model = &t.lang_hebrew_model.Win1255Model, .has_name_prober = true } },
    .{ .single = .{ .model = &t.lang_hebrew_model.Win1255Model, .reversed = true, .has_name_prober = true } },
    sb(&t.lang_thai_model.Tis_620ThaiModel),
    sb(&t.lang_thai_model.Iso_8859_11ThaiModel),
    sb(&t.lang_french_model.Iso_8859_1FrenchModel),
    sb(&t.lang_french_model.Iso_8859_15FrenchModel),
    sb(&t.lang_french_model.Windows_1252FrenchModel),
    sb(&t.lang_spanish_model.Iso_8859_1SpanishModel),
    sb(&t.lang_spanish_model.Iso_8859_15SpanishModel),
    sb(&t.lang_spanish_model.Windows_1252SpanishModel),
    sb(&t.lang_hungarian_model.Iso_8859_2HungarianModel),
    sb(&t.lang_hungarian_model.Windows_1250HungarianModel),
    sb(&t.lang_german_model.Iso_8859_1GermanModel),
    sb(&t.lang_german_model.Windows_1252GermanModel),
    sb(&t.lang_esperanto_model.Iso_8859_3EsperantoModel),
    sb(&t.lang_turkish_model.Iso_8859_3TurkishModel),
    sb(&t.lang_turkish_model.Iso_8859_9TurkishModel),
    sb(&t.lang_arabic_model.Iso_8859_6ArabicModel),
    sb(&t.lang_arabic_model.Windows_1256ArabicModel),
    sb(&t.lang_vietnamese_model.VisciiVietnameseModel),
    sb(&t.lang_vietnamese_model.Windows_1258VietnameseModel),
    sb(&t.lang_danish_model.Iso_8859_1DanishModel),
    sb(&t.lang_danish_model.Iso_8859_15DanishModel),
    sb(&t.lang_danish_model.Windows_1252DanishModel),
};

pub const SbcsGroupProber = struct {
    members: [num_of_sbcs_probers]Member = initial_members,
    is_active: [num_of_sbcs_probers]bool = @splat(true),
    state: prober.State = .detecting,
    best_guess: i32 = -1,
    active_num: u32 = num_of_sbcs_probers,

    pub fn reset(self: *SbcsGroupProber) void {
        for (&self.members) |*m| switch (m.*) {
            inline else => |*p| p.reset(),
        };
        self.is_active = @splat(true);
        self.active_num = num_of_sbcs_probers;
        self.best_guess = -1;
        self.state = .detecting;
    }

    fn single(self: *SbcsGroupProber, i: usize) *SingleByteProber {
        return &self.members[i].single;
    }

    fn memberHandleData(self: *SbcsGroupProber, i: usize, buf: []const u8) prober.State {
        return switch (self.members[i]) {
            .single => |*p| p.handleData(buf),
            .hebrew => |*h| h.handleData(buf, self.single(logical_index), self.single(visual_index)),
        };
    }

    fn memberConfidence(self: *SbcsGroupProber, i: usize) f32 {
        return switch (self.members[i]) {
            .single => |*p| p.confidence(),
            .hebrew => 0.0,
        };
    }

    fn memberName(self: *SbcsGroupProber, i: usize) [:0]const u8 {
        const hebrew = &self.members[hebrew_index].hebrew;
        return switch (self.members[i]) {
            .single => |*p| if (p.has_name_prober)
                hebrew.charsetName(self.single(logical_index), self.single(visual_index))
            else
                p.model.charsetName,
            .hebrew => hebrew.charsetName(self.single(logical_index), self.single(visual_index)),
        };
    }

    /// `scratch` must be at least `buf.len` bytes.
    // complexity: O(n * 35)
    pub fn handleData(self: *SbcsGroupProber, buf: []const u8, scratch: []u8) prober.State {
        const n = filter.withoutEnglishLetters(buf, scratch);
        if (n == 0) return self.state;
        const filtered = scratch[0..n];
        for (0..num_of_sbcs_probers) |i| {
            if (!self.is_active[i]) continue;
            const st = self.memberHandleData(i, filtered);
            if (st == .found_it) {
                self.best_guess = @intCast(i);
                self.state = .found_it;
                break;
            } else if (st == .not_me) {
                self.is_active[i] = false;
                self.active_num -= 1;
                if (self.active_num == 0) {
                    self.state = .not_me;
                    break;
                }
            }
        }
        return self.state;
    }

    pub fn confidence(self: *SbcsGroupProber) f32 {
        switch (self.state) {
            .found_it => return prober.f32FromDouble(0.99),
            .not_me => return prober.f32FromDouble(0.01),
            .detecting => {
                var best_conf: f32 = 0.0;
                for (0..num_of_sbcs_probers) |i| {
                    if (!self.is_active[i]) continue;
                    const cf = self.memberConfidence(i);
                    if (best_conf < cf) {
                        best_conf = cf;
                        self.best_guess = @intCast(i);
                    }
                }
                return best_conf;
            },
        }
    }

    pub fn charsetName(self: *SbcsGroupProber) [:0]const u8 {
        if (self.best_guess == -1) {
            _ = self.confidence();
            if (self.best_guess == -1) self.best_guess = 0;
        }
        return self.memberName(@intCast(self.best_guess));
    }
};

test "confidence reproduces upstream's unsigned (total - ctrl) wraparound" {
    // Regression found by the June differential fuzz on `fe f0 9f 98 81`:
    // two letters (total_char = 2) and three control bytes (ctrl_char = 3) in
    // ISO-8859-7. Upstream's PRUint32 subtraction wraps, pushing r past the
    // 1.0 cap, so confidence is 0.99; a signed port would go negative.
    const std = @import("std");
    var p: SingleByteProber = .{ .model = &t.lang_greek_model.Iso_8859_7GreekModel };
    _ = p.handleData("\xfe\xf0\x9f\x98\x81");
    try std.testing.expectEqual(prober.f32FromDouble(0.99), p.confidence());
}
