// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.

// ── Bit-packing descriptor constants (from nsPkgInt.h) ──────────────────────
// 4-bit packing: 8 nibbles per u32 word
pub const eIdxSft4bits: u32 = 3; // right-shift i by this to get word index
pub const eSftMsk4bits: u32 = 7; // mask i by this to get intra-word slot
pub const eBitSft4bits: u32 = 2; // shift slot by this to get bit offset
pub const eUnitMsk4bits: u32 = 0x0000000F; // mask to extract one 4-bit unit

// 8-bit packing: 4 bytes per u32 word
pub const eIdxSft8bits: u32 = 2;
pub const eSftMsk8bits: u32 = 3;
pub const eBitSft8bits: u32 = 3;
pub const eUnitMsk8bits: u32 = 0x000000FF;

// 16-bit packing: 2 shorts per u32 word
pub const eIdxSft16bits: u32 = 1;
pub const eSftMsk16bits: u32 = 1;
pub const eBitSft16bits: u32 = 4;
pub const eUnitMsk16bits: u32 = 0x0000FFFF;

/// Packed integer table — direct port of uchardet's nsPkgInt struct and
/// GETFROMPCK macro.  Elements are packed into u32 words at sub-word
/// granularity (4-bit, 8-bit, or 16-bit units), selected by the descriptor
/// constants above.  `get(i)` unpacks element i using the formula:
///   (data[i >> idx_sft] >> ((i & sft_msk) << bit_sft)) & unit_msk
pub const PckInt = struct {
	/// How far to right-shift `i` to obtain the containing word index.
	idx_sft: u32,
	/// Mask applied to `i` (after word indexing) to get the intra-word slot.
	sft_msk: u32,
	/// How far to left-shift the slot number to get the bit offset within
	/// the word — equals log2(unit_width_in_bits).
	bit_sft: u32,
	/// Bit mask to extract one packed unit from the shifted word.
	unit_msk: u32,
	/// The backing array of packed u32 words.
	data: []const u32,

	/// Unpack the element at logical index `i`.
	/// Equivalent to the C macro: GETFROMPCK(i, c)
	///   = (((c).data[(i)>>(c).idxsft]) >> (((i)&(c).sftmsk)<<(c).bitsft)) & (c).unitmsk
	pub fn get(self: PckInt, i: u32) u32 {
		const word = self.data[i >> @intCast(self.idx_sft)];
		const shift: u5 = @intCast((i & self.sft_msk) << @intCast(self.bit_sft));
		return (word >> shift) & self.unit_msk;
	}
};

/// Multibyte coding state machine model — port of uchardet's SMModel struct.
///
/// Encodes a DFA that classifies input byte sequences into character-class
/// transitions. The DFA is run byte-by-byte by nsCodingStateMachine; the
/// packed tables keep the memory footprint tiny while allowing fast lookup.
pub const SMModel = struct {
	/// Packed byte-class table: maps each input byte to a class index.
	class_table: PckInt,
	/// Number of distinct byte classes (used to stride into state_table).
	class_factor: u32,
	/// Packed state-transition table: indexed by state*class_factor+class.
	state_table: PckInt,
	/// Maps byte class → number of bytes in the current character.
	char_len_table: []const u32,
	/// Human-readable encoding name (e.g. "UTF-8", "Big5").
	name: []const u8,
};
