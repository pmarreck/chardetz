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
// Translated to Zig from uchardetz src/nsLatin1Prober.cpp @ abacfc1f.
// Translated to Zig from uchardetz src/nsLatin1Prober.h @ abacfc1f.

//! nsLatin1Prober: character-class bigram plausibility for windows-1252,
//! deliberately damped so more specific probers win ties.
const prober = @import("prober.zig");
const filter = @import("filter.zig");
const latin1 = @import("tables/all.zig").latin1;

const freq_cat_num = 4;

pub const Latin1Prober = struct {
    state: prober.State = .detecting,
    last_char_class: u8 = latin1.OTH,
    freq_counter: [freq_cat_num]u32 = @splat(0),

    pub const name: [:0]const u8 = "WINDOWS-1252";

    pub fn reset(self: *Latin1Prober) void {
        self.* = .{};
    }

    /// `scratch` must be at least `buf.len` bytes; it receives the filtered text.
    // complexity: O(n)
    pub fn handleData(self: *Latin1Prober, buf: []const u8, scratch: []u8) prober.State {
        const n = filter.withEnglishLetters(buf, scratch);
        for (scratch[0..n]) |c| {
            const char_class = latin1.Latin1_CharToClass[c];
            const freq = latin1.Latin1ClassModel[@as(usize, self.last_char_class) * latin1.CLASS_NUM + char_class];
            if (freq == 0) {
                self.state = .not_me;
                break;
            }
            self.freq_counter[freq] += 1;
            self.last_char_class = char_class;
        }
        return self.state;
    }

    pub fn confidence(self: *const Latin1Prober) f32 {
        if (self.state == .not_me) return 0.01;
        var total: u32 = 0;
        for (self.freq_counter) |count| total += count;
        var cf: f32 = undefined;
        if (total == 0) {
            cf = 0.0;
        } else {
            cf = prober.f(self.freq_counter[3]) * 1.0 / prober.f(total);
            cf -= prober.f(self.freq_counter[1]) * 20.0 / prober.f(total);
        }
        if (cf < 0.0) cf = 0.0;
        cf *= 0.50;
        return cf;
    }
};
