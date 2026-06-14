const std = @import("std");
const sm = @import("chardetz").state_machine;

test "PkgInt 4-bit descriptors match uchardet nsPkgInt.h" {
	try std.testing.expectEqual(@as(u32, 3), sm.eIdxSft4bits);
	try std.testing.expectEqual(@as(u32, 7), sm.eSftMsk4bits);
	try std.testing.expectEqual(@as(u32, 2), sm.eBitSft4bits);
	try std.testing.expectEqual(@as(u32, 0x0000000F), sm.eUnitMsk4bits);
}

test "PckInt.get unpacks a packed nibble like uchardet GETFROMPCK" {
	const data = [_]u32{0x000000BA}; // low nibble=0xA, next=0xB
	const pck = sm.PckInt{
		.idx_sft = sm.eIdxSft4bits,
		.sft_msk = sm.eSftMsk4bits,
		.bit_sft = sm.eBitSft4bits,
		.unit_msk = sm.eUnitMsk4bits,
		.data = &data,
	};
	try std.testing.expectEqual(@as(u32, 0xA), pck.get(0));
	try std.testing.expectEqual(@as(u32, 0xB), pck.get(1));
}
