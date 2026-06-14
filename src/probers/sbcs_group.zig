// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsSBCSGroupProber (.cpp/.h). Holds the 35-slot single-byte
// prober array (one nsSingleByteCharSetProber per language model, plus the
// nsHebrewProber helper at slot 10 and its two windows-1255 model probers at
// 11/12), in the EXACT order of the upstream constructor. On HandleData it
// FilterWithoutEnglishLetters the buffer once, then feeds it to every active
// sub-prober: a sub-prober reaching found_it wins (shortcut); one reaching
// not_me goes inactive; if all go inactive the group is not_me. GetConfidence
// returns the max active sub-prober confidence (recording the best guess), and
// GetCharSetName returns that best sub-prober's name (the Hebrew slots route
// through the Hebrew name prober).

const std = @import("std");
const prober = @import("../prober.zig");
const sbcs = @import("sbcs.zig");
const hebrew = @import("hebrew.zig");
const filter = @import("../filter.zig");
const tables = @import("../tables.zig");

const ProbingState = prober.ProbingState;
const SingleByteCharSetProber = sbcs.SingleByteCharSetProber;
const HebrewProber = hebrew.HebrewProber;
const sm = tables.sbcs;

/// Total slots in the SBCS prober group (nsSBCSGroupProber.h NUM_OF_SBCS_PROBERS).
pub const NUM_OF_SBCS_PROBERS: usize = 35;
/// Slot indices for the Hebrew machinery (must match the wiring below).
const HEBREW_SLOT: usize = 10;
const HEBREW_LOGICAL_SLOT: usize = 11;
const HEBREW_VISUAL_SLOT: usize = 12;

