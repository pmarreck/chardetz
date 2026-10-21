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
// Translated to Zig from uchardetz src/nsCharSetProber.cpp @ abacfc1f.

//! uchardet's two input filters, writing into a caller-provided buffer at
//! least as long as the input (output never exceeds input length).
const std = @import("std");

/// Non-letter ASCII byte: a segment delimiter for both filters.
inline fn isAsciiSymbol(c: u8) bool {
    return c < 'A' or (c > 'Z' and c < 'a') or c > 'z';
}

/// FilterWithoutEnglishLetters: keeps only words containing a high byte,
/// replacing each delimiter after a kept word with one space.
// complexity: O(n)
pub fn withoutEnglishLetters(buf: []const u8, out: []u8) usize {
    std.debug.assert(out.len >= buf.len);
    var n: usize = 0;
    var prev: usize = 0;
    var meet_msb = false;
    for (buf, 0..) |c, cur| {
        if (c & 0x80 != 0) {
            meet_msb = true;
        } else if (isAsciiSymbol(c)) {
            if (meet_msb and cur > prev) {
                @memcpy(out[n..][0 .. cur - prev], buf[prev..cur]);
                n += cur - prev;
                out[n] = ' ';
                n += 1;
                meet_msb = false;
            }
            prev = cur + 1;
        }
    }
    if (meet_msb and buf.len > prev) {
        @memcpy(out[n..][0 .. buf.len - prev], buf[prev..]);
        n += buf.len - prev;
    }
    return n;
}

/// FilterWithEnglishLetters: drops markup between '<' and '>' and reduces
/// each run of ASCII symbols to one space.
// complexity: O(n)
pub fn withEnglishLetters(buf: []const u8, out: []u8) usize {
    std.debug.assert(out.len >= buf.len);
    var n: usize = 0;
    var prev: usize = 0;
    var in_tag = false;
    for (buf, 0..) |c, cur| {
        if (c == '>') {
            in_tag = false;
        } else if (c == '<') {
            in_tag = true;
        }
        if (c & 0x80 == 0 and isAsciiSymbol(c)) {
            if (cur > prev and !in_tag) {
                @memcpy(out[n..][0 .. cur - prev], buf[prev..cur]);
                n += cur - prev;
                out[n] = ' ';
                n += 1;
            }
            prev = cur + 1;
        }
    }
    if (!in_tag and buf.len > prev) {
        @memcpy(out[n..][0 .. buf.len - prev], buf[prev..]);
        n += buf.len - prev;
    }
    return n;
}

fn expectFilter(comptime filter: anytype, input: []const u8, expected: []const u8) !void {
    var out: [64]u8 = undefined;
    const n = filter(input, &out);
    try std.testing.expectEqualSlices(u8, expected, out[0..n]);
}

test "withoutEnglishLetters keeps only words containing high bytes" {
    try expectFilter(withoutEnglishLetters, "hello world", "");
    try expectFilter(withoutEnglishLetters, "ab\xe9c, plain \xe0!", "ab\xe9c \xe0 ");
    try expectFilter(withoutEnglishLetters, "x \xff\xfe", "\xff\xfe");
    try expectFilter(withoutEnglishLetters, "", "");
}

test "withEnglishLetters drops tags and collapses symbols" {
    try expectFilter(withEnglishLetters, "caf\xe9 au lait", "caf\xe9 au lait");
    try expectFilter(withEnglishLetters, "a<b c>d", "c d");
    try expectFilter(withEnglishLetters, "x, y", "x y");
    try expectFilter(withEnglishLetters, "<open", "");
}
