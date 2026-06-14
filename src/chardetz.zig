//! chardetz — a pure-Zig character-encoding detector translated from uchardet
//! (https://github.com/pmarreck/uchardetz, pinned @ abacfc1f), itself derived
//! from Mozilla's universalchardet. This is the core module root: pure
//! in-memory detection logic with NO I/O.
//!
//! Tri-licensed MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later — see COPYING.
//!
//! Milestone status: M2 = detection engine skeleton + UTF-8 prober. The
//! CodingStateMachine drives the generated SMModels; a vtable-based Prober
//! interface unifies probers heterogeneously; UniversalDetector dispatches
//! (BOM + BOM-less UTF-16 heuristic + input classification + argmax-confidence).
//! Detected charsets so far: ASCII, UTF-8, UTF-16/BE/LE, UTF-32. Remaining
//! probers (multibyte group, SBCS group, Latin1, escape, Hebrew) land in later
//! chunks and plug into the dispatcher's prober array.

const std = @import("std");

// ── Phase 2: core struct definitions ────────────────────────────────────────
pub const sbcs_model = @import("sbcs_model.zig");
pub const state_machine = @import("state_machine.zig");
pub const char_distribution = @import("char_distribution.zig");
pub const jp_context = @import("jp_context.zig");

// ── Phase 4: generated SM tables ────────────────────────────────────────────
pub const tables = @import("tables.zig");

// ── M2: detection engine ─────────────────────────────────────────────────────
pub const coding_state_machine = @import("coding_state_machine.zig");
pub const prober = @import("prober.zig");
pub const detector = @import("detector.zig");

/// Buffer filters shared by the SBCS group / Latin1 probers.
pub const filter = @import("filter.zig");

/// Grouped re-export of concrete probers (extended as later chunks land).
pub const probers = struct {
	pub const utf8 = @import("probers/utf8.zig");
	pub const sbcs = @import("probers/sbcs.zig");
	pub const sbcs_group = @import("probers/sbcs_group.zig");
	pub const hebrew = @import("probers/hebrew.zig");
	pub const latin1 = @import("probers/latin1.zig");
};

/// One-shot detection: returns the detected charset name (a static string
/// slice; "" if undetermined). The allocator is accepted for API symmetry with
/// uchardet's lifecycle and future allocating probers, but the current path is
/// allocation-free. Mirrors uchardet's new → handle_data → data_end →
/// get_charset.
pub const detect = detector.detect;

test "scaffold compiles" {
	try std.testing.expect(true);
}
