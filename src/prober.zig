// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// The charset-prober interface. Port of nsCharSetProber's abstract base class
// (nsProbingState + the virtual HandleData/GetState/Reset/GetConfidence/
// GetCharSetName surface), expressed as a Zig vtable so the UniversalDetector
// can hold a heterogeneous, growing array of concrete probers behind a single
// pointer type.
//
// DESIGN CHOICE — vtable over tagged union:
//   The dispatcher (nsUniversalDetector) stores probers in a fixed array and
//   loops over them polymorphically (HandleData/GetConfidence on each). A
//   vtable models this open set cleanly: each later chunk (multibyte group,
//   SBCS group, Latin1, escape, Hebrew) adds a new concrete struct that exposes
//   an `asProber()` returning a `Prober` wrapping its own vtable — no central
//   enum to edit, no growing switch. A tagged union would force every prober's
//   type into one `enum`/`union` declaration in this file and a switch in every
//   method, coupling unrelated probers together and reopening this file on each
//   addition. The vtable keeps the interface closed and the implementations
//   open (open/closed principle), which is exactly the extensibility the
//   remaining chunks need.

/// Probing verdict — port of nsProbingState (nsCharSetProber.h).
/// detecting: still undecided, but a confidence can be queried.
/// found_it: positive answer. not_me: negative answer.
pub const ProbingState = enum(u32) {
    detecting = 0,
    found_it = 1,
    not_me = 2,
};

/// #define SHORTCUT_THRESHOLD (float)0.95 — nsCharSetProber.h.
/// A prober (or the dispatcher) shortcuts to found_it once confidence exceeds
/// this while still in the detecting state.
pub const SHORTCUT_THRESHOLD: f32 = 0.95;

/// #define MINIMUM_THRESHOLD (float)0.20 — nsUniversalDetector.cpp.
/// In DataEnd, the highest-confidence prober is only reported if its confidence
/// exceeds this floor; otherwise the detector reports nothing (negative answer).
pub const MINIMUM_THRESHOLD: f32 = 0.20;

/// Polymorphic handle to a concrete charset prober. `ptr` is the erased
/// concrete prober; `vtable` dispatches the five nsCharSetProber operations.
pub const Prober = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Feed a buffer; returns the prober's state after processing it.
        handle_data: *const fn (ptr: *anyopaque, buf: []const u8) ProbingState,
        /// Current confidence in [0,1]. Pure (no I/O, no clock).
        get_confidence: *const fn (ptr: *anyopaque) f32,
        /// Current probing state.
        get_state: *const fn (ptr: *anyopaque) ProbingState,
        /// Reset to the initial detecting state.
        reset: *const fn (ptr: *anyopaque) void,
        /// The charset name this prober reports when it wins.
        charset_name: *const fn (ptr: *anyopaque) []const u8,
    };

    pub fn handleData(self: Prober, buf: []const u8) ProbingState {
        return self.vtable.handle_data(self.ptr, buf);
    }
    pub fn getConfidence(self: Prober) f32 {
        return self.vtable.get_confidence(self.ptr);
    }
    pub fn getState(self: Prober) ProbingState {
        return self.vtable.get_state(self.ptr);
    }
    pub fn reset(self: Prober) void {
        self.vtable.reset(self.ptr);
    }
    pub fn charsetName(self: Prober) []const u8 {
        return self.vtable.charset_name(self.ptr);
    }
};
