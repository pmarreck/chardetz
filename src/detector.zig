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
// Translated to Zig from uchardetz src/nsUniversalDetector.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/uchardet.cpp @ abacfc1f.

//! nsUniversalDetector plus uchardet.cpp's handle semantics: a streaming
//! detector fed with `handleData`, finished with `dataEnd`, read with
//! `charset`. All probers live inline; the only allocation is one scratch
//! buffer for filtered text, grown to the largest chunk seen and reused.
const std = @import("std");
const prober = @import("prober.zig");
const MbcsGroupProber = @import("mbcs.zig").MbcsGroupProber;
const SbcsGroupProber = @import("sbcs.zig").SbcsGroupProber;
const Latin1Prober = @import("latin1_prober.zig").Latin1Prober;
const EscProber = @import("esc_prober.zig").EscProber;
const PBProber = @import("printable_binary_prober.zig").PBProber;

const minimum_threshold = prober.f32FromDouble(0.20);
const esc: u8 = 0x1b;
const nbsp: u8 = 0xa0;

const InputState = enum { pure_ascii, esc_ascii, highbyte };

/// Compile-time switches for chardetz's corrections to uchardet behavior.
/// Each is documented with its rationale and tests in docs/ACCURACY.md.
/// `Fixes.none` reproduces uchardet exactly and is what the oracle gates run.
pub const Fixes = struct {
    /// Feed the probers fixed `block_len` blocks however the caller splits
    /// the input, so the answer depends only on the bytes. Upstream checks
    /// byte-order marks and BOM-less UTF-16 only in the first chunk, and
    /// probers stop early per chunk, so small chunks change its answer.
    fixed_blocks: bool = true,
    /// Withdraw the provisional ASCII (or ISO-8859-1) verdict when high bytes
    /// arrive in a later chunk. Upstream keeps it, so any input whose first
    /// chunk is plain ASCII is reported as ASCII unless a prober becomes
    /// certain on its own.
    revisable_ascii: bool = true,
    /// Report UTF-8 for input that is entirely valid UTF-8 and contains
    /// multibyte characters. Upstream weighs UTF-8 by a confidence that
    /// grows with the number of multibyte characters (0.75 for two), so a
    /// single-byte language model often wins on short text. Text in a
    /// single-byte charset almost never forms valid multibyte UTF-8 by
    /// accident. Never overrides a byte-order mark, an escape-sequence or
    /// other certain verdict, or PRINTABLE-BINARY.
    valid_utf8: bool = true,

    pub const none: Fixes = .{ .fixed_blocks = false, .revisable_ascii = false, .valid_utf8 = false };
};

/// Block size for `Fixes.fixed_blocks`: the size uchardet's own command-line
/// tool and test runner read, against which its corpus labels were set.
pub const block_len = 65536;

/// The detector chardetz ships: every accuracy fix on.
pub const Detector = DetectorWith(.{});
/// Bug-for-bug uchardet, for the differential oracle gates.
pub const UpstreamDetector = DetectorWith(Fixes.none);

