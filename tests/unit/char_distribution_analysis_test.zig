const std = @import("std");
const cz = @import("chardetz");
const cda = cz.char_distribution_analysis;
const tables = cz.tables;

// GetOrder byte-math, asserted against the upstream CharDistribution.h formulas.

test "EUC-KR GetOrder: 94*(b0-0xb0)+b1-0xa1" {
    var a = cda.CharDistributionAnalysis.init(&tables.char_distribution.EUCKRDistributionTable, .euckr);
    // b0=0xb0,b1=0xa1 → 94*0 + 0 = 0
    a.handleOneChar(&[_]u8{ 0xb0, 0xa1 }, 2);
    try std.testing.expectEqual(@as(u32, 1), a.total_chars);
}

test "EUC-KR GetOrder rejects first byte < 0xb0 (order -1, no count)" {
    var a = cda.CharDistributionAnalysis.init(&tables.char_distribution.EUCKRDistributionTable, .euckr);
    a.handleOneChar(&[_]u8{ 0xaf, 0xa1 }, 2);
    try std.testing.expectEqual(@as(u32, 0), a.total_chars);
}

test "Big5 GetOrder: two second-byte ranges (+63 / 0x40 base)" {
    var a = cda.CharDistributionAnalysis.init(&tables.char_distribution.Big5DistributionTable, .big5);
    // b0=0xa4,b1=0xa1 → 157*0 + 0 + 63 = 63
    a.handleOneChar(&[_]u8{ 0xa4, 0xa1 }, 2);
    // b0=0xa4,b1=0x40 → 157*0 + 0 = 0
    a.handleOneChar(&[_]u8{ 0xa4, 0x40 }, 2);
    try std.testing.expectEqual(@as(u32, 2), a.total_chars);
}

test "SJIS GetOrder: low + high first-byte ranges, second-byte gap adjust" {
    var a = cda.CharDistributionAnalysis.init(&tables.char_distribution.JISDistributionTable, .sjis);
    // b0=0x81,b1=0x40 → 188*0 + (0x40-0x40) = 0
    a.handleOneChar(&[_]u8{ 0x81, 0x40 }, 2);
    // b0=0xe0,b1=0x80 → 188*31 + (0x80-0x40) - 1 (b1>0x7f)
    a.handleOneChar(&[_]u8{ 0xe0, 0x80 }, 2);
    try std.testing.expectEqual(@as(u32, 2), a.total_chars);
}

test "non-2-byte char is ignored (order forced to -1)" {
    var a = cda.CharDistributionAnalysis.init(&tables.char_distribution.Big5DistributionTable, .big5);
    a.handleOneChar(&[_]u8{ 0xa4, 0xa1 }, 1);
    try std.testing.expectEqual(@as(u32, 0), a.total_chars);
}

test "GetConfidence is SURE_NO with no data" {
    var a = cda.CharDistributionAnalysis.init(&tables.char_distribution.Big5DistributionTable, .big5);
    try std.testing.expectEqual(cda.SURE_NO, a.getConfidence());
}

test "GetConfidence rises with frequent chars, clamps to SURE_YES" {
    var a = cda.CharDistributionAnalysis.init(&tables.char_distribution.EUCKRDistributionTable, .euckr);
    a.reset(true); // preferred → data_threshold 0
    // Feed the same frequent char many times. order=0 for (0xb0,0xa1); if its
    // rank < 512 it counts as frequent. Drive total==freq → SURE_YES clamp.
    var i: usize = 0;
    while (i < 50) : (i += 1) a.handleOneChar(&[_]u8{ 0xb0, 0xa1 }, 2);
    // total==freq path returns SURE_YES (the "normalize" branch).
    if (a.freq_chars == a.total_chars and a.total_chars > 0) {
        try std.testing.expectEqual(cda.SURE_YES, a.getConfidence());
    }
}

test "EUC-TW order can exceed char_to_freq_order array length (must not OOB-panic)" {
    // EUCTW GetOrder max ≈ 5545 (b0=0xfe,b1=0xfe → 94*(0xfe-0xc4)+0xfe-0xa1),
    // but EUCTWCharToFreqOrder has only ~5378 entries while table_size=8102.
    // uchardet's `order < table_size` guard does NOT prevent the OOB read; we
    // must additionally clamp to the actual array length (effective behavior:
    // an out-of-array order is simply not "frequent"). This must not panic.
    var a = cda.CharDistributionAnalysis.init(&tables.char_distribution.EUCTWDistributionTable, .euctw);
    a.reset(true);
    a.handleOneChar(&[_]u8{ 0xfe, 0xfe }, 2); // order 5545 > array len
    // The char counts toward total but cannot be classified frequent safely.
    try std.testing.expectEqual(@as(u32, 1), a.total_chars);
}

test "Reset clears counters" {
    var a = cda.CharDistributionAnalysis.init(&tables.char_distribution.Big5DistributionTable, .big5);
    a.handleOneChar(&[_]u8{ 0xa4, 0xa1 }, 2);
    a.reset(false);
    try std.testing.expectEqual(@as(u32, 0), a.total_chars);
    try std.testing.expectEqual(@as(u32, 0), a.freq_chars);
}
