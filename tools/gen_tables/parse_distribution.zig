//! Parser for uchardet CJK frequency-distribution `.tab` source files.
//!
//! Each `.tab` file (Big5Freq.tab, GB2312Freq.tab, etc.) contains:
//!   - `#define <NAME>_TYPICAL_DISTRIBUTION_RATIO (float)[space]<f>` — confidence ratio
//!   - `#define <NAME>_TABLE_SIZE  <n>` — character-space size (NOT array length)
//!   - `static const PRInt16 <Name>CharToFreqOrder[] = { ... };` — frequency ranks
//!
//! The caller passes `table_name` as the basename minus "Freq.tab" (e.g. "Big5").
//! The uppercase form (e.g. "BIG5") is derived internally for `#define` lookups.
//! The array is located by scanning for any `static const PRInt16 ...CharToFreqOrder[]`.

const std = @import("std");

pub const DistTable = struct {
	/// Human-readable charset name (same as the table_name passed by the caller).
	name: []const u8,
	/// Frequency-order lookup: index = encoding char order, value = rank.
	char_to_freq_order: []u16,
	/// Character-space size as declared by `<NAME>_TABLE_SIZE`.  NOT the array length.
	table_size: u32,
	/// Confidence-scaling ratio from `<NAME>_TYPICAL_DISTRIBUTION_RATIO`.
	typical_distribution_ratio: f32,
};

/// Strip all `/* ... */` block comments and `// ...` line comments from `src`.
/// Returns a freshly-allocated slice; caller frees.
fn stripComments(alloc: std.mem.Allocator, src: []const u8) ![]u8 {
	var out: std.ArrayListUnmanaged(u8) = .empty;
	errdefer out.deinit(alloc);
	var i: usize = 0;
	while (i < src.len) {
		if (i + 1 < src.len and src[i] == '/' and src[i + 1] == '*') {
			i += 2;
			while (i + 1 < src.len) : (i += 1) {
				if (src[i] == '*' and src[i + 1] == '/') {
					i += 2;
					break;
				}
			}
		} else if (i + 1 < src.len and src[i] == '/' and src[i + 1] == '/') {
			i += 2;
			while (i < src.len and src[i] != '\n') : (i += 1) {}
		} else {
			try out.append(alloc, src[i]);
			i += 1;
		}
	}
	return out.toOwnedSlice(alloc);
}