/// One detector implementation; `fixes` selects upstream or corrected behavior.
pub fn DetectorWith(comptime fixes: Fixes) type {
    return struct {
        const Self = @This();
        gpa: std.mem.Allocator,
        scratch: std.ArrayList(u8) = .empty,
        /// Bytes waiting to complete a block (`Fixes.fixed_blocks` only).
        pending: std.ArrayList(u8) = .empty,

        input_state: InputState = .pure_ascii,
        nbsp_found: bool = false,
        done: bool = false,
        start: bool = true,
        got_data: bool = false,
        last_char: u8 = 0,
        detected: ?[:0]const u8 = null,
        /// What uchardet_get_charset returns (HandleUniversalDetector::m_charset).
        reported: ?[:0]const u8 = null,

        /// chardetz extension (not in uchardet): recognizes printable-binary text.
        /// Inert unless its signal is strong, and checked first because such text
        /// is also valid UTF-8.
        pb: PBProber = .{},
        mbcs: MbcsGroupProber = .{},
        sbcs: SbcsGroupProber = .{},
        latin1: Latin1Prober = .{},
        /// Upstream deletes the escape prober at the first high byte and
        /// recreates it on demand; `esc_alive` mirrors that lifetime.
        esc: EscProber = .{},
        esc_alive: bool = false,
        /// `Fixes.valid_utf8` only.
        utf8: Utf8Validator = .{},

        pub fn init(gpa: std.mem.Allocator) Self {
            return .{ .gpa = gpa };
        }

        pub fn deinit(self: *Self) void {
            self.scratch.deinit(self.gpa);
            self.pending.deinit(self.gpa);
            self.* = undefined;
        }

        pub fn reset(self: *Self) void {
            self.nbsp_found = false;
            self.done = false;
            self.input_state = .pure_ascii;
            self.start = true;
            self.detected = null;
            self.got_data = false;
            self.last_char = 0;
            self.utf8 = .{};
            self.pending.clearRetainingCapacity();
            if (self.esc_alive) self.esc.reset();
            self.pb.reset();
            self.mbcs.reset();
            self.sbcs.reset();
            self.latin1.reset();
            self.reported = "";
        }

        /// Feeds the next chunk. With `Fixes.fixed_blocks` the bytes are
        /// regrouped into `block_len` blocks, so the result does not depend on
        /// how the input is split; otherwise results depend on chunk boundaries
        /// exactly as uchardet's do (byte-order marks are only checked in the
        /// first chunk, for example). Fails only if a buffer cannot grow, in
        /// which case no detector state has changed.
        // complexity: O(n)
        pub fn handleData(self: *Self, buf: []const u8) error{OutOfMemory}!void {
            if (self.done) return;
            if (!fixes.fixed_blocks) {
                try self.scratch.ensureTotalCapacity(self.gpa, buf.len);
                return self.process(buf);
            }
            const needed = @min(block_len, self.pending.items.len + buf.len);
            try self.pending.ensureTotalCapacity(self.gpa, needed);
            try self.scratch.ensureTotalCapacity(self.gpa, needed);
            var rest = buf;
            if (self.pending.items.len > 0) {
                const take = @min(rest.len, block_len - self.pending.items.len);
                self.pending.appendSliceAssumeCapacity(rest[0..take]);
                rest = rest[take..];
                if (self.pending.items.len < block_len) return;
                self.process(self.pending.items);
                self.pending.clearRetainingCapacity();
            }
            while (rest.len >= block_len and !self.done) : (rest = rest[block_len..]) self.process(rest[0..block_len]);
            if (!self.done) self.pending.appendSliceAssumeCapacity(rest);
        }

        /// nsUniversalDetector::HandleData for one chunk. The scratch buffer
        /// must already hold `buf.len` bytes.
        fn process(self: *Self, buf: []const u8) void {
            if (self.done) return;
            if (buf.len > 0) self.got_data = true;
            if (fixes.valid_utf8) self.utf8.feed(buf);

            if (self.start) {
                self.start = false;
                if (detectBom(buf)) |name| {
                    self.detected = name;
                    self.done = true;
                    return;
                }
                if (detectBomlessUtf16(buf)) |name| {
                    self.detected = name;
                    self.done = true;
                    return;
                }
            }

            for (buf) |c| {
                if (c & 0x80 != 0 and c != nbsp) {
                    if (self.input_state != .highbyte) {
                        self.input_state = .highbyte;
                        if (fixes.revisable_ascii) self.detected = null;
                        self.esc_alive = false;
                    }
                } else {
                    if (c == nbsp) {
                        self.nbsp_found = true;
                    } else if (self.input_state == .pure_ascii and (c == esc or (c == '{' and self.last_char == '~'))) {
                        self.input_state = .esc_ascii;
                    }
                    self.last_char = c;
                }
            }

            switch (self.input_state) {
                .esc_ascii => {
                    if (!self.esc_alive) {
                        self.esc.reset();
                        self.esc_alive = true;
                    }
                    if (self.esc.handleData(buf) == .found_it) {
                        self.done = true;
                        self.detected = self.esc.detected;
                    } else if (self.nbsp_found) {
                        self.detected = "ISO-8859-1";
                    } else {
                        self.detected = "ASCII";
                    }
                },
                .highbyte => {
                    const scratch = self.scratch.allocatedSlice()[0..buf.len];
                    if (self.pb.handleData(buf) == .found_it) return self.found(PBProber.name);
                    if (self.mbcs.handleData(buf) == .found_it) return self.found(self.mbcs.charsetName());
                    if (self.sbcs.handleData(buf, scratch) == .found_it) return self.found(self.sbcs.charsetName());
                    if (self.latin1.handleData(buf, scratch) == .found_it) return self.found(Latin1Prober.name);
                },
                .pure_ascii => self.detected = if (self.nbsp_found) "ISO-8859-1" else "ASCII",
            }
        }

        fn found(self: *Self, name: [:0]const u8) void {
            self.done = true;
            self.detected = name;
        }

        pub fn dataEnd(self: *Self) void {
            if (fixes.fixed_blocks and self.pending.items.len > 0) {
                self.process(self.pending.items);
                self.pending.clearRetainingCapacity();
            }
            if (!self.got_data) return;
            if (self.detected) |name| {
                self.done = true;
                self.reported = name;
                return;
            }
            if (self.input_state != .highbyte) return;
            const confidences = [4]f32{ self.pb.confidence(), self.mbcs.confidence(), self.sbcs.confidence(), self.latin1.confidence() };
            var max_conf: f32 = 0.0;
            var max_prober: usize = 0;
            for (confidences, 0..) |cf, i| {
                if (cf > max_conf) {
                    max_conf = cf;
                    max_prober = i;
                }
            }
            if (fixes.valid_utf8 and self.utf8.multibyteText() and !(max_prober == 0 and max_conf > minimum_threshold)) {
                self.reported = "UTF-8";
                return;
            }
            if (max_conf > minimum_threshold) self.reported = switch (max_prober) {
                0 => PBProber.name,
                1 => self.mbcs.charsetName(),
                2 => self.sbcs.charsetName(),
                else => Latin1Prober.name,
            };
        }

        /// uchardet_get_charset: "" until something has been reported.
        pub fn charset(self: *const Self) [:0]const u8 {
            return self.reported orelse "";
        }
    };
}

