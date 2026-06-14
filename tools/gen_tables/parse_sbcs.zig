//! Parser for uchardet C++ SBCS language model source files.
//! Extracts CharToOrderMap arrays (256 entries, macro-resolved),
//! LangModel matrices (raw u8 values), and SequenceModel declarations.

const std = @import("std");

pub const OrderMap = struct {
	name: []const u8,
	values: [256]u8,
};

pub const LangMatrix = struct {
	name: []const u8,
	values: []u8,
};

pub const SeqModel = struct {
	var_name: []const u8,
	map_ref: []const u8,
	matrix_ref: []const u8,
	freq_char_count: usize,
	typical_positive_ratio: f32,
	keep_english_letter: bool,
	charset_name: []const u8,
};

/// Resolve a macro token to its u8 sentinel value, or parse as decimal integer.
fn resolveToken(tok: []const u8) !u8 {
	const t = std.mem.trim(u8, tok, " \t\r\n");
	if (std.mem.eql(u8, t, "ILL")) return 255;
	if (std.mem.eql(u8, t, "CTR")) return 254;
	if (std.mem.eql(u8, t, "SYM")) return 253;
	if (std.mem.eql(u8, t, "RET")) return 252;
	if (std.mem.eql(u8, t, "NUM")) return 251;
	return std.fmt.parseInt(u8, t, 10);
}

/// Strip all /* ... */ block comments and // line comments from src (returns allocated slice).
/// This handles both C and C++ comment styles present in uchardet source files.
fn stripComments(alloc: std.mem.Allocator, src: []const u8) ![]u8 {
	var out: std.ArrayListUnmanaged(u8) = .empty;
	errdefer out.deinit(alloc);
	var i: usize = 0;
	while (i < src.len) {
		if (i + 1 < src.len and src[i] == '/' and src[i + 1] == '*') {
			// Skip block comment until */
			i += 2;
			while (i + 1 < src.len) : (i += 1) {
				if (src[i] == '*' and src[i + 1] == '/') {
					i += 2;
					break;
				}
			}
		} else if (i + 1 < src.len and src[i] == '/' and src[i + 1] == '/') {
			// Skip line comment until newline (preserve the newline itself)
			i += 2;
			while (i < src.len and src[i] != '\n') : (i += 1) {}
		} else {
			try out.append(alloc, src[i]);
			i += 1;
		}
	}
	return out.toOwnedSlice(alloc);
}

/// Parse all `static const unsigned char <NAME>[] = { ... };` blocks.
/// Resolves ILL/CTR/SYM/RET/NUM macros. Requires exactly 256 values each.
pub fn parseOrderMaps(alloc: std.mem.Allocator, src: []const u8) ![]OrderMap {
	var maps: std.ArrayListUnmanaged(OrderMap) = .empty;
	errdefer {
		for (maps.items) |m| alloc.free(m.name);
		maps.deinit(alloc);
	}

	const stripped = try stripComments(alloc, src);
	defer alloc.free(stripped);

	const needle = "static const unsigned char ";
	var offset: usize = 0;

	while (std.mem.indexOfPos(u8, stripped, offset, needle)) |pos| {
		const after_needle = pos + needle.len;
		// Find '[' to get the identifier
		const bracket = std.mem.indexOfScalarPos(u8, stripped, after_needle, '[') orelse break;
		const name_raw = std.mem.trim(u8, stripped[after_needle..bracket], " \t\r\n");
		const name = try alloc.dupe(u8, name_raw);
		errdefer alloc.free(name);

		// Find opening '{'
		const open = std.mem.indexOfScalarPos(u8, stripped, bracket, '{') orelse {
			alloc.free(name);
			offset = after_needle;
			continue;
		};
		// Find closing '};'
		const close_brace = std.mem.indexOfPos(u8, stripped, open + 1, "};") orelse {
			alloc.free(name);
			offset = after_needle;
			continue;
		};
		const block = stripped[open + 1 .. close_brace];

		// Split on comma, collect trimmed non-empty tokens
		var values: [256]u8 = undefined;
		var count: usize = 0;
		var it = std.mem.tokenizeScalar(u8, block, ',');
		while (it.next()) |raw_tok| {
			const tok = std.mem.trim(u8, raw_tok, " \t\r\n");
			if (tok.len == 0) continue;
			if (count >= 256) return error.TooManyValues;
			values[count] = try resolveToken(tok);
			count += 1;
		}
		if (count != 256) {
			alloc.free(name);
			offset = close_brace + 2;
			continue;
		}

		try maps.append(alloc, .{ .name = name, .values = values });
		offset = close_brace + 2;
	}

	return maps.toOwnedSlice(alloc);
}

