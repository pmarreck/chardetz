// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.

// Constants ported from CharDistribution.h
/// Characters whose frequency order < 512 are "frequent"; this threshold
/// gates confidence output (ported from ENOUGH_DATA_THRESHOLD).
pub const ENOUGH_DATA_THRESHOLD: u32 = 1024;
/// Minimum number of frequent characters seen before reporting a result.
pub const MINIMUM_DATA_THRESHOLD: u32 = 4;

/// Static frequency-order table for one CJK distribution analyser.
///
/// Maps an encoding-specific character order (from GetOrder() in the prober)
/// to a frequency rank among the most common characters. The generator
/// (Phase 5) produces one DistributionTable constant per CJK charset
/// (Big5, EUC-TW, EUC-KR, GB2312, SJIS, EUC-JP) by translating the
/// corresponding *.tab files from uchardet.
///
/// The upstream C++ uses `const PRInt16* mCharToFreqOrder` (signed 16-bit).
/// We use u16 here because all actual rank values are non-negative (0–N);
/// the signed type in C++ was a historical accident. The prober interprets
/// values < 512 as "frequent".
pub const DistributionTable = struct {
	/// Frequency-order lookup: index = encoding char order, value = rank.
	/// Values < 512 denote "frequent" characters used for confidence scoring.
	char_to_freq_order: []const u16,
	/// Number of entries in char_to_freq_order (= size of the encoding's
	/// character space; e.g. 5401 for Big5). Ported from mTableSize.
	table_size: u32 = 0,
	/// Confidence-scaling constant specific to each CJK charset/encoding.
	/// Ported from mTypicalDistributionRatio.
	typical_distribution_ratio: f32,
	/// Human-readable charset name (e.g. "Big5", "EUC-JP").
	name: []const u8,
};
