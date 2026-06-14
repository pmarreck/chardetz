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
// @generated from nsMBCSSM.cpp @ abacfc1fc86ef7618547d7dce7cc7501e756fa31 — do not edit (regenerate via `zig build gen-tables`).

const state_machine = @import("../state_machine.zig");

pub const BIG5_cls = [32]u32{
	0x11111111,0x00111111,0x11111111,0x11110111,0x11111111,0x11111111,0x11111111,0x11111111,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x12222222,
	0x44444444,0x44444444,0x44444444,0x44444444,0x33333334,0x33333333,0x33333333,0x33333333,
	0x33333333,0x33333333,0x33333333,0x33333333,0x33333333,0x33333333,0x33333333,0x03333333
};

pub const BIG5_st = [3]u32{
	0x11113001,0x12222211,0x00000001
};

pub const Big5CharLenTable = [5]u32{
	0x00000000,0x00000001,0x00000001,0x00000002,0x00000000
};

pub const EUCJP_cls = [32]u32{
	0x44444444,0x55444444,0x44444444,0x44445444,0x44444444,0x44444444,0x44444444,0x44444444,
	0x44444444,0x44444444,0x44444444,0x44444444,0x44444444,0x44444444,0x44444444,0x44444444,
	0x55555555,0x31555555,0x55555555,0x55555555,0x22222225,0x22222222,0x22222222,0x22222222,
	0x22222222,0x22222222,0x22222222,0x22222222,0x00000000,0x00000000,0x00000000,0x50000000
};

pub const EUCJP_st = [5]u32{
	0x11105343,0x22221111,0x11101022,0x13111011,0x00001113
};

pub const EUCJPCharLenTable = [6]u32{
	0x00000002,0x00000002,0x00000002,0x00000003,0x00000001,0x00000000
};

pub const EUCKR_cls = [32]u32{
	0x11111111,0x00111111,0x11111111,0x11110111,0x11111111,0x11111111,0x11111111,0x11111111,
	0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,
	0x00000000,0x00000000,0x00000000,0x00000000,0x22222220,0x33322222,0x22222222,0x22222222,
	0x22222222,0x22222232,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x02222222
};

pub const EUCKR_st = [2]u32{
	0x11111301,0x00112222
};

pub const EUCKRCharLenTable = [4]u32{
	0x00000000,0x00000001,0x00000002,0x00000000
};

pub const EUCTW_cls = [32]u32{
	0x22222222,0x00222222,0x22222222,0x22220222,0x22222222,0x22222222,0x22222222,0x22222222,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,
	0x00000000,0x06000000,0x00000000,0x00000000,0x44444430,0x11111155,0x11111111,0x11111111,
	0x33331311,0x33333333,0x33333333,0x33333333,0x33333333,0x33333333,0x33333333,0x03333333
};

pub const EUCTW_st = [6]u32{
	0x14333011,0x22111111,0x10122222,0x11111000,0x00101115,0x00000010
};

pub const EUCTWCharLenTable = [7]u32{
	0x00000000,0x00000000,0x00000001,0x00000002,0x00000002,0x00000002,0x00000003
};

pub const GB18030_cls = [32]u32{
	0x11111111,0x00111111,0x11111111,0x11110111,0x11111111,0x11111111,0x33333333,0x11111133,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x42222222,
	0x66666665,0x66666666,0x66666666,0x66666666,0x66666666,0x66666666,0x66666666,0x66666666,
	0x66666666,0x66666666,0x66666666,0x66666666,0x66666666,0x66666666,0x66666666,0x06666666
};

pub const GB18030_st = [6]u32{
	0x13000001,0x22111111,0x01122222,0x11110014,0x12111511,0x00000011
};

pub const GB18030CharLenTable = [7]u32{
	0x00000000,0x00000001,0x00000001,0x00000001,0x00000001,0x00000001,0x00000002
};

pub const SJIS_cls = [32]u32{
	0x11111111,0x00111111,0x11111111,0x11110111,0x11111111,0x11111111,0x11111111,0x11111111,
	0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x22222222,0x12222222,
	0x33333333,0x33333333,0x33333333,0x33333333,0x22222222,0x22222222,0x22222222,0x22222222,
	0x22222222,0x22222222,0x22222222,0x22222222,0x33333333,0x44433333,0x44444444,0x00044444
};

pub const SJIS_st = [3]u32{
	0x11113001,0x22221111,0x00001122
};

pub const SJISCharLenTable = [6]u32{
	0x00000000,0x00000001,0x00000001,0x00000002,0x00000000,0x00000000
};

pub const UTF8_cls = [32]u32{
	0x11111111,0x00111111,0x11111111,0x11110111,0x11111111,0x11111111,0x11111111,0x11111111,
	0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,0x11111111,
	0x33332222,0x44444444,0x44444444,0x44444444,0x55555555,0x55555555,0x55555555,0x55555555,
	0x66666600,0x66666666,0x66666666,0x66666666,0x88888887,0x88988888,0xBBBBBBBA,0x00FEDDDC
};

pub const UTF8_st = [26]u32{
	0xAC111101,0x345678B9,0x11111111,0x11111111,0x22222222,0x22222222,0x11555511,0x11111111,
	0x11555111,0x11111111,0x11777711,0x11111111,0x11771111,0x11111111,0x11999911,0x11111111,
	0x11911111,0x11111111,0x11CCCC11,0x11111111,0x11C11111,0x11111111,0x111CCC11,0x11111111,
	0x11000011,0x11111111
};

pub const UTF8CharLenTable = [16]u32{
	0x00000000,0x00000001,0x00000000,0x00000000,0x00000000,0x00000000,0x00000002,0x00000003,
	0x00000003,0x00000003,0x00000004,0x00000004,0x00000005,0x00000005,0x00000006,0x00000006
};

pub const Big5SMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &BIG5_cls,
	},
	.class_factor = 5,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &BIG5_st,
	},
	.char_len_table = &Big5CharLenTable,
	.name = "BIG5",
};

pub const EUCJPSMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &EUCJP_cls,
	},
	.class_factor = 6,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &EUCJP_st,
	},
	.char_len_table = &EUCJPCharLenTable,
	.name = "EUC-JP",
};

pub const EUCKRSMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &EUCKR_cls,
	},
	.class_factor = 4,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &EUCKR_st,
	},
	.char_len_table = &EUCKRCharLenTable,
	.name = "EUC-KR",
};

pub const EUCTWSMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &EUCTW_cls,
	},
	.class_factor = 7,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &EUCTW_st,
	},
	.char_len_table = &EUCTWCharLenTable,
	.name = "EUC-TW",
};

pub const GB18030SMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &GB18030_cls,
	},
	.class_factor = 7,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &GB18030_st,
	},
	.char_len_table = &GB18030CharLenTable,
	.name = "GB18030",
};

pub const SJISSMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &SJIS_cls,
	},
	.class_factor = 6,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &SJIS_st,
	},
	.char_len_table = &SJISCharLenTable,
	.name = "SHIFT_JIS",
};

pub const UTF8SMModel = state_machine.SMModel{
	.class_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &UTF8_cls,
	},
	.class_factor = 16,
	.state_table = .{
		.idx_sft = state_machine.eIdxSft4bits,
		.sft_msk = state_machine.eSftMsk4bits,
		.bit_sft = state_machine.eBitSft4bits,
		.unit_msk = state_machine.eUnitMsk4bits,
		.data = &UTF8_st,
	},
	.char_len_table = &UTF8CharLenTable,
	.name = "UTF-8",
};

