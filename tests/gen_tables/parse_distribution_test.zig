//! Unit tests for parse_distribution: CJK frequency-distribution .tab parser.

const std = @import("std");
const gen_tables = @import("gen_tables");
const parse_distribution = gen_tables.parse_distribution;

const FIXTURE = @embedFile("fixtures/dist_snippet.txt");

test "parseDistribution: ratio, table_size, array values from fixture" {
	const alloc = std.testing.allocator;
	const t = try parse_distribution.parseDistribution(alloc, FIXTURE, "FOO");
	defer parse_distribution.freeDistTable(alloc, t);

	try std.testing.expectEqualStrings("FOO", t.name);
	try std.testing.expectApproxEqRel(@as(f32, 0.75), t.typical_distribution_ratio, 1e-5);
	try std.testing.expectEqual(@as(u32, 4), t.table_size);
	try std.testing.expectEqual(@as(usize, 4), t.char_to_freq_order.len);
	try std.testing.expectEqual(@as(u16, 1), t.char_to_freq_order[0]);
	try std.testing.expectEqual(@as(u16, 1801), t.char_to_freq_order[1]);
	try std.testing.expectEqual(@as(u16, 1506), t.char_to_freq_order[2]);
	try std.testing.expectEqual(@as(u16, 255), t.char_to_freq_order[3]);
}
