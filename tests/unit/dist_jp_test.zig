const std = @import("std");
const cd = @import("chardetz").char_distribution;
const jp = @import("chardetz").jp_context;

test "CharDistribution table struct holds a charToFreqOrder slice + ratio" {
	const order = [_]u16{ 0, 1, 2 };
	const t = cd.DistributionTable{ .char_to_freq_order = &order, .typical_distribution_ratio = 1.0, .name = "Big5" };
	try std.testing.expectEqual(@as(usize, 3), t.char_to_freq_order.len);
	try std.testing.expectEqualStrings("Big5", t.name);
}

test "JpCntx context table struct holds a flattened frequency table" {
	const jis = [_]u8{ 0, 1, 2, 3 };
	const t = jp.ContextTable{ .jis2_char_context = &jis };
	try std.testing.expectEqual(@as(u8, 3), t.jis2_char_context[3]);
}
