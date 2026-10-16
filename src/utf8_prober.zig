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
// Translated to Zig from uchardetz src/nsUTF8Prober.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsUTF8Prober.h @ abacfc1f.

//! nsUTF8Prober: counts multibyte sequences accepted by the UTF-8 state machine.
const prober = @import("prober.zig");
const tables = @import("tables/all.zig");

const one_char_prob = prober.f32FromDouble(0.50);

pub const Utf8Prober = struct {
    sm: prober.CodingStateMachine = .init(&tables.mbcs_sm.UTF8SMModel),
    state: prober.State = .detecting,
    num_of_mb_char: u32 = 0,

    pub const name: [:0]const u8 = "UTF-8";

    pub fn reset(self: *Utf8Prober) void {
        self.sm.reset();
        self.num_of_mb_char = 0;
        self.state = .detecting;
    }

    // complexity: O(n)
    pub fn handleData(self: *Utf8Prober, buf: []const u8) prober.State {
        for (buf) |c| {
            const coding_state = self.sm.nextState(c);
            if (coding_state == prober.sm_its_me) {
                self.state = .found_it;
                break;
            }
            if (coding_state == prober.sm_start and self.sm.current_char_len >= 2) self.num_of_mb_char += 1;
        }
        if (self.state == .detecting and self.confidence() > prober.shortcut_threshold) self.state = .found_it;
        return self.state;
    }

    pub fn confidence(self: *const Utf8Prober) f32 {
        var unlike = prober.f32FromDouble(0.99);
        if (self.num_of_mb_char < 6) {
            for (0..self.num_of_mb_char) |_| unlike *= one_char_prob;
            return prober.f32FromDouble(1.0) - unlike;
        }
        return prober.f32FromDouble(0.99);
    }
};
