// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.

/// Special codepoint order values (not real frequency orders).
/// Values >= 251 are reserved sentinels; real frequency orders are 0–250.
/// Ported from nsSBCharSetProber.h: ILL/CTR/SYM/RET/NUM macros.
pub const ILL: u8 = 255; // Illegal codepoint in this charset
pub const CTR: u8 = 254; // Control character
pub const SYM: u8 = 253; // Symbol / punctuation (not a word character)
pub const RET: u8 = 252; // Return / line feed
pub const NUM: u8 = 251; // ASCII digit 0–9

/// Single-byte charset frequency model for the nsSBCharSetProber.
///
/// Holds a 256-entry codepoint→order map and a freq_char_count²-entry
/// 2-char-sequence precedence matrix. The detector scores byte bigrams by
/// looking up each byte's order then consulting the matrix to determine
/// whether the pair is a "positive" (likely) or "negative" (unlikely)
/// sequence for the target charset.
pub const SequenceModel = struct {
	/// Maps every 8-bit codepoint (index) to a frequency order (0–250) or
	/// to one of the sentinel constants ILL/CTR/SYM/RET/NUM. Length: 256.
	char_to_order_map: []const u8,
	/// freq_char_count × freq_char_count matrix of 2-char bigram classes
	/// (POSITIVE_CAT / PROBABLE_CAT / NEUTRAL_CAT / NEGATIVE_CAT).
	precedence_matrix: []const u8,
	/// Number of frequent characters tracked; determines matrix dimensions.
	freq_char_count: usize,
	/// Ratio of positive (high-frequency bigram) sequences to total, used
	/// to compute per-prober confidence. Ported from mTypicalPositiveRatio.
	typical_positive_ratio: f32,
	/// Whether this script intermixes ASCII letters (currently unused in
	/// uchardet but preserved for future use). Ported from keepEnglishLetter.
	keep_english_letter: bool,
	/// IANA/MIME charset name for this model (e.g. "windows-1252").
	charset_name: []const u8,
};
