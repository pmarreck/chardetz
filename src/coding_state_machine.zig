// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsCodingStateMachine.h. The state machine consumes input
// bytes one at a time, mapping each byte to a character class (via the model's
// packed class table) and walking a DFA whose transitions live in the model's
// packed state table. It is the shared driver behind every multibyte prober.

const state_machine = @import("state_machine.zig");

/// DFA state — port of nsSMState (nsCodingStateMachine.h). uchardet declares
/// nsSMState as `enum { eStart, eError, eItsMe }` but assigns it via
/// `(nsSMState)GETFROMPCK(...)` — i.e. it is really an opaque `unsigned int`
/// tag whose state tables carry INTERMEDIATE values (UTF8_st packs 3..12). So
/// this MUST be a NON-EXHAUSTIVE enum (`_`): `@enumFromInt(12)` on a closed
/// `enum{start,error,its_me}` is illegal-value UB (traps in Debug, silent UB in
/// ReleaseFast — caught by the differential fuzz harness as an EUC-TW buffer
/// mis-detected as UTF-8). The `_` carries intermediate states as unnamed
/// variants; the `== .start/.@"error"/.its_me` comparisons in the probers still
/// work exactly as uchardet's `== eStart` etc.
pub const SMState = enum(u32) {
    start = 0,
    @"error" = 1,
    its_me = 2,
    _,
};

/// Runs an SMModel DFA byte-by-byte. Port of nsCodingStateMachine: for each
/// byte it looks up the byte's class, captures the character length on the
/// first byte of a character (state == start), then transitions via
/// stateTable[state*classFactor + class].
pub const CodingStateMachine = struct {
    model: *const state_machine.SMModel,
    current_state: SMState = .start,
    current_char_len: u32 = 0,
    current_byte_pos: u32 = 0,

    pub fn init(m: *const state_machine.SMModel) CodingStateMachine {
        return .{ .model = m };
    }

    /// Advance the DFA by one byte and return the new state.
    /// Mirrors nsCodingStateMachine::NextState exactly: GETCLASS uses the
    /// unsigned byte; charLen is sampled only at the start of a character.
    pub fn nextState(self: *CodingStateMachine, c: u8) SMState {
        // For each byte we get its class; if it is the first byte we also get
        // the byte length of the character it begins.
        const byte_cls = self.model.class_table.get(c);
        if (self.current_state == .start) {
            self.current_byte_pos = 0;
            self.current_char_len = self.model.char_len_table[byte_cls];
        }
        // From the byte's class and the state table, derive the next state.
        const idx = @intFromEnum(self.current_state) * self.model.class_factor + byte_cls;
        self.current_state = @enumFromInt(self.model.state_table.get(idx));
        self.current_byte_pos += 1;
        return self.current_state;
    }

    pub fn getCurrentCharLen(self: CodingStateMachine) u32 {
        return self.current_char_len;
    }

    pub fn reset(self: *CodingStateMachine) void {
        self.current_state = .start;
    }

    pub fn getCodingStateMachine(self: CodingStateMachine) []const u8 {
        return self.model.name;
    }
};
