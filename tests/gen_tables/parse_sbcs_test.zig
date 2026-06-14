//! Unit tests for parse_sbcs: order map parsing, matrix parsing, and
//! SequenceModel declaration parsing.

const std = @import("std");
const gen_tables = @import("gen_tables");
const parse_sbcs = gen_tables.parse_sbcs;

const ORDER_MAP_FIXTURE =
	\\static const unsigned char Iso_8859_1_CharToOrderMap[] =
	\\{
	\\  CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,RET,CTR,CTR,RET,CTR,CTR, /* 0X */
	\\  CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR, /* 1X */
	\\  SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM, /* 2X */
	\\  NUM,NUM,NUM,NUM,NUM,NUM,NUM,NUM,NUM,NUM,SYM,SYM,SYM,SYM,SYM,SYM, /* 3X */
	\\  SYM,  2, 18, 11, 10,  0, 17, 15, 19,  4, 25, 26,  7, 13,  3,  8, /* 4X */
	\\   12, 20,  5,  1,  6,  9, 16, 30, 21, 22, 29,SYM,SYM,SYM,SYM,SYM, /* 5X */
	\\  SYM,  2, 18, 11, 10,  0, 17, 15, 19,  4, 25, 26,  7, 13,  3,  8, /* 6X */
	\\   12, 20,  5,  1,  6,  9, 16, 30, 21, 22, 29,SYM,SYM,SYM,SYM,CTR, /* 7X */
	\\  CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR, /* 8X */
	\\  CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR,CTR, /* 9X */
	\\  SYM,SYM,SYM,SYM,ILL,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM, /* AX */
	\\  SYM,SYM,SYM,SYM,SYM, 67,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM,SYM, /* BX */
	\\   24, 38, 32, 46, 49, 68, 47, 27, 23, 14, 28, 41, 69, 39, 33, 36, /* CX */
	\\   48, 45, 54, 40, 31, 55, 42,SYM, 52, 37, 43, 34, 44, 53, 50, 70, /* DX */
	\\   24, 38, 32, 46, 49, 71, 47, 27, 23, 14, 28, 41, 72, 39, 33, 36, /* EX */
	\\   48, 45, 54, 40, 31, 55, 42,SYM, 52, 37, 43, 34, 44, 53, 50, 73, /* FX */
	\\};
;

const LANG_MODEL_FIXTURE =
	\\static const PRUint8 TestLangModel[] =
	\\{
	\\  3,2,1,0,3,2,1,0,
	\\};
;

const SEQ_MODEL_FIXTURE =
	\\const SequenceModel TestModel =
	\\{
	\\  Some_CharToOrderMap,
	\\  TestLangModel,
	\\  38,
	\\  (float)0.997057879992383,
	\\  PR_TRUE,
	\\  "WINDOWS-1252"
	\\};
;

test "parseOrderMaps resolves macros and yields 256 entries" {
	const alloc = std.testing.allocator;
	const maps = try parse_sbcs.parseOrderMaps(alloc, ORDER_MAP_FIXTURE);
	defer {
		for (maps) |m| alloc.free(m.name);
		alloc.free(maps);
	}

	try std.testing.expectEqual(@as(usize, 1), maps.len);
	const m = maps[0];
	try std.testing.expectEqualStrings("Iso_8859_1_CharToOrderMap", m.name);
	// values is [256]u8, so .len is 256
	try std.testing.expectEqual(@as(usize, 256), m.values.len);
	// Row 0X: CTR=254
	try std.testing.expectEqual(@as(u8, 254), m.values[0]);
	// Row 0X index 10: RET=252
	try std.testing.expectEqual(@as(u8, 252), m.values[10]);
	// Row 2X: SYM=253
	try std.testing.expectEqual(@as(u8, 253), m.values[0x20]);
	// Row 3X: NUM=251
	try std.testing.expectEqual(@as(u8, 251), m.values[0x30]);
	// AX index 4: ILL=255
	try std.testing.expectEqual(@as(u8, 255), m.values[0xA4]);
	// 4X index 1 = 'A': order 2
	try std.testing.expectEqual(@as(u8, 2), m.values[0x41]);
}

test "parseLangModels parses u8 values" {
	const alloc = std.testing.allocator;
	const mats = try parse_sbcs.parseLangModels(alloc, LANG_MODEL_FIXTURE);
	defer {
		for (mats) |m| {
			alloc.free(m.name);
			alloc.free(m.values);
		}
		alloc.free(mats);
	}

	try std.testing.expectEqual(@as(usize, 1), mats.len);
	try std.testing.expectEqualStrings("TestLangModel", mats[0].name);
	try std.testing.expectEqual(@as(usize, 8), mats[0].values.len);
	try std.testing.expectEqual(@as(u8, 3), mats[0].values[0]);
	try std.testing.expectEqual(@as(u8, 0), mats[0].values[3]);
}

test "parseSequenceModels parses 6 fields correctly" {
	const alloc = std.testing.allocator;
	const models = try parse_sbcs.parseSequenceModels(alloc, SEQ_MODEL_FIXTURE);
	defer {
		for (models) |m| {
			alloc.free(m.var_name);
			alloc.free(m.map_ref);
			alloc.free(m.matrix_ref);
			alloc.free(m.charset_name);
		}
		alloc.free(models);
	}

	try std.testing.expectEqual(@as(usize, 1), models.len);
	const sm = models[0];
	try std.testing.expectEqualStrings("TestModel", sm.var_name);
	try std.testing.expectEqualStrings("Some_CharToOrderMap", sm.map_ref);
	try std.testing.expectEqualStrings("TestLangModel", sm.matrix_ref);
	try std.testing.expectEqual(@as(usize, 38), sm.freq_char_count);
	try std.testing.expectApproxEqRel(@as(f32, 0.997057879992383), sm.typical_positive_ratio, 1e-5);
	try std.testing.expect(sm.keep_english_letter);
	try std.testing.expectEqualStrings("WINDOWS-1252", sm.charset_name);
}
