//! Unit tests for parse_jpcntx: JpCntx 2D context table parser.

const std = @import("std");
const gen_tables = @import("gen_tables");
const parse_jpcntx = gen_tables.parse_jpcntx;

const FIXTURE = @embedFile("fixtures/jpcntx_snippet.txt");

test "parseJp2dTable: rows, cols, flattened values" {
	const alloc = std.testing.allocator;
	const t = try parse_jpcntx.parseJp2dTable(alloc, FIXTURE);
	defer parse_jpcntx.freeJp2dTable(alloc, t);

	try std.testing.expectEqual(@as(usize, 3), t.rows);
	try std.testing.expectEqual(@as(usize, 3), t.cols);
	try std.testing.expectEqual(@as(usize, 9), t.values.len);
	// [0][2] — index 2 in flat array
	try std.testing.expectEqual(@as(u8, 2), t.values[2]);
	// [1][2] — index 5 in flat array
	try std.testing.expectEqual(@as(u8, 3), t.values[5]);
}
