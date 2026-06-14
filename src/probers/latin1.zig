// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsLatin1Prober (.cpp/.h). A standalone top-level prober (slot
// [2] in nsUniversalDetector) that classifies WINDOWS-1252 / Latin-1 text by a
// fixed 8-class character model rather than a generated language model. Each
// byte maps to one of 8 classes (ASCII cap/small, accented cap/small vowel/
// other, other, undefined); the (prev,cur) class bigram is looked up in a small
// frequency table giving illegal(0)/unlikely(1)/normal(2)/likely(3). Confidence
// is the likely-bigram fraction minus 20× the unlikely fraction, halved so more
// accurate detectors win ties. An illegal bigram → not_me.

const std = @import("std");
const prober = @import("../prober.zig");
const filter = @import("../filter.zig");

const ProbingState = prober.ProbingState;

// Character classes (nsLatin1Prober.cpp).
const UDF: u8 = 0; // undefined
const OTH: u8 = 1; // other
const ASC: u8 = 2; // ascii capital letter
const ASS: u8 = 3; // ascii small letter
const ACV: u8 = 4; // accent capital vowel
const ACO: u8 = 5; // accent capital other
const ASV: u8 = 6; // accent small vowel
const ASO: u8 = 7; // accent small other
const CLASS_NUM: usize = 8;

const FREQ_CAT_NUM: usize = 4;

// 256-entry byte→class table (nsLatin1Prober.cpp Latin1_CharToClass).
const Latin1_CharToClass = [256]u8{
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // 00 - 07
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // 08 - 0F
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // 10 - 17
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // 18 - 1F
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // 20 - 27
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // 28 - 2F
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // 30 - 37
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // 38 - 3F
    OTH, ASC, ASC, ASC, ASC, ASC, ASC, ASC, // 40 - 47
    ASC, ASC, ASC, ASC, ASC, ASC, ASC, ASC, // 48 - 4F
    ASC, ASC, ASC, ASC, ASC, ASC, ASC, ASC, // 50 - 57
    ASC, ASC, ASC, OTH, OTH, OTH, OTH, OTH, // 58 - 5F
    OTH, ASS, ASS, ASS, ASS, ASS, ASS, ASS, // 60 - 67
    ASS, ASS, ASS, ASS, ASS, ASS, ASS, ASS, // 68 - 6F
    ASS, ASS, ASS, ASS, ASS, ASS, ASS, ASS, // 70 - 77
    ASS, ASS, ASS, OTH, OTH, OTH, OTH, OTH, // 78 - 7F
    OTH, UDF, OTH, ASO, OTH, OTH, OTH, OTH, // 80 - 87
    OTH, OTH, ACO, OTH, ACO, UDF, ACO, UDF, // 88 - 8F
    UDF, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // 90 - 97
    OTH, OTH, ASO, OTH, ASO, UDF, ASO, ACO, // 98 - 9F
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // A0 - A7
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // A8 - AF
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // B0 - B7
    OTH, OTH, OTH, OTH, OTH, OTH, OTH, OTH, // B8 - BF
    ACV, ACV, ACV, ACV, ACV, ACV, ACO, ACO, // C0 - C7
    ACV, ACV, ACV, ACV, ACV, ACV, ACV, ACV, // C8 - CF
    ACO, ACO, ACV, ACV, ACV, ACV, ACV, OTH, // D0 - D7
    ACV, ACV, ACV, ACV, ACV, ACO, ACO, ACO, // D8 - DF
    ASV, ASV, ASV, ASV, ASV, ASV, ASO, ASO, // E0 - E7
    ASV, ASV, ASV, ASV, ASV, ASV, ASV, ASV, // E8 - EF
    ASO, ASO, ASV, ASV, ASV, ASV, ASV, OTH, // F0 - F7
    ASV, ASV, ASV, ASV, ASV, ASO, ASO, ASO, // F8 - FF
};

// 8×8 class-bigram frequency model (nsLatin1Prober.cpp Latin1ClassModel).
// 0:illegal 1:very unlikely 2:normal 3:very likely
const Latin1ClassModel = [CLASS_NUM * CLASS_NUM]u8{
    //   UDF OTH ASC ASS ACV ACO ASV ASO
    0, 0, 0, 0, 0, 0, 0, 0, // UDF
    0, 3, 3, 3, 3, 3, 3, 3, // OTH
    0, 3, 3, 3, 3, 3, 3, 3, // ASC
    0, 3, 3, 3, 1, 1, 3, 3, // ASS
    0, 3, 3, 3, 1, 2, 1, 2, // ACV
    0, 3, 3, 3, 3, 3, 3, 3, // ACO
    0, 3, 1, 3, 1, 1, 1, 3, // ASV
    0, 3, 1, 3, 1, 1, 3, 3, // ASO
};

pub const Latin1Prober = struct {
    allocator: std.mem.Allocator,
    state: ProbingState = .detecting,
    last_char_class: u8 = OTH,
    freq_counter: [FREQ_CAT_NUM]u32 = .{ 0, 0, 0, 0 },

    pub fn init(allocator: std.mem.Allocator) Latin1Prober {
        return .{ .allocator = allocator };
    }

    /// nsLatin1Prober::Reset.
    pub fn reset(self: *Latin1Prober) void {
        self.state = .detecting;
        self.last_char_class = OTH;
        self.freq_counter = .{ 0, 0, 0, 0 };
    }

    /// nsLatin1Prober::HandleData. Filters through FilterWithEnglishLetters
    /// (falling back to the raw buffer on alloc failure, exactly like upstream),
    /// then classifies each (prev,cur) class bigram; an illegal bigram → not_me.
    pub fn handleData(self: *Latin1Prober, buf: []const u8) ProbingState {
        const filtered = filter.withEnglishLetters(self.allocator, buf) catch null;
        defer if (filtered) |f| self.allocator.free(f);
        const work: []const u8 = if (filtered) |f| f else buf;

        for (work) |b| {
            const char_class = Latin1_CharToClass[b];
            const freq = Latin1ClassModel[@as(usize, self.last_char_class) * CLASS_NUM + char_class];
            if (freq == 0) {
                self.state = .not_me;
                break;
            }
            self.freq_counter[freq] += 1;
            self.last_char_class = char_class;
        }

        return self.state;
    }

    /// nsLatin1Prober::GetConfidence.
    pub fn getConfidence(self: *Latin1Prober) f32 {
        if (self.state == .not_me) return 0.01;

        var total: u32 = 0;
        for (self.freq_counter) |c| total += c;

        var confidence: f32 = undefined;
        if (total == 0) {
            confidence = 0.0;
        } else {
            const total_f: f32 = @floatFromInt(total);
            const f3: f32 = @floatFromInt(self.freq_counter[3]);
            const f1: f32 = @floatFromInt(self.freq_counter[1]);
            confidence = f3 * 1.0 / total_f;
            confidence -= f1 * 20.0 / total_f;
        }
        if (confidence < 0.0) confidence = 0.0;
        // Lower latin1 confidence so more accurate detectors take priority.
        confidence *= 0.50;
        return confidence;
    }

    pub fn getState(self: *Latin1Prober) ProbingState {
        return self.state;
    }

    pub fn charsetName(_: *Latin1Prober) []const u8 {
        return "WINDOWS-1252";
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
    pub fn asProber(self: *Latin1Prober) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
