//! chardetz — a pure-Zig character-encoding detector translated from uchardet
//! (https://github.com/pmarreck/uchardetz, pinned @ abacfc1f), itself derived
//! from Mozilla's universalchardet. This is the core module root: pure
//! in-memory detection logic with NO I/O.
//!
//! Tri-licensed MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later — see COPYING.
//!
//! Milestone status: COMPLETE detection engine — every charset uchardet
//! supports, at oracle parity. The CodingStateMachine drives the generated
//! SMModels; a vtable-based Prober interface unifies probers heterogeneously;
//! UniversalDetector dispatches (BOM + BOM-less UTF-16 heuristic + input
//! classification + argmax-confidence) over the prober array
//! [MBCSGroup, SBCSGroup, Latin1] — with the escape-sequence prober fed on the
//! eEscAscii path. The MBCS group holds [UTF8, SJIS, EUCJP, GB18030, EUCKR,
//! Big5, EUCTW]; the SBCS group holds 35 single-byte sub-probers (incl.
//! Hebrew); plus the Latin1 prober. Detected charsets: ASCII, UTF-8,
//! UTF-16/BE/LE, UTF-32, every single-byte charset (Cyrillic, Greek, Hebrew,
//! Thai, Arabic, Vietnamese, Turkish, Latin-1/15, WINDOWS-125x, etc.), the CJK
//! multibyte set (SHIFT_JIS, BIG5, EUC-JP/KR/TW, GB18030) and the escape
//! encodings (ISO-2022-JP/KR/CN, HZ-GB-2312) — verified at checked=59,
//! pending=0, divergences=0 vs the uchardet oracle over the full corpus.

const std = @import("std");

// ── Phase 2: core struct definitions ────────────────────────────────────────
pub const sbcs_model = @import("sbcs_model.zig");
pub const state_machine = @import("state_machine.zig");
pub const char_distribution = @import("char_distribution.zig");
pub const jp_context = @import("jp_context.zig");
pub const char_distribution_analysis = @import("char_distribution_analysis.zig");
pub const jp_context_analysis = @import("jp_context_analysis.zig");

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
	pub const big5 = @import("probers/big5.zig");
	pub const gb18030 = @import("probers/gb18030.zig");
	pub const euckr = @import("probers/euckr.zig");
	pub const euctw = @import("probers/euctw.zig");
	pub const sjis = @import("probers/sjis.zig");
	pub const eucjp = @import("probers/eucjp.zig");
	pub const mbcs_group = @import("probers/mbcs_group.zig");
	pub const escape = @import("probers/escape.zig");
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
