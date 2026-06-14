//! chardetz — a pure-Zig character-encoding detector translated from uchardet
//! (https://github.com/pmarreck/uchardetz, pinned @ abacfc1f), itself derived
//! from Mozilla's universalchardet. This is the core module root: pure
//! in-memory detection logic with NO I/O.
//!
//! Tri-licensed MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later — see COPYING.
//!
//! Milestone status: M1 = scaffold + tables + oracle harness (no probers yet).
//! Prober/dispatcher logic arrives in M2+. Struct definitions and generated
//! data tables are re-exported here as they land.

const std = @import("std");

// ── Phase 2: core struct definitions ────────────────────────────────────────
pub const sbcs_model = @import("sbcs_model.zig");
pub const state_machine = @import("state_machine.zig");
pub const char_distribution = @import("char_distribution.zig");
pub const jp_context = @import("jp_context.zig");

// ── Phase 4: generated SM tables ────────────────────────────────────────────
pub const tables = @import("tables.zig");

test "scaffold compiles" {
	try std.testing.expect(true);
}
