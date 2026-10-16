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

const minimum_threshold = prober.f32FromDouble(0.20);
const esc: u8 = 0x1b;
const nbsp: u8 = 0xa0;

const InputState = enum { pure_ascii, esc_ascii, highbyte };

pub const Detector = struct {
    gpa: std.mem.Allocator,
    scratch: std.ArrayList(u8) = .empty,

    input_state: InputState = .pure_ascii,
    nbsp_found: bool = false,
    done: bool = false,
    start: bool = true,
    got_data: bool = false,
    last_char: u8 = 0,
    detected: ?[:0]const u8 = null,
    /// What uchardet_get_charset returns (HandleUniversalDetector::m_charset).
    reported: ?[:0]const u8 = null,

    mbcs: MbcsGroupProber = .{},
    sbcs: SbcsGroupProber = .{},
    latin1: Latin1Prober = .{},
    /// Upstream deletes the escape prober at the first high byte and
    /// recreates it on demand; `esc_alive` mirrors that lifetime.
    esc: EscProber = .{},
    esc_alive: bool = false,

    pub fn init(gpa: std.mem.Allocator) Detector {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Detector) void {
        self.scratch.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn reset(self: *Detector) void {
        self.nbsp_found = false;
        self.done = false;
        self.input_state = .pure_ascii;
        self.start = true;
        self.detected = null;
        self.got_data = false;
        self.last_char = 0;
        if (self.esc_alive) self.esc.reset();
        self.mbcs.reset();
        self.sbcs.reset();
        self.latin1.reset();
        self.reported = "";
    }

    /// Feeds the next chunk. Results can depend on chunk boundaries exactly
    /// as uchardet's do (byte-order marks are only checked in the first
    /// chunk, for example). Fails only if the scratch buffer cannot grow, in
    /// which case no detector state has changed.
    // complexity: O(n)
    pub fn handleData(self: *Detector, buf: []const u8) error{OutOfMemory}!void {
        if (self.done) return;
        try self.scratch.ensureTotalCapacity(self.gpa, buf.len);
        if (buf.len > 0) self.got_data = true;

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
                if (self.mbcs.handleData(buf) == .found_it) return self.found(self.mbcs.charsetName());
                if (self.sbcs.handleData(buf, scratch) == .found_it) return self.found(self.sbcs.charsetName());
                if (self.latin1.handleData(buf, scratch) == .found_it) return self.found(Latin1Prober.name);
            },
            .pure_ascii => self.detected = if (self.nbsp_found) "ISO-8859-1" else "ASCII",
        }
    }

    fn found(self: *Detector, name: [:0]const u8) void {
        self.done = true;
        self.detected = name;
    }

    pub fn dataEnd(self: *Detector) void {
        if (!self.got_data) return;
        if (self.detected) |name| {
            self.done = true;
            self.reported = name;
            return;
        }
        if (self.input_state != .highbyte) return;
        const confidences = [3]f32{ self.mbcs.confidence(), self.sbcs.confidence(), self.latin1.confidence() };
        var max_conf: f32 = 0.0;
        var max_prober: usize = 0;
        for (confidences, 0..) |cf, i| {
            if (cf > max_conf) {
                max_conf = cf;
                max_prober = i;
            }
        }
        if (max_conf > minimum_threshold) self.reported = switch (max_prober) {
            0 => self.mbcs.charsetName(),
            1 => self.sbcs.charsetName(),
            else => Latin1Prober.name,
        };
    }

    /// uchardet_get_charset: "" until something has been reported.
    pub fn charset(self: *const Detector) [:0]const u8 {
        return self.reported orelse "";
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