/// Strict streaming UTF-8 validation (RFC 3629: no overlong forms, surrogates
/// or codepoints past U+10FFFF) across chunk boundaries, counting complete
/// multibyte sequences. Backs `Fixes.valid_utf8`.
const Utf8Validator = struct {
    valid: bool = true,
    /// Continuation bytes still expected in the current sequence.
    need: u2 = 0,
    /// Allowed range of the next continuation byte (narrower after E0, ED, F0, F4).
    lo: u8 = 0x80,
    hi: u8 = 0xBF,
    multibyte: usize = 0,

    fn feed(v: *Utf8Validator, buf: []const u8) void {
        if (!v.valid) return;
        for (buf) |b| {
            if (v.need > 0) {
                if (b < v.lo or b > v.hi) {
                    v.valid = false;
                    return;
                }
                v.lo = 0x80;
                v.hi = 0xBF;
                v.need -= 1;
                if (v.need == 0) v.multibyte += 1;
            } else switch (b) {
                0x00...0x7F => {},
                0xC2...0xDF => v.need = 1,
                0xE0...0xEF => {
                    v.need = 2;
                    if (b == 0xE0) v.lo = 0xA0;
                    if (b == 0xED) v.hi = 0x9F;
                },
                0xF0...0xF4 => {
                    v.need = 3;
                    if (b == 0xF0) v.lo = 0x90;
                    if (b == 0xF4) v.hi = 0x8F;
                },
                else => {
                    v.valid = false;
                    return;
                },
            }
        }
    }

    /// Everything so far is complete, valid UTF-8 with at least one multibyte character.
    fn multibyteText(v: *const Utf8Validator) bool {
        return v.valid and v.need == 0 and v.multibyte > 0;
    }
};

/// Byte-order marks recognized in the first chunk (needs at least 3 bytes).
fn detectBom(buf: []const u8) ?[:0]const u8 {
    if (buf.len <= 2) return null;
    switch (buf[0]) {
        0xef => if (buf[1] == 0xbb and buf[2] == 0xbf) return "UTF-8",
        0xfe => if (buf[1] == 0xff) return "UTF-16",
        0xff => if (buf[1] == 0xfe) {
            return if (buf.len > 3 and buf[2] == 0 and buf[3] == 0) "UTF-32" else "UTF-16";
        },
        0x00 => if (buf.len > 3 and buf[1] == 0 and buf[2] == 0xfe and buf[3] == 0xff) return "UTF-32",
        else => {},
    }
    return null;
}

/// uchardetz's BOM-less UTF-16 heuristic over the first 256 bytes of the
/// first chunk: >= 20% NULs in one byte position and < 5% in the other.
fn detectBomlessUtf16(buf: []const u8) ?[:0]const u8 {
    if (buf.len < 8) return null;
    const check_len = @min(buf.len, 256) & ~@as(usize, 1);
    var even_nulls: usize = 0;
    var odd_nulls: usize = 0;
    var j: usize = 0;
    while (j < check_len) : (j += 2) {
        if (buf[j] == 0) even_nulls += 1;
        if (buf[j + 1] == 0) odd_nulls += 1;
    }
    const half_len = check_len / 2;
    if (even_nulls * 5 >= half_len and odd_nulls * 20 < half_len) return "UTF-16BE";
    if (odd_nulls * 5 >= half_len and even_nulls * 20 < half_len) return "UTF-16LE";
    return null;
}

fn detectInChunks(comptime D: type, bytes: []const u8, chunk_len: usize) ![:0]const u8 {
    var d: D = .init(std.testing.allocator);
    defer d.deinit();
    var rest = bytes;
    while (rest.len > 0) {
        const n = @min(rest.len, chunk_len);
        try d.handleData(rest[0..n]);
        rest = rest[n..];
    }
    d.dataEnd();
    return d.charset();
}