pub const SBCSGroupProber = struct {
    allocator: std.mem.Allocator,
    state: ProbingState = .detecting,

    // The 34 single-byte language probers occupy every slot except HEBREW_SLOT.
    // The slot-keyed layout (rather than a packed array) keeps indices aligned
    // with the upstream constructor exactly, so is_active[i] maps 1:1.
    sb: [NUM_OF_SBCS_PROBERS]SingleByteCharSetProber,
    heb: HebrewProber,

    is_active: [NUM_OF_SBCS_PROBERS]bool = [_]bool{true} ** NUM_OF_SBCS_PROBERS,
    active_num: u32 = NUM_OF_SBCS_PROBERS,
    best_guess: i32 = -1,

    /// Polymorphic handles to each slot's prober, (re)built per dispatch so the
    /// erased pointers always target THIS struct's current address (init returns
    /// by value). Slot HEBREW_SLOT points at `heb`; all others at `sb[i]`.
    prober_storage: [NUM_OF_SBCS_PROBERS]prober.Prober = undefined,

    /// Build the array of SingleByteCharSetProbers in the exact upstream order.
    /// The Hebrew slot (10) is left as a throwaway init(); the real Hebrew prober
    /// lives in `heb` and is substituted at proberSlice() time. Slots 11/12 are
    /// the logical/visual windows-1255 model probers (name_prober wired lazily).
    pub fn init(allocator: std.mem.Allocator) SBCSGroupProber {
        var g = SBCSGroupProber{
            .allocator = allocator,
            .sb = undefined,
            .heb = HebrewProber.init(),
        };
        const s = &g.sb;
        s[0] = SingleByteCharSetProber.init(&sm.russian.Win1251RussianModel);
        s[1] = SingleByteCharSetProber.init(&sm.russian.Koi8rRussianModel);
        s[2] = SingleByteCharSetProber.init(&sm.russian.Latin5RussianModel);
        s[3] = SingleByteCharSetProber.init(&sm.russian.MacCyrillicRussianModel);
        s[4] = SingleByteCharSetProber.init(&sm.russian.Ibm866RussianModel);
        s[5] = SingleByteCharSetProber.init(&sm.russian.Ibm855RussianModel);

        s[6] = SingleByteCharSetProber.init(&sm.greek.Iso_8859_7GreekModel);
        s[7] = SingleByteCharSetProber.init(&sm.greek.Windows_1253GreekModel);

        s[8] = SingleByteCharSetProber.init(&sm.bulgarian.Latin5BulgarianModel);
        s[9] = SingleByteCharSetProber.init(&sm.bulgarian.Win1251BulgarianModel);

        // Slot 10 is the Hebrew prober (lives in g.heb); placeholder here.
        s[HEBREW_SLOT] = SingleByteCharSetProber.init(&sm.hebrew.Win1255Model);
        // Logical Hebrew (not reversed) + Visual Hebrew (reversed). name_prober
        // wired lazily in proberSlice() (needs the moved struct's address).
        s[HEBREW_LOGICAL_SLOT] = SingleByteCharSetProber.initFull(&sm.hebrew.Win1255Model, false, null);
        s[HEBREW_VISUAL_SLOT] = SingleByteCharSetProber.initFull(&sm.hebrew.Win1255Model, true, null);

        s[13] = SingleByteCharSetProber.init(&sm.thai.Tis_620ThaiModel);
        s[14] = SingleByteCharSetProber.init(&sm.thai.Iso_8859_11ThaiModel);

        s[15] = SingleByteCharSetProber.init(&sm.french.Iso_8859_1FrenchModel);
        s[16] = SingleByteCharSetProber.init(&sm.french.Iso_8859_15FrenchModel);
        s[17] = SingleByteCharSetProber.init(&sm.french.Windows_1252FrenchModel);

        s[18] = SingleByteCharSetProber.init(&sm.spanish.Iso_8859_1SpanishModel);
        s[19] = SingleByteCharSetProber.init(&sm.spanish.Iso_8859_15SpanishModel);
        s[20] = SingleByteCharSetProber.init(&sm.spanish.Windows_1252SpanishModel);

        s[21] = SingleByteCharSetProber.init(&sm.hungarian.Iso_8859_2HungarianModel);
        s[22] = SingleByteCharSetProber.init(&sm.hungarian.Windows_1250HungarianModel);

        s[23] = SingleByteCharSetProber.init(&sm.german.Iso_8859_1GermanModel);
        s[24] = SingleByteCharSetProber.init(&sm.german.Windows_1252GermanModel);

        s[25] = SingleByteCharSetProber.init(&sm.esperanto.Iso_8859_3EsperantoModel);

        s[26] = SingleByteCharSetProber.init(&sm.turkish.Iso_8859_3TurkishModel);
        s[27] = SingleByteCharSetProber.init(&sm.turkish.Iso_8859_9TurkishModel);

        s[28] = SingleByteCharSetProber.init(&sm.arabic.Iso_8859_6ArabicModel);
        s[29] = SingleByteCharSetProber.init(&sm.arabic.Windows_1256ArabicModel);

        s[30] = SingleByteCharSetProber.init(&sm.vietnamese.VisciiVietnameseModel);
        s[31] = SingleByteCharSetProber.init(&sm.vietnamese.Windows_1258VietnameseModel);

        // ISO-8859-1 before ISO-8859-15 (ties go to the older, more common one).
        s[32] = SingleByteCharSetProber.init(&sm.danish.Iso_8859_1DanishModel);
        s[33] = SingleByteCharSetProber.init(&sm.danish.Iso_8859_15DanishModel);
        s[34] = SingleByteCharSetProber.init(&sm.danish.Windows_1252DanishModel);

        return g;
    }

    /// Wire the Hebrew prober's model-prober handles and the two model probers'
    /// name-prober handles against the CURRENT address of self, then publish all
    /// 35 polymorphic handles. Called lazily (never in init()) so erased pointers
    /// never dangle on the by-value init() return — same discipline as the
    /// dispatcher's proberSlice(). Cheap: a handful of pointer writes.
    fn proberSlice(self: *SBCSGroupProber) []prober.Prober {
        // Cross-wire Hebrew helpers (idempotent; safe to redo each dispatch).
        const heb_name = sbcs.NameProber{ .ptr = &self.heb, .charset_name = hebNameWrap };
        self.sb[HEBREW_LOGICAL_SLOT].name_prober = heb_name;
        self.sb[HEBREW_VISUAL_SLOT].name_prober = heb_name;
        self.heb.setModelProbers(
            .{ .ptr = &self.sb[HEBREW_LOGICAL_SLOT], .get_confidence = sbConfWrap, .get_state = sbStateWrap },
            .{ .ptr = &self.sb[HEBREW_VISUAL_SLOT], .get_confidence = sbConfWrap, .get_state = sbStateWrap },
        );

        var i: usize = 0;
        while (i < NUM_OF_SBCS_PROBERS) : (i += 1) {
            self.prober_storage[i] = if (i == HEBREW_SLOT)
                self.heb.asProber()
            else
                self.sb[i].asProber();
        }
        return self.prober_storage[0..];
    }

    fn hebNameWrap(ptr: *anyopaque) []const u8 {
        const h: *HebrewProber = @ptrCast(@alignCast(ptr));
        return h.charsetName();
    }
    fn sbConfWrap(ptr: *anyopaque) f32 {
        const p: *SingleByteCharSetProber = @ptrCast(@alignCast(ptr));
        return p.getConfidence();
    }
    fn sbStateWrap(ptr: *anyopaque) ProbingState {
        const p: *SingleByteCharSetProber = @ptrCast(@alignCast(ptr));
        return p.getState();
    }

    /// nsSBCSGroupProber::Reset.
    pub fn reset(self: *SBCSGroupProber) void {
        const slice = self.proberSlice();
        self.active_num = 0;
        var i: usize = 0;
        while (i < NUM_OF_SBCS_PROBERS) : (i += 1) {
            slice[i].reset();
            self.is_active[i] = true;
            self.active_num += 1;
        }
        self.best_guess = -1;
        self.state = .detecting;
    }

    /// nsSBCSGroupProber::HandleData.
    pub fn handleData(self: *SBCSGroupProber, buf: []const u8) ProbingState {
        const slice = self.proberSlice();

        // FilterWithoutEnglishLetters; on alloc failure mirror upstream's
        // graceful "goto done" (do nothing, keep current state).
        const filtered = filter.withoutEnglishLetters(self.allocator, buf) catch return self.state;
        defer self.allocator.free(filtered);
        if (filtered.len == 0) return self.state; // nothing to see here

        var i: usize = 0;
        while (i < NUM_OF_SBCS_PROBERS) : (i += 1) {
            if (!self.is_active[i]) continue;
            const st = slice[i].handleData(filtered);
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

    /// nsSBCSGroupProber::GetConfidence — max active sub-prober confidence,
    /// recording best_guess as a side effect (upstream relies on this).
    pub fn getConfidence(self: *SBCSGroupProber) f32 {
        switch (self.state) {
            .found_it => return 0.99,
            .not_me => return 0.01,
            .detecting => {
                const slice = self.proberSlice();
                var best_conf: f32 = 0.0;
                var i: usize = 0;
                while (i < NUM_OF_SBCS_PROBERS) : (i += 1) {
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

    pub fn getState(self: *SBCSGroupProber) ProbingState {
        return self.state;
    }

    /// nsSBCSGroupProber::GetCharSetName. If no best guess yet, compute one via
    /// GetConfidence; if still none, default to slot 0.
    pub fn charsetName(self: *SBCSGroupProber) []const u8 {
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

    /// Erase this group into the polymorphic Prober handle the dispatcher holds.
    pub fn asProber(self: *SBCSGroupProber) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
