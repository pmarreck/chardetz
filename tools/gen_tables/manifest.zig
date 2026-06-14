// CONTROL FILE — blessed-hash guarded (see RULES.md). Do not edit without re-blessing.
//! Pinned upstream source references for the table generator.
pub const PINNED_COMMIT = "abacfc1fc86ef7618547d7dce7cc7501e756fa31";
pub const UPSTREAM_SRC = "/Users/pmarreck/Documents-CloudManaged/uchardetz/src";

pub const sm_sources = [_][]const u8{ "nsMBCSSM.cpp", "nsEscSM.cpp" };
pub const dist_sources = [_][]const u8{ "Big5Freq.tab", "GB2312Freq.tab", "EUCTWFreq.tab", "JISFreq.tab", "EUCKRFreq.tab" };
pub const jpcntx_source = "JpCntx.cpp";
pub const sbcs_sources = [_][]const u8{
	"LangModels/LangArabicModel.cpp",
	"LangModels/LangBulgarianModel.cpp",
	"LangModels/LangDanishModel.cpp",
	"LangModels/LangEsperantoModel.cpp",
	"LangModels/LangFrenchModel.cpp",
	"LangModels/LangGermanModel.cpp",
	"LangModels/LangGreekModel.cpp",
	"LangModels/LangHebrewModel.cpp",
	"LangModels/LangHungarianModel.cpp",
	"LangModels/LangRussianModel.cpp",
	"LangModels/LangSpanishModel.cpp",
	"LangModels/LangThaiModel.cpp",
	"LangModels/LangTurkishModel.cpp",
	"LangModels/LangVietnameseModel.cpp",
};
