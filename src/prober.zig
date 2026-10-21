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
// Translated to Zig from uchardetz src/nsCharSetProber.h @ abacfc1f.
// Translated to Zig from uchardetz src/nsCodingStateMachine.h @ abacfc1f.

//! Shared prober vocabulary: probing states, uchardet's float constants and
//! the coding state machine that drives every multibyte and escape prober.
const std = @import("std");
const types = @import("tables/types.zig");

/// nsProbingState.
pub const State = enum { detecting, found_it, not_me };

/// C `(float)<double literal>`: rounds the double, not the decimal, to f32.
pub fn f32FromDouble(comptime x: f64) f32 {
    return @floatCast(x);
}

/// SHORTCUT_THRESHOLD, `(float)0.95`.
pub const shortcut_threshold = f32FromDouble(0.95);

/// C's implicit unsigned-to-float conversion.
pub inline fn f(x: u32) f32 {
    return @floatFromInt(x);
}

/// nsCodingStateMachine states (nsSMState).
pub const sm_start: u32 = 0;
pub const sm_error: u32 = 1;
pub const sm_its_me: u32 = 2;

/// nsCodingStateMachine: per-byte class lookup and packed state transitions.
// complexity: O(1) per byte
pub const CodingStateMachine = struct {
    model: *const types.SMModel,
    current_state: u32 = sm_start,
    current_char_len: u32 = 0,
    current_byte_pos: u32 = 0,

    pub fn init(model: *const types.SMModel) CodingStateMachine {
        return .{ .model = model };
    }

    pub fn nextState(self: *CodingStateMachine, c: u8) u32 {
        const byte_cls = types.getFromPck(c, self.model.classTable);
        if (self.current_state == sm_start) {
            self.current_byte_pos = 0;
            // ISO2022JPSMModel has 10 byte classes but an 8-entry char-length
            // table, so upstream reads past it. Only the escape prober uses
            // that machine and it never reads the length; use 0 instead.
            self.current_char_len = if (byte_cls < self.model.charLenTable.len) self.model.charLenTable[byte_cls] else 0;
        }
        self.current_state = types.getFromPck(self.current_state * self.model.classFactor + byte_cls, self.model.stateTable);
        self.current_byte_pos += 1;
        return self.current_state;
    }

    pub fn reset(self: *CodingStateMachine) void {
        self.current_state = sm_start;
    }
};

test "f32FromDouble rounds through double like a C cast" {
    try std.testing.expectEqual(@as(u32, 0x3f733333), @as(u32, @bitCast(shortcut_threshold)));
}

test "multibyte models have a char length for every byte class" {
    const sm = @import("tables/all.zig").mbcs_sm;
    inline for (.{ sm.UTF8SMModel, sm.Big5SMModel, sm.EUCJPSMModel, sm.EUCKRSMModel, sm.EUCTWSMModel, sm.GB18030SMModel, sm.SJISSMModel }) |m| {
        try std.testing.expectEqual(@as(usize, m.classFactor), m.charLenTable.len);
    }
}
