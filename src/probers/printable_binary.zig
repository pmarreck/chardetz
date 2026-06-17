// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
//! PRINTABLE-BINARY prober — a chardetz EXTENSION beyond uchardet. Recognizes
//! printable_binary ("PB") encoded content: a constrained UTF-8 subset built from a
//! fixed 256-glyph table (see src/printable_binary_table.zig). Validated
//! metamorphically (round-trip via PB's own encoder), NOT against the uchardet oracle.
//!
//! Heuristic (design 2026-06-15): decode the input's UTF-8 codepoints and require
//!   (A) ≥99% of codepoints are in the PB set (256 glyphs ∪ literal whitespace), AND
//!   (B) ≥10% are "distinctive" (control/punctuation/high-byte glyphs), AND
//!   (C) ≥32 codepoints seen (min-data guard).
//! Met → found_it / confidence 0.99. Otherwise ~0 confidence, so the prober is inert
//! and the rest of the detector array (UTF-8, SBCS, Latin1) decides — non-intrusion.
//! Placed at slot 0 of the detector's high-byte array so a strong PB signal pre-empts
//! the UTF-8 prober (PB is valid UTF-8 and would otherwise be reported as UTF-8).
const std = @import("std");
const prober = @import("../prober.zig");
const pbt = @import("../printable_binary_table.zig");

const ProbingState = prober.ProbingState;

/// Min decoded codepoints before any verdict (Condition C).
const MIN_DATA: u32 = 32;
/// Condition A: fraction of codepoints that must be in the PB set.
const ALLOWED_RATIO: f32 = 0.99;
/// Condition B: fraction of codepoints that must be distinctive glyphs.
const DISTINCTIVE_RATIO: f32 = 0.10;
const CONFIDENT: f32 = 0.99;

pub const PBProber = struct {
    state: ProbingState = .detecting,
    total: u32 = 0,
    in_allowed: u32 = 0,
    distinctive: u32 = 0,
    /// Carry-over bytes of a UTF-8 sequence split across handleData calls.
    pending: [4]u8 = undefined,
    pending_len: u8 = 0,

    pub fn init() PBProber {
        return .{};
    }

    pub fn reset(self: *PBProber) void {
        self.* = .{};
    }

    /// Decode codepoints from the buffer, tally membership/distinctiveness, then
    /// re-evaluate the A/B/C conditions; reaching found_it lets the detector shortcut.
    pub fn handleData(self: *PBProber, buf: []const u8) ProbingState {
        if (self.state == .found_it) return self.state;
        self.consume(buf);
        if (self.conditionsMet()) self.state = .found_it;
        return self.state;
    }

    fn classifyCp(self: *PBProber, cp: u21) void {
        self.total += 1;
        if (pbt.lookup(cp)) |dist| {
            self.in_allowed += 1;
            if (dist) self.distinctive += 1;
        }
    }

    /// UTF-8 decode `pending ++ buf` codepoint by codepoint, classifying each and
    /// carrying any trailing incomplete sequence into `pending`. Invalid bytes count
    /// as one out-of-set codepoint (they push the in-set ratio below 99%).
    fn consume(self: *PBProber, buf: []const u8) void {
        var i: usize = 0;
        // Complete a carried-over sequence first.
        if (self.pending_len > 0) {
            const need = std.unicode.utf8ByteSequenceLength(self.pending[0]) catch 1;
            while (self.pending_len < need and i < buf.len) {
                self.pending[self.pending_len] = buf[i];
                self.pending_len += 1;
                i += 1;
            }
            if (self.pending_len < need) return; // still incomplete; await more bytes
            if (std.unicode.utf8Decode(self.pending[0..need])) |cp| {
                self.classifyCp(cp);
            } else |_| {
                self.total += 1; // invalid → out-of-set
            }
            self.pending_len = 0;
        }
        // Process the remainder of buf.
        while (i < buf.len) {
            const need = std.unicode.utf8ByteSequenceLength(buf[i]) catch {
                self.total += 1; // invalid lead byte → out-of-set, skip 1
                i += 1;
                continue;
            };
            if (i + need > buf.len) {
                const rem = buf.len - i;
                @memcpy(self.pending[0..rem], buf[i..]);
                self.pending_len = @intCast(rem);
                return;
            }
            if (std.unicode.utf8Decode(buf[i .. i + need])) |cp| {
                self.classifyCp(cp);
            } else |_| {
                self.total += 1; // invalid sequence → out-of-set
                i += 1;
                continue;
            }
            i += need;
        }
    }

    fn conditionsMet(self: *const PBProber) bool {
        if (self.total < MIN_DATA) return false;
        const total_f: f32 = @floatFromInt(self.total);
        const allowed_ok = @as(f32, @floatFromInt(self.in_allowed)) >= ALLOWED_RATIO * total_f;
        const distinctive_ok = @as(f32, @floatFromInt(self.distinctive)) >= DISTINCTIVE_RATIO * total_f;
        return allowed_ok and distinctive_ok;
    }

    /// 0.99 when the PB conditions hold, else ~0 so the prober cannot win the
    /// detector's dataEnd argmax when the signal is weak.
    pub fn getConfidence(self: *PBProber) f32 {
        return if (self.state == .found_it or self.conditionsMet()) CONFIDENT else 0.0;
    }

    pub fn getState(self: *PBProber) ProbingState {
        return self.state;
    }

    pub fn charsetName(_: *PBProber) []const u8 {
        return "PRINTABLE-BINARY";
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

    /// Erase this prober into the polymorphic Prober handle the detector holds.
    pub fn asProber(self: *PBProber) prober.Prober {
        return .{ .ptr = self, .vtable = &vtable };
    }
};