test "a byte-order mark fed one byte at a time is still recognized" {
    const bytes = "\xFF\xFEh\x00e\x00l\x00l\x00o\x00";
    try std.testing.expectEqualStrings("UTF-16", try detectInChunks(UpstreamDetector, bytes, bytes.len));
    // Upstream only looks for a mark in a first chunk of 3+ bytes.
    try std.testing.expect(!std.mem.eql(u8, "UTF-16", try detectInChunks(UpstreamDetector, bytes, 1)));
    try std.testing.expectEqualStrings("UTF-16", try detectInChunks(Detector, bytes, 1));
}

test "high bytes after a 64 KiB ASCII prefix are not reported as ASCII" {
    // Two multibyte characters: UTF-8 confidence 0.75, below the 0.95 shortcut
    // at which the UTF-8 prober would override the verdict by itself.
    const utf8_text = " na\xC3\xAFve caf\xC3\xA9";
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.testing.allocator);
    try buf.appendNTimes(std.testing.allocator, 'a', 65536);
    try buf.appendSlice(std.testing.allocator, utf8_text);
    // Upstream fixes the verdict at ASCII after an all-ASCII first chunk.
    try std.testing.expectEqualStrings("ASCII", try detectInChunks(UpstreamDetector, buf.items, 65536));
    try std.testing.expectEqualStrings("UTF-8", try detectInChunks(UpstreamDetector, buf.items[65536..], 65536));
    try std.testing.expectEqualStrings("UTF-8", try detectInChunks(Detector, buf.items, 65536));
}

test "handleData leaves the detector unchanged when a buffer cannot grow" {
    const text = "na\xC3\xAFve caf\xC3\xA9 " ** 8;
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    var d: Detector = .init(failing.allocator());
    defer d.deinit();
    try std.testing.expectError(error.OutOfMemory, d.handleData(text));
    try std.testing.expectEqual(@as(usize, 0), d.pending.items.len);
    try std.testing.expect(!d.got_data);
    failing.fail_index = std.math.maxInt(usize);
    try d.handleData(text);
    d.dataEnd();
    try std.testing.expectEqualStrings("UTF-8", d.charset());
}

test "valid UTF-8 with multibyte characters is reported as UTF-8" {
    const bytes = "\xC4\xB0nsan haklar\xC4\xB1 evrensel beyannamesi"; // Turkish, two multibyte letters
    // Upstream's UTF-8 confidence for two multibyte characters (0.75) loses
    // to a single-byte language model.
    try std.testing.expect(!std.mem.eql(u8, "UTF-8", try detectInChunks(UpstreamDetector, bytes, bytes.len)));
    try std.testing.expectEqualStrings("UTF-8", try detectInChunks(Detector, bytes, bytes.len));
    try std.testing.expectEqualStrings("UTF-8", try detectInChunks(Detector, bytes, 1));
}

test "input that is not valid UTF-8 is not forced to UTF-8" {
    const latin1 = "Le caf\xE9 est tr\xE8s bon, merci beaucoup pour tout";
    const truncated = "\xC4\xB0nsan haklar\xC4"; // ends inside a sequence
    for ([_][]const u8{ latin1, truncated }) |bytes| {
        try std.testing.expectEqualStrings(
            try detectInChunks(UpstreamDetector, bytes, bytes.len),
            try detectInChunks(Detector, bytes, bytes.len),
        );
    }
    try std.testing.expectEqualStrings("ASCII", try detectInChunks(Detector, "plain ascii", 64));
}

test "Utf8Validator agrees with std.unicode on random inputs split at random points" {
    var prng = std.Random.DefaultPrng.init(0x75746638);
    const r = prng.random();
    // Bytes biased toward the interesting UTF-8 boundaries.
    const alphabet = [_]u8{ 'a', 0x7F, 0x80, 0x8F, 0x90, 0x9F, 0xA0, 0xBF, 0xC0, 0xC1, 0xC2, 0xDF, 0xE0, 0xED, 0xEF, 0xF0, 0xF4, 0xF5, 0xFF };
    var buf: [12]u8 = undefined;
    for (0..200_000) |_| {
        const n = r.uintAtMost(usize, buf.len);
        for (buf[0..n]) |*b| b.* = alphabet[r.uintLessThan(usize, alphabet.len)];
        const s = buf[0..n];
        var v: Utf8Validator = .{};
        const cut = r.uintAtMost(usize, n);
        v.feed(s[0..cut]);
        v.feed(s[cut..]);
        const want = std.unicode.utf8ValidateSlice(s);
        try std.testing.expectEqual(want, v.valid and v.need == 0);
        if (want) {
            var multibyte: usize = 0;
            var it = std.unicode.Utf8View.initUnchecked(s).iterator();
            while (it.nextCodepointSlice()) |cp| {
                if (cp.len > 1) multibyte += 1;
            }
            try std.testing.expectEqual(multibyte, v.multibyte);
        }
    }
}
