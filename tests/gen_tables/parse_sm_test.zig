//! Unit tests for parse_sm: PRUint32 array parsing (PCK4BITS evaluation) and
//! SMModel declaration parsing from the uchardet C++ state-machine sources.

const std = @import("std");
const gen_tables = @import("gen_tables");
const parse_sm = gen_tables.parse_sm;

// ── Fixture: Big5 state-machine block (extracted from nsMBCSSM.cpp) ──────────
const BIG5_FIXTURE =
	\\static const PRUint32 BIG5_cls [ 256 / 8 ] = {
	\\PCK4BITS(1,1,1,1,1,1,1,1),
	\\PCK4BITS(1,1,1,1,1,1,0,0),
	\\PCK4BITS(1,1,1,1,1,1,1,1),
	\\PCK4BITS(1,1,1,0,1,1,1,1),
	\\PCK4BITS(1,1,1,1,1,1,1,1),
	\\PCK4BITS(1,1,1,1,1,1,1,1),
	\\PCK4BITS(1,1,1,1,1,1,1,1),
	\\PCK4BITS(1,1,1,1,1,1,1,1),
	\\PCK4BITS(2,2,2,2,2,2,2,2),
	\\PCK4BITS(2,2,2,2,2,2,2,2),
	\\PCK4BITS(2,2,2,2,2,2,2,2),
	\\PCK4BITS(2,2,2,2,2,2,2,2),
	\\PCK4BITS(2,2,2,2,2,2,2,2),
	\\PCK4BITS(2,2,2,2,2,2,2,2),
	\\PCK4BITS(2,2,2,2,2,2,2,2),
	\\PCK4BITS(2,2,2,2,2,2,2,1),
	\\PCK4BITS(4,4,4,4,4,4,4,4),
	\\PCK4BITS(4,4,4,4,4,4,4,4),
	\\PCK4BITS(4,4,4,4,4,4,4,4),
	\\PCK4BITS(4,4,4,4,4,4,4,4),
	\\PCK4BITS(4,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,3),
	\\PCK4BITS(3,3,3,3,3,3,3,0)
	\\};
	\\
	\\static const PRUint32 BIG5_st [ 3] = {
	\\PCK4BITS(eError,eStart,eStart,3,eError,eError,eError,eError),
	\\PCK4BITS(eError,eError,eItsMe,eItsMe,eItsMe,eItsMe,eItsMe,eError),
	\\PCK4BITS(eError,eStart,eStart,eStart,eStart,eStart,eStart,eStart)
	\\};
	\\
	\\static const PRUint32 Big5CharLenTable[] = {0, 1, 1, 2, 0};
	\\
	\\SMModel const Big5SMModel = {
	\\  {eIdxSft4bits, eSftMsk4bits, eBitSft4bits, eUnitMsk4bits, BIG5_cls },
	\\    5,
	\\  {eIdxSft4bits, eSftMsk4bits, eBitSft4bits, eUnitMsk4bits, BIG5_st },
	\\  Big5CharLenTable,
	\\  "BIG5",
	\\};
;

// ── Tests for parseU32Arrays ──────────────────────────────────────────────────

test "parseU32Arrays: BIG5_cls has 32 words" {
	const alloc = std.testing.allocator;
	const arrays = try parse_sm.parseU32Arrays(alloc, BIG5_FIXTURE);
	defer {
		for (arrays) |a| {
			alloc.free(a.name);
			alloc.free(a.values);
		}
		alloc.free(arrays);
	}

	// Should find BIG5_cls, BIG5_st, and Big5CharLenTable
	var cls_opt: ?parse_sm.U32Array = null;
	for (arrays) |a| {
		if (std.mem.eql(u8, a.name, "BIG5_cls")) cls_opt = a;
	}
	try std.testing.expect(cls_opt != null);
	const cls = cls_opt.?;
	// 256 bytes / 8 per PCK4BITS call = 32 words
	try std.testing.expectEqual(@as(usize, 32), cls.values.len);
}

test "parseU32Arrays: BIG5_st is present" {
	const alloc = std.testing.allocator;
	const arrays = try parse_sm.parseU32Arrays(alloc, BIG5_FIXTURE);
	defer {
		for (arrays) |a| {
			alloc.free(a.name);
			alloc.free(a.values);
		}
		alloc.free(arrays);
	}

	var found = false;
	for (arrays) |a| {
		if (std.mem.eql(u8, a.name, "BIG5_st")) found = true;
	}
	try std.testing.expect(found);
}

test "parseU32Arrays: Big5CharLenTable equals {0,1,1,2,0}" {
	const alloc = std.testing.allocator;
	const arrays = try parse_sm.parseU32Arrays(alloc, BIG5_FIXTURE);
	defer {
		for (arrays) |a| {
			alloc.free(a.name);
			alloc.free(a.values);
		}
		alloc.free(arrays);
	}

	var tbl_opt: ?parse_sm.U32Array = null;
	for (arrays) |a| {
		if (std.mem.eql(u8, a.name, "Big5CharLenTable")) tbl_opt = a;
	}
	try std.testing.expect(tbl_opt != null);
	const tbl = tbl_opt.?;
	try std.testing.expectEqual(@as(usize, 5), tbl.values.len);
	try std.testing.expectEqual(@as(u32, 0), tbl.values[0]);
	try std.testing.expectEqual(@as(u32, 1), tbl.values[1]);
	try std.testing.expectEqual(@as(u32, 1), tbl.values[2]);
	try std.testing.expectEqual(@as(u32, 2), tbl.values[3]);
	try std.testing.expectEqual(@as(u32, 0), tbl.values[4]);
}

// ── Tests for parseSMModels ───────────────────────────────────────────────────

test "parseSMModels: finds Big5SMModel with correct fields" {
	const alloc = std.testing.allocator;
	const models = try parse_sm.parseSMModels(alloc, BIG5_FIXTURE);
	defer {
		for (models) |m| parse_sm.freeSMModelDecl(alloc, m);
		alloc.free(models);
	}

	try std.testing.expectEqual(@as(usize, 1), models.len);
	const m = models[0];
	try std.testing.expectEqualStrings("Big5SMModel", m.var_name);
	try std.testing.expectEqual(@as(u32, 5), m.class_factor);
	try std.testing.expectEqualStrings("BIG5_cls", m.class_data_ref);
	try std.testing.expectEqualStrings("BIG5_st", m.state_data_ref);
	try std.testing.expectEqualStrings("Big5CharLenTable", m.char_len_ref);
	try std.testing.expectEqualStrings("BIG5", m.name);
}
