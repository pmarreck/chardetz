// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.

// Constants ported from JpCntx.h
/// Number of hiragana frequency categories (used to dimension mRelSample).
pub const NUM_OF_CATEGORY: u32 = 6;
/// Minimum number of 2-char sequences before confidence is trusted.
pub const ENOUGH_REL_THRESHOLD: u32 = 100;
/// If mTotalRel exceeds this, stop collecting (ported from MAX_REL_THRESHOLD).
pub const MAX_REL_THRESHOLD: u32 = 1000;

/// Static 2-character hiragana context table for Japanese encoding detection.
///
/// Holds the flattened `jp2CharContext[83][83]` table from JpCntx.cpp, which
/// maps pairs of hiragana character indices to one of NUM_OF_CATEGORY
/// frequency categories. The prober accumulates category counts to decide
/// confidence. The generator (Phase 5) produces this constant from JpCntx.cpp.
///
/// The upstream declares `const PRUint8 jp2CharContext[83][83]` (u8 elements,
/// 83×83 = 6 889 entries). We store it as a flat slice for simpler indexing:
///   category = jis2_char_context[last_order * 83 + current_order]
pub const ContextTable = struct {
	/// Flattened 83×83 hiragana bigram→category table (u8, values 0–5).
	/// Index: last_hiragana_order * 83 + current_hiragana_order.
	jis2_char_context: []const u8,
};
