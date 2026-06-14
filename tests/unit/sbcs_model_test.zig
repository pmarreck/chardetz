const std = @import("std");
const m = @import("chardetz").sbcs_model;

test "order constants match uchardet nsSBCharSetProber.h" {
	try std.testing.expectEqual(@as(u8, 255), m.ILL);
	try std.testing.expectEqual(@as(u8, 254), m.CTR);
	try std.testing.expectEqual(@as(u8, 253), m.SYM);
	try std.testing.expectEqual(@as(u8, 252), m.RET);
	try std.testing.expectEqual(@as(u8, 251), m.NUM);
}

test "SequenceModel holds a 256-entry order map and a precedence matrix" {
	const com = [_]u8{0} ** 256;
	const pm = [_]u8{ 0, 1, 2, 3 };
	const model = m.SequenceModel{
		.char_to_order_map = &com,
		.precedence_matrix = &pm,
		.freq_char_count = 2,
		.typical_positive_ratio = 0.5,
		.keep_english_letter = true,
		.charset_name = "TEST-1",
	};
	try std.testing.expectEqual(@as(usize, 2), model.freq_char_count);
	try std.testing.expectEqualStrings("TEST-1", model.charset_name);
	try std.testing.expectEqual(@as(u8, 3), model.precedence_matrix[3]);
}