/// Parse all `static const PRUint8 <NAME>[] = { ... };` blocks.
/// Values are raw decimal integers (no macros needed).
pub fn parseLangModels(alloc: std.mem.Allocator, src: []const u8) ![]LangMatrix {
	var mats: std.ArrayListUnmanaged(LangMatrix) = .empty;
	errdefer {
		for (mats.items) |m| {
			alloc.free(m.name);
			alloc.free(m.values);
		}
		mats.deinit(alloc);
	}

	const stripped = try stripComments(alloc, src);
	defer alloc.free(stripped);

	const needle = "static const PRUint8 ";
	var offset: usize = 0;

	while (std.mem.indexOfPos(u8, stripped, offset, needle)) |pos| {
		const after_needle = pos + needle.len;
		const bracket = std.mem.indexOfScalarPos(u8, stripped, after_needle, '[') orelse break;
		const name_raw = std.mem.trim(u8, stripped[after_needle..bracket], " \t\r\n");
		const name = try alloc.dupe(u8, name_raw);
		errdefer alloc.free(name);

		const open = std.mem.indexOfScalarPos(u8, stripped, bracket, '{') orelse {
			alloc.free(name);
			offset = after_needle;
			continue;
		};
		const close_brace = std.mem.indexOfPos(u8, stripped, open + 1, "};") orelse {
			alloc.free(name);
			offset = after_needle;
			continue;
		};
		const block = stripped[open + 1 .. close_brace];

		var vals: std.ArrayListUnmanaged(u8) = .empty;
		errdefer vals.deinit(alloc);
		var it = std.mem.tokenizeScalar(u8, block, ',');
		while (it.next()) |raw_tok| {
			const tok = std.mem.trim(u8, raw_tok, " \t\r\n");
			if (tok.len == 0) continue;
			const v = std.fmt.parseInt(u8, tok, 10) catch continue;
			try vals.append(alloc, v);
		}

		try mats.append(alloc, .{ .name = name, .values = try vals.toOwnedSlice(alloc) });
		offset = close_brace + 2;
	}

	return mats.toOwnedSlice(alloc);
}

/// Parse all `const SequenceModel <NAME> = { ... };` blocks.
pub fn parseSequenceModels(alloc: std.mem.Allocator, src: []const u8) ![]SeqModel {
	var models: std.ArrayListUnmanaged(SeqModel) = .empty;
	errdefer {
		for (models.items) |m| {
			alloc.free(m.var_name);
			alloc.free(m.map_ref);
			alloc.free(m.matrix_ref);
			alloc.free(m.charset_name);
		}
		models.deinit(alloc);
	}

	const stripped = try stripComments(alloc, src);
	defer alloc.free(stripped);

	// Must match "const SequenceModel " but NOT "static const" version
	const needle = "const SequenceModel ";
	var offset: usize = 0;

	while (std.mem.indexOfPos(u8, stripped, offset, needle)) |pos| {
		// Ensure it's NOT preceded by "static " (would make it "static const SequenceModel")
		var skip = false;
		if (pos >= 7) {
			const prefix = stripped[pos - 7 .. pos];
			if (std.mem.eql(u8, prefix, "static ")) skip = true;
		}
		if (skip) {
			offset = pos + needle.len;
			continue;
		}

		const after_needle = pos + needle.len;
		// Find '=' to get var name
		const eq = std.mem.indexOfScalarPos(u8, stripped, after_needle, '=') orelse break;
		const var_name_raw = std.mem.trim(u8, stripped[after_needle..eq], " \t\r\n");
		const var_name = try alloc.dupe(u8, var_name_raw);
		errdefer alloc.free(var_name);

		// Find '{'
		const open = std.mem.indexOfScalarPos(u8, stripped, eq, '{') orelse {
			alloc.free(var_name);
			offset = after_needle;
			continue;
		};
		// Find '};'
		const close_brace = std.mem.indexOfPos(u8, stripped, open + 1, "};") orelse {
			alloc.free(var_name);
			offset = after_needle;
			continue;
		};
		const block = stripped[open + 1 .. close_brace];

		// Split block by commas into exactly 6 fields
		var fields: [6][]const u8 = undefined;
		var fi: usize = 0;
		var it = std.mem.splitScalar(u8, block, ',');
		while (it.next()) |raw_field| {
			if (fi >= 6) break;
			fields[fi] = std.mem.trim(u8, raw_field, " \t\r\n");
			fi += 1;
		}
		if (fi < 6) {
			alloc.free(var_name);
			offset = close_brace + 2;
			continue;
		}

		// field 0: map_ref
		const map_ref = try alloc.dupe(u8, fields[0]);
		errdefer alloc.free(map_ref);

		// field 1: matrix_ref
		const matrix_ref = try alloc.dupe(u8, fields[1]);
		errdefer alloc.free(matrix_ref);

		// field 2: freq_char_count
		const freq_char_count = std.fmt.parseInt(usize, fields[2], 10) catch {
			alloc.free(var_name);
			alloc.free(map_ref);
			alloc.free(matrix_ref);
			offset = close_brace + 2;
			continue;
		};

		// field 3: typical_positive_ratio — strip "(float)" prefix
		var ratio_str = fields[3];
		if (std.mem.startsWith(u8, ratio_str, "(float)")) ratio_str = ratio_str[7..];
		ratio_str = std.mem.trim(u8, ratio_str, " \t\r\n");
		const typical_positive_ratio = std.fmt.parseFloat(f32, ratio_str) catch {
			alloc.free(var_name);
			alloc.free(map_ref);
			alloc.free(matrix_ref);
			offset = close_brace + 2;
			continue;
		};

		// field 4: keep_english_letter — PR_TRUE or PR_FALSE
		const keep_str = fields[4];
		const keep_english_letter = std.mem.eql(u8, keep_str, "PR_TRUE");

		// field 5: charset_name — strip surrounding quotes
		var cs = fields[5];
		// Remove leading quote
		if (cs.len > 0 and cs[0] == '"') cs = cs[1..];
		// Remove trailing quote
		if (cs.len > 0 and cs[cs.len - 1] == '"') cs = cs[0 .. cs.len - 1];
		const charset_name = try alloc.dupe(u8, cs);
		errdefer alloc.free(charset_name);

		try models.append(alloc, .{
			.var_name = var_name,
			.map_ref = map_ref,
			.matrix_ref = matrix_ref,
			.freq_char_count = freq_char_count,
			.typical_positive_ratio = typical_positive_ratio,
			.keep_english_letter = keep_english_letter,
			.charset_name = charset_name,
		});
		offset = close_brace + 2;
	}

	return models.toOwnedSlice(alloc);
}
