// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
//
// This file is part of chardetz, a C++→Zig translation of uchardet
// (https://github.com/pmarreck/uchardetz), itself derived from Mozilla's
// universalchardet. The Original Code is Mozilla Universal charset detector
// code; Initial Developer: Netscape Communications Corporation (© 2001).
// Contributor: BYVoid <byvoid.kcp@gmail.com>.
//
// Tri-licensed MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later. See COPYING.
//
// @generated from nsEscSM.cpp @ abacfc1fc86ef7618547d7dce7cc7501e756fa31 — do not edit (regenerate via `zig build gen-tables`).

const state_machine = @import("../state_machine.zig");

pub const HZ_cls = [32]u32{
	0x00000001,0x00000000,0x00000000,0x00001000,0x00000000,0x00000000,0x00000000,0x00000000,
	0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x02504000,
	0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,
	0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111
};

pub const HZ_st = [6]u32{
	0x11000310,0x22221111,0x14001122,0x14551615,0x14144414,0x00000024
};

pub const HZCharLenTable = [6]u32{
	0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000
};

pub const ISO2022CN_cls = [32]u32{
	0x00000002,0x00000000,0x00000000,0x00001000,0x00000000,0x00000030,0x00000000,0x00000000,
	0x00004000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222
};

pub const ISO2022CN_st = [8]u32{
	0x00000130,0x11111110,0x22222211,0x14111222,0x11112111,0x11111165,0x11112111,0x01211111
};

pub const ISO2022CNCharLenTable = [9]u32{
	0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,
	0x00000000
};

pub const ISO2022JP_cls = [32]u32{
	0x00000002,0x22000000,0x00000000,0x00001000,0x00070000,0x00000003,0x00000000,0x00000000,
	0x00080406,0x00000590,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222
};

pub const ISO2022JP_st = [9]u32{
	0x00000130,0x11111100,0x22221111,0x11222222,0x11411151,0x12126111,0x22111111,0x11112111,
	0x00121111
};

pub const ISO2022JPCharLenTable = [8]u32{
	0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000
};

pub const ISO2022KR_cls = [32]u32{
	0x00000002,0x00000000,0x00000000,0x00001000,0x00030000,0x00000040,0x00000000,0x00000000,
	0x00005000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222
};

pub const ISO2022KR_st = [5]u32{
	0x11000130,0x22221111,0x11411122,0x11151111,0x00002111
};

pub const ISO2022KRCharLenTable = [6]u32{
	0x00000000,0x00000000,0x00000000,0x00000000,0x00000000,0x00000000
};

pub const HZSMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &HZ_cls,
	},
	.class_factor = 6,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &HZ_st,
	},
	.char_len_table = &HZCharLenTable,
	.name = "HZ-GB-2312",
};

pub const ISO2022CNSMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &ISO2022CN_cls,
	},
	.class_factor = 9,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &ISO2022CN_st,
	},
	.char_len_table = &ISO2022CNCharLenTable,
	.name = "ISO-2022-CN",
};

pub const ISO2022JPSMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &ISO2022JP_cls,
	},
	.class_factor = 10,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &ISO2022JP_st,
	},
	.char_len_table = &ISO2022JPCharLenTable,
	.name = "ISO-2022-JP",
};

pub const ISO2022KRSMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &ISO2022KR_cls,
	},
	.class_factor = 6,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &ISO2022KR_st,
	},
	.char_len_table = &ISO2022KRCharLenTable,
	.name = "ISO-2022-KR",
};

