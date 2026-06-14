//! chardetz — a pure-Zig character-encoding detector translated from uchardet
//! (https://github.com/pmarreck/uchardetz, pinned @ abacfc1f), itself derived
//! from Mozilla's universalchardet. This is the core module root: pure
//! in-memory detection logic with NO I/O.
//!
//! Tri-licensed MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later — see COPYING.
//!
//! Milestone status: detection engine + UTF-8 prober + the full single-byte
//! prober family (SBCS group of 35 sub-probers incl. Hebrew, plus Latin1). The
//! CodingStateMachine drives the generated SMModels; a vtable-based Prober
//! interface unifies probers heterogeneously; UniversalDetector dispatches
//! (BOM + BOM-less UTF-16 heuristic + input classification + argmax-confidence)
//! over the prober array [UTF8, SBCSGroup, Latin1]. Detected charsets: ASCII,
//! UTF-8, UTF-16/BE/LE, UTF-32, and every single-byte charset (Cyrillic, Greek,
//! Hebrew, Thai, Arabic, Vietnamese, Turkish, Latin-1/15, WINDOWS-125x, etc.) —
//! verified at 0 divergences vs the uchardet oracle. Remaining: the CJK
//! multibyte (MBCS) group + the escape-sequence prober (ISO-2022-*, SHIFT_JIS,
//! BIG5, EUC-*, GB18030), which plug into the same dispatcher array next.

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
