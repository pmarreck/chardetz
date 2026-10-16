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
// Translated to Zig from uchardetz src/nsEscCharsetProber.cpp @ abacfc1f.

//! nsEscCharSetProber: ISO-2022 and HZ escape-sequence state machines.
const prober = @import("prober.zig");
const esc_sm = @import("tables/all.zig").esc_sm;

const num_of_esc_charsets = 4;

pub const EscProber = struct {
    sms: [num_of_esc_charsets]prober.CodingStateMachine = .{
        .init(&esc_sm.HZSMModel),
        .init(&esc_sm.ISO2022CNSMModel),
        .init(&esc_sm.ISO2022JPSMModel),
        .init(&esc_sm.ISO2022KRSMModel),
    },
    state: prober.State = .detecting,
    detected: ?[:0]const u8 = null,

    pub fn reset(self: *EscProber) void {
        self.state = .detecting;
        for (&self.sms) |*sm| sm.reset();
        self.detected = null;
    }

    /// Steps every machine (last to first, as upstream) on each byte.
    // complexity: O(n * 4)
    pub fn handleData(self: *EscProber, buf: []const u8) prober.State {
        for (buf) |c| {
            if (self.state != .detecting) break;
            var j: usize = num_of_esc_charsets;
            while (j > 0) {
                j -= 1;
                if (self.sms[j].nextState(c) == prober.sm_its_me) {
                    self.state = .found_it;
                    self.detected = self.sms[j].model.name;
                    return self.state;
                }
            }
        }
        return self.state;
    }
};