/// Parse the frequency-distribution data from a single `.tab` source file.
///
/// `table_name` is the basename minus "Freq.tab" (e.g. "Big5").  The function
/// derives the define prefix by upper-casing it (e.g. "BIG5_") for locating
/// `#define BIG5_TABLE_SIZE` and `#define BIG5_TYPICAL_DISTRIBUTION_RATIO`.
/// The array (`static const PRInt16 ...CharToFreqOrder[]`) is found by searching
/// for any declaration whose name ends in "CharToFreqOrder" — there is exactly
/// one per `.tab` file, so no ambiguity arises.
///
/// Caller owns all returned memory.
pub fn parseDistribution(alloc: std.mem.Allocator, src: []const u8, table_name: []const u8) !DistTable {
	// Build the UPPERCASE prefix for #define lookups (e.g. "BIG5_").
	const upper_name = try std.ascii.allocUpperString(alloc, table_name);
	defer alloc.free(upper_name);

	// ── Parse #define <UPPER>_TYPICAL_DISTRIBUTION_RATIO ────────────────────
	const ratio_key = try std.fmt.allocPrint(alloc, "#define {s}_TYPICAL_DISTRIBUTION_RATIO", .{upper_name});
	defer alloc.free(ratio_key);

	const ratio_pos = std.mem.indexOf(u8, src, ratio_key) orelse return error.MissingRatioDefine;
	const after_ratio_key = ratio_pos + ratio_key.len;
	// Value is the rest of the line; trim leading whitespace and the optional "(float)" cast.
	const ratio_line_end = std.mem.indexOfScalarPos(u8, src, after_ratio_key, '\n') orelse src.len;
	var ratio_str = std.mem.trim(u8, src[after_ratio_key..ratio_line_end], " \t\r");
	// Strip optional "(float)" prefix (with or without trailing space).
	if (std.mem.startsWith(u8, ratio_str, "(float)")) ratio_str = std.mem.trimStart(u8, ratio_str[7..], " ");
	const typical_distribution_ratio = std.fmt.parseFloat(f32, ratio_str) catch return error.BadRatioValue;

	// ── Parse #define <UPPER>_TABLE_SIZE ────────────────────────────────────
	const size_key = try std.fmt.allocPrint(alloc, "#define {s}_TABLE_SIZE", .{upper_name});
	defer alloc.free(size_key);

	const size_pos = std.mem.indexOf(u8, src, size_key) orelse return error.MissingTableSizeDefine;
	const after_size_key = size_pos + size_key.len;
	const size_line_end = std.mem.indexOfScalarPos(u8, src, after_size_key, '\n') orelse src.len;
	const size_str = std.mem.trim(u8, src[after_size_key..size_line_end], " \t\r");
	const table_size = std.fmt.parseInt(u32, size_str, 10) catch return error.BadTableSizeValue;

	// ── Strip comments before parsing the array ──────────────────────────────
	const stripped = try stripComments(alloc, src);
	defer alloc.free(stripped);

	// ── Locate `static const PRInt16 ...CharToFreqOrder[]` ──────────────────
	// We search for the pattern rather than requiring an exact name, because the
	// array prefix is mixed-case and the caller's table_name might differ in case.
	const array_decl_needle = "static const PRInt16 ";
	const freq_suffix = "CharToFreqOrder";

	var search_offset: usize = 0;
	const open: usize = blk: {
		while (std.mem.indexOfPos(u8, stripped, search_offset, array_decl_needle)) |decl_pos| {
			const after_decl = decl_pos + array_decl_needle.len;
			// Find '[' — the array dimension bracket or the empty [] for dynamic
			const bracket = std.mem.indexOfScalarPos(u8, stripped, after_decl, '[') orelse {
				search_offset = after_decl;
				continue;
			};
			const raw_name = std.mem.trim(u8, stripped[after_decl..bracket], " \t\r\n");
			if (!std.mem.endsWith(u8, raw_name, freq_suffix)) {
				search_offset = after_decl;
				continue;
			}
			// Found the right declaration — locate the '{' that opens the initialiser.
			const open_brace = std.mem.indexOfScalarPos(u8, stripped, bracket, '{') orelse {
				search_offset = after_decl;
				continue;
			};
			break :blk open_brace;
		}
		return error.MissingFreqOrderArray;
	};

	const close_brace = std.mem.indexOfPos(u8, stripped, open + 1, "};") orelse
		return error.UnterminatedFreqOrderArray;
	const block = stripped[open + 1 .. close_brace];

	// ── Parse comma-separated u16 values ────────────────────────────────────
	var vals: std.ArrayListUnmanaged(u16) = .empty;
	errdefer vals.deinit(alloc);

	var it = std.mem.tokenizeScalar(u8, block, ',');
	while (it.next()) |raw_tok| {
		const tok = std.mem.trim(u8, raw_tok, " \t\r\n");
		if (tok.len == 0) continue;
		const v = std.fmt.parseInt(u16, tok, 10) catch |err| return err;
		try vals.append(alloc, v);
	}

	// Pad up to table_size to neutralize an upstream out-of-bounds read.
	// uchardet's CharDistributionAnalysis guards only `order < table_size`, then
	// indexes char_to_freq_order[order]. For EUC-TW the compiled array (5376) is
	// SHORTER than table_size (8102), so orders in [len, table_size) read past
	// the array in C++ — undefined behavior; the adjacent .rodata happens to be
	// < 512 on the pinned build, i.e. classified "frequent". chardetz cannot read
	// OOB (Zig bounds-checks), so we pad the table to table_size with a < 512
	// ("frequent") sentinel, reproducing uchardet's de-facto behavior
	// DETERMINISTICALLY and making `order < table_size` in-bounds by construction
	// (physics over policy). Peter's call (2026-06-14): match the oracle. Only
	// EUC-TW is affected — every other table already has len == table_size.
	const FREQUENT_PAD: u16 = 0; // any value < 512 classifies as "frequent"
	while (vals.items.len < table_size) {
		try vals.append(alloc, FREQUENT_PAD);
	}

	return DistTable{
		.name = try alloc.dupe(u8, table_name),
		.char_to_freq_order = try vals.toOwnedSlice(alloc),
		.table_size = table_size,
		.typical_distribution_ratio = typical_distribution_ratio,
	};
}

/// Free all memory owned by a DistTable.
pub fn freeDistTable(alloc: std.mem.Allocator, t: DistTable) void {
	alloc.free(t.name);
	alloc.free(t.char_to_freq_order);
}
