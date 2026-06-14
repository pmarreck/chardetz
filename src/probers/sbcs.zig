// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsSingleByteCharSetProber (.cpp/.h). A generic single-byte
// charset prober parameterized by a *const SequenceModel. It maps each input
// byte through the model's char_to_order_map, indexes the precedence_matrix on
// the (prev,cur) order bigram to bucket it into one of four sequence
// categories, and derives confidence from the positive/probable sequence ratio
// scaled by the model's typical-positive-ratio and the frequent-char fraction.
//
// Optionally takes a `reversed` flag (visual Hebrew, which reuses the logical
// windows-1255 model with the bigram lookup transposed) and a `name_prober`
// (the nsHebrewProber, which makes the final ISO-8859-8-vs-WINDOWS-1255 call).

const std = @import("std");
const prober = @import("../prober.zig");
const sbcs_model = @import("../sbcs_model.zig");

const ProbingState = prober.ProbingState;
const SequenceModel = sbcs_model.SequenceModel;

// ── nsSBCharSetProber.h constants ───────────────────────────────────────────
/// Once mTotalSeqs exceeds this, the prober may shortcut to found_it/not_me.
const SB_ENOUGH_REL_THRESHOLD: u32 = 1024;
/// Confidence above which the prober is sure it IS this charset.
const POSITIVE_SHORTCUT_THRESHOLD: f32 = 0.95;
/// Confidence below which the prober is sure it is NOT this charset.
const NEGATIVE_SHORTCUT_THRESHOLD: f32 = 0.05;
/// Order values >= this are symbols/punctuation, not word characters.
const SYMBOL_CAT_ORDER: u8 = 250;

/// Number of bigram sequence categories the precedence matrix buckets into.
const NUMBER_OF_SEQ_CAT: usize = 4;
/// Bigram category indices (nsSBCharSetProber.h). POSITIVE = most likely.
const POSITIVE_CAT: usize = NUMBER_OF_SEQ_CAT - 1; // 3
const PROBABLE_CAT: usize = NUMBER_OF_SEQ_CAT - 2; // 2
const NEUTRAL_CAT: usize = NUMBER_OF_SEQ_CAT - 3; // 1
const NEGATIVE_CAT: usize = 0;

/// An optional auxiliary prober consulted for the final charset name. The SBCS
/// group wires the nsHebrewProber here for the two windows-1255 model probers.
pub const NameProber = struct {
    ptr: *anyopaque,
    charset_name: *const fn (ptr: *anyopaque) []const u8,
};

