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
// The Original Code is mozilla.org code.
//
// The Initial Developer of the Original Code is
// Netscape Communications Corporation.
// Portions created by the Initial Developer are Copyright (C) 1998
// the Initial Developer. All Rights Reserved.
//
// Contributor(s):
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
// Hand port of uchardet's nsPkgInt.h, plus the SMModel (nsCodingStateMachine.h)
// and SequenceModel (nsSBCharSetProber.h) record types used by src/tables.

//! Packed-integer table helpers and the record types the generated tables use.
const std = @import("std");

/// uchardet's nsPkgInt: a table of small values packed into u32 words.
/// Fields keep the C names so generated tables read like upstream.
pub const PkgInt = struct {
    idxsft: u5,
    sftmsk: u32,
    bitsft: u5,
    unitmsk: u32,
    data: []const u32,
};

/// Packs eight 4-bit values, first value in the low nibble (C PCK4BITS).
pub fn pck4bits(v: [8]u4) u32 {
    var word: u32 = 0;
    for (v, 0..) |x, k| word |= @as(u32, x) << @intCast(4 * k);
    return word;
}

/// Packs four 8-bit values, first value in the low byte (C PCK8BITS).
pub fn pck8bits(v: [4]u8) u32 {
    var word: u32 = 0;
    for (v, 0..) |x, k| word |= @as(u32, x) << @intCast(8 * k);
    return word;
}

/// Packs two 16-bit values, first value in the low half (C PCK16BITS).
pub fn pck16bits(v: [2]u16) u32 {
    return @as(u32, v[0]) | (@as(u32, v[1]) << 16);
}

/// Reads element `i` from a packed table (C GETFROMPCK).
pub fn getFromPck(i: u32, c: PkgInt) u32 {
    const shift: u5 = @intCast((i & c.sftmsk) << c.bitsft);
    return (c.data[i >> c.idxsft] >> shift) & c.unitmsk;
}

/// State-machine model for multibyte and escape-sequence probers.
pub const SMModel = struct {
    classTable: PkgInt,
    classFactor: u32,
    stateTable: PkgInt,
    charLenTable: []const u32,
    name: [:0]const u8,
};

/// Single-byte language model: byte -> frequency order map plus the
/// 2-character sequence precedence matrix.
pub const SequenceModel = struct {
    charToOrderMap: *const [256]u8,
    precedenceMatrix: []const u8,
    freqCharCount: u32,
    mTypicalPositiveRatio: f32,
    keepEnglishLetter: bool,
    charsetName: [:0]const u8,
};

test "pck macros put the first value in the lowest bits" {
    try std.testing.expectEqual(@as(u32, 0x87654321), pck4bits(.{ 1, 2, 3, 4, 5, 6, 7, 8 }));
    try std.testing.expectEqual(@as(u32, 0x04030201), pck8bits(.{ 1, 2, 3, 4 }));
    try std.testing.expectEqual(@as(u32, 0x00020001), pck16bits(.{ 1, 2 }));
}

test "getFromPck reads 4-bit elements across words" {
    const data = [_]u32{ 0x87654321, 0x0000000F };
    const c: PkgInt = .{ .idxsft = 3, .sftmsk = 7, .bitsft = 2, .unitmsk = 0xF, .data = &data };
    try std.testing.expectEqual(@as(u32, 1), getFromPck(0, c));
    try std.testing.expectEqual(@as(u32, 8), getFromPck(7, c));
    try std.testing.expectEqual(@as(u32, 15), getFromPck(8, c));
    try std.testing.expectEqual(@as(u32, 0), getFromPck(9, c));
}
