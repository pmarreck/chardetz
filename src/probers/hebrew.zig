// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsHebrewProber (.cpp/.h). This prober recognizes neither a
// language nor a charset on its own (GetConfidence is always 0.0); it is a
// helper consulted as the `name_prober` by the two windows-1255 model probers
// (logical + visual) in the SBCS group. It accumulates final-letter evidence
// to decide, in GetCharSetName, between Logical Hebrew (WINDOWS-1255) and
// Visual Hebrew (ISO-8859-8):
//   (1) word (>1 letter) ending in a final letter  → +logical
//   (2) word (>1 letter) ending in a non-final form → +visual (laid out backwards)
//   (3) word (>1 letter) starting with a final letter → +visual
// If the final-letter score gap is decisive it wins; otherwise the two model
// probers' confidences break the tie; otherwise it defaults to logical.

const std = @import("std");
const prober = @import("../prober.zig");

const ProbingState = prober.ProbingState;

// windows-1255 / ISO-8859-8 code points of interest (the signed C '\xNN'
// literals are these unsigned byte values).
const FINAL_KAF: u8 = 0xEA;
const NORMAL_KAF: u8 = 0xEB;
const FINAL_MEM: u8 = 0xED;
const NORMAL_MEM: u8 = 0xEE;
const FINAL_NUN: u8 = 0xEF;
const NORMAL_NUN: u8 = 0xF0;
const FINAL_PE: u8 = 0xF3;
const NORMAL_PE: u8 = 0xF4;
const FINAL_TSADI: u8 = 0xF5;
const NORMAL_TSADI: u8 = 0xF6;

/// Below this final-letter score gap, don't decide on final letters alone.
const MIN_FINAL_CHAR_DISTANCE: i32 = 5;
/// Below this model-confidence gap, don't decide on model scores at all.
const MIN_MODEL_DISTANCE: f32 = 0.01;

const VISUAL_HEBREW_NAME = "ISO-8859-8";
const LOGICAL_HEBREW_NAME = "WINDOWS-1255";

/// A handle to one of the two windows-1255 model probers, used so the Hebrew
/// prober can read their confidence/state without importing their concrete type
/// (the SBCS group owns them; this avoids a cyclic dependency).
pub const ModelProber = struct {
    ptr: *anyopaque,
    get_confidence: *const fn (ptr: *anyopaque) f32,
    get_state: *const fn (ptr: *anyopaque) ProbingState,
};

pub const HebrewProber = struct {
    final_char_logical_score: i32 = 0,
    final_char_visual_score: i32 = 0,

    // The two last characters seen in the previous buffer. Initialized to space
    // so the start of data behaves like a word delimiter.
    prev: u8 = ' ',
    before_prev: u8 = ' ',

    // The logical/visual model probers, owned by the SBCS group, wired in after
    // construction via setModelProbers.
    logical_prob: ?ModelProber = null,
    visual_prob: ?ModelProber = null,

    pub fn init() HebrewProber {
        return .{};
    }

    /// nsHebrewProber::SetModelProbers.
    pub fn setModelProbers(self: *HebrewProber, logical: ModelProber, visual: ModelProber) void {
        self.logical_prob = logical;
        self.visual_prob = visual;
    }

    fn isFinal(c: u8) bool {
        return c == FINAL_KAF or c == FINAL_MEM or c == FINAL_NUN or c == FINAL_PE or c == FINAL_TSADI;
    }

    fn isNonFinal(c: u8) bool {
        // Normal Tsadi deliberately excluded (apostrophe→space artifact); Pe/Kaf
        // kept despite rare legal word-final non-final forms.
        return c == NORMAL_KAF or c == NORMAL_MEM or c == NORMAL_NUN or c == NORMAL_PE;
    }

    /// nsHebrewProber::HandleData. Accumulates the three final-letter heuristics
    /// above. Stays in detecting until both model probers say not_me.
    pub fn handleData(self: *HebrewProber, buf: []const u8) ProbingState {
        if (self.getState() == .not_me) return .not_me;

        for (buf) |cur| {
            if (cur == ' ') {
                // A word just ended.
                if (self.before_prev != ' ') {
                    if (isFinal(self.prev)) {
                        self.final_char_logical_score += 1; // case (1)
                    } else if (isNonFinal(self.prev)) {
                        self.final_char_visual_score += 1; // case (2)
                    }
                }
            } else {
                // case (3): [-2:space][-1:final letter][cur:not space]
                if (self.before_prev == ' ' and isFinal(self.prev) and cur != ' ') {
                    self.final_char_visual_score += 1;
                }
            }
            self.before_prev = self.prev;
            self.prev = cur;
        }

        return .detecting;
    }

    /// nsHebrewProber::GetCharSetName — decide Logical vs Visual.
    pub fn charsetName(self: *HebrewProber) []const u8 {
        const finalsub = self.final_char_logical_score - self.final_char_visual_score;
        if (finalsub >= MIN_FINAL_CHAR_DISTANCE) return LOGICAL_HEBREW_NAME;
        if (finalsub <= -MIN_FINAL_CHAR_DISTANCE) return VISUAL_HEBREW_NAME;

        const log_conf = if (self.logical_prob) |p| p.get_confidence(p.ptr) else 0.0;
        const vis_conf = if (self.visual_prob) |p| p.get_confidence(p.ptr) else 0.0;
        const modelsub = log_conf - vis_conf;
        if (modelsub > MIN_MODEL_DISTANCE) return LOGICAL_HEBREW_NAME;
        if (modelsub < -MIN_MODEL_DISTANCE) return VISUAL_HEBREW_NAME;

        if (finalsub < 0) return VISUAL_HEBREW_NAME;
        return LOGICAL_HEBREW_NAME;
    }

    /// nsHebrewProber::Reset.
    pub fn reset(self: *HebrewProber) void {
        self.final_char_logical_score = 0;
        self.final_char_visual_score = 0;
        self.prev = ' ';
        self.before_prev = ' ';
    }

    /// nsHebrewProber::GetState — active while either model prober is active.
    pub fn getState(self: *HebrewProber) ProbingState {
        const log_state = if (self.logical_prob) |p| p.get_state(p.ptr) else ProbingState.not_me;
        const vis_state = if (self.visual_prob) |p| p.get_state(p.ptr) else ProbingState.not_me;
        if (log_state == .not_me and vis_state == .not_me) return .not_me;
        return .detecting;
    }

    /// nsHebrewProber::GetConfidence — always 0.0; it never identifies alone.
    pub fn getConfidence(_: *HebrewProber) f32 {
        return 0.0;
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
    pub fn asProber(self: *HebrewProber) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