/// Port of nsSingleByteCharSetProber. Stateless w.r.t. allocation: HandleData
/// does no I/O and no allocation (the SBCS group filters the buffer before
/// feeding it here, so this prober just consumes pre-filtered high-ASCII text).
pub const SingleByteCharSetProber = struct {
    model: *const SequenceModel,
    reversed: bool,
    name_prober: ?NameProber,

    state: ProbingState = .detecting,
    /// Char order of the last character seen.
    last_order: u8 = 255,

    total_seqs: u32 = 0,
    seq_counters: [NUMBER_OF_SEQ_CAT]u32 = .{ 0, 0, 0, 0 },

    total_char: u32 = 0,
    ctrl_char: u32 = 0,
    /// Characters that fall in our sampling (frequent-char) range.
    freq_char: u32 = 0,

    /// Plain single-byte prober over `model` (not reversed, no name prober).
    pub fn init(model: *const SequenceModel) SingleByteCharSetProber {
        return .{ .model = model, .reversed = false, .name_prober = null };
    }

    /// nsSingleByteCharSetProber(model, reversed, nameProber). Used for the two
    /// Hebrew model probers (logical = not reversed, visual = reversed).
    pub fn initFull(model: *const SequenceModel, reversed: bool, name_prober: ?NameProber) SingleByteCharSetProber {
        return .{ .model = model, .reversed = reversed, .name_prober = name_prober };
    }

    /// nsSingleByteCharSetProber::Reset.
    pub fn reset(self: *SingleByteCharSetProber) void {
        self.state = .detecting;
        self.last_order = 255;
        self.seq_counters = .{ 0, 0, 0, 0 };
        self.total_seqs = 0;
        self.total_char = 0;
        self.ctrl_char = 0;
        self.freq_char = 0;
    }

    /// nsSingleByteCharSetProber::HandleData. For each byte: map to its order;
    /// count word chars / illegal (→not_me) / control chars; when both this and
    /// the previous order are within freq_char_count, classify the bigram via
    /// the precedence matrix (transposed when reversed) and bump that category.
    /// After the buffer, once enough sequences are seen, shortcut on a confident
    /// positive (found_it) or strongly negative (not_me) confidence.
    pub fn handleData(self: *SingleByteCharSetProber, buf: []const u8) ProbingState {
        const freq_count: u8 = @intCast(self.model.freq_char_count);
        for (buf) |b| {
            const order = self.model.char_to_order_map[b];

            if (order < SYMBOL_CAT_ORDER) {
                self.total_char += 1;
            } else if (order == sbcs_model.ILL) {
                // Illegal codepoint for this charset — bail immediately.
                self.state = .not_me;
                break;
            } else if (order == sbcs_model.CTR) {
                self.ctrl_char += 1;
            }

            if (order < freq_count) {
                self.freq_char += 1;

                if (self.last_order < freq_count) {
                    self.total_seqs += 1;
                    const idx: usize = if (!self.reversed)
                        @as(usize, self.last_order) * self.model.freq_char_count + order
                    else
                        @as(usize, order) * self.model.freq_char_count + self.last_order;
                    self.seq_counters[self.model.precedence_matrix[idx]] += 1;
                }
            }
            self.last_order = order;
        }

        if (self.state == .detecting) {
            if (self.total_seqs > SB_ENOUGH_REL_THRESHOLD) {
                const cf = self.getConfidence();
                if (cf > POSITIVE_SHORTCUT_THRESHOLD) {
                    self.state = .found_it;
                } else if (cf < NEGATIVE_SHORTCUT_THRESHOLD) {
                    self.state = .not_me;
                }
            }
        }
        return self.state;
    }

    /// nsSingleByteCharSetProber::GetConfidence (POSITIVE_APPROACH). The base
    /// ratio is positive-sequences / total-sequences normalized by the model's
    /// typical-positive-ratio; it is then scaled by the positive(+¼ probable)
    /// per-char density, the non-control fraction, and the frequent-char
    /// fraction, capped at 0.99. Distinguishes close winners by rewarding
    /// charsets whose added codepoints actually form positive sequences.
    pub fn getConfidence(self: *SingleByteCharSetProber) f32 {
        if (self.total_seqs > 0) {
            const total_seqs_f: f32 = @floatFromInt(self.total_seqs);
            const total_char_f: f32 = @floatFromInt(self.total_char);
            const pos_f: f32 = @floatFromInt(self.seq_counters[POSITIVE_CAT]);
            const prob_f: f32 = @floatFromInt(self.seq_counters[PROBABLE_CAT]);
            const ctrl_f: f32 = @floatFromInt(self.ctrl_char);
            const freq_f: f32 = @floatFromInt(self.freq_char);

            var r: f32 = @as(f32, 1.0) * pos_f / total_seqs_f / self.model.typical_positive_ratio;
            r = r * (pos_f + prob_f / 4.0) / total_char_f;
            r = r * (total_char_f - ctrl_f) / total_char_f;
            r = r * freq_f / total_char_f;
            if (r >= 1.00) r = 0.99;
            return r;
        }
        return 0.01;
    }

    pub fn getState(self: *SingleByteCharSetProber) ProbingState {
        return self.state;
    }

    /// nsSingleByteCharSetProber::GetCharSetName — the name prober (Hebrew) wins
    /// if present, else the model's own charset name.
    pub fn charsetName(self: *SingleByteCharSetProber) []const u8 {
        if (self.name_prober) |np| return np.charset_name(np.ptr);
        return self.model.charset_name;
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

    /// Erase this prober into the polymorphic Prober handle.
    pub fn asProber(self: *SingleByteCharSetProber) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
