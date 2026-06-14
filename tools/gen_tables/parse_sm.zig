//! Parser for uchardet C++ multibyte/escape state-machine source files.
//! Extracts `static const PRUint32 <NAME>[]` arrays (evaluating PCK4BITS/eError/
//! eStart/eItsMe macros) and `SMModel const <NAME>` / `const SMModel <NAME>`
//! struct declarations from nsMBCSSM.cpp and nsEscSM.cpp.

const std = @import("std");

// ── Sentinel values for state-machine states (from nsCodingStateMachine.h) ─
const eStart: u32 = 0;
const eError: u32 = 1;
const eItsMe: u32 = 2;

/// A parsed `static const PRUint32 <NAME>[] = { ... };` block.
/// Values are fully-evaluated u32 words (PCK4BITS/sentinels resolved).
pub const U32Array = struct {
	name: []const u8,
	values: []u32,
};

/// A parsed `SMModel const <NAME>` / `const SMModel <NAME>` declaration.
/// Mirrors the C struct layout; data-array references are raw identifier strings.
pub const SMModelDecl = struct {
	/// Variable name (e.g. "Big5SMModel").
	var_name: []const u8,
	/// PckInt class_table descriptor fields: {idxSft, sftMsk, bitSft, unitMsk}.
	class_descriptors: [4][]const u8,
	/// Name of the backing `PRUint32[]` array for the class table.
	class_data_ref: []const u8,
	/// Number of distinct byte classes.
	class_factor: u32,
	/// PckInt state_table descriptor fields: {idxSft, sftMsk, bitSft, unitMsk}.
	state_descriptors: [4][]const u8,
	/// Name of the backing `PRUint32[]` array for the state table.
	state_data_ref: []const u8,
	/// Name of the `PRUint32[]` char-length table.
	char_len_ref: []const u8,
	/// Human-readable encoding name string (without surrounding quotes).
	name: []const u8,
};

// ── Comment stripping (reused from parse_sbcs pattern) ──────────────────────

/// Strip all `/* ... */` block comments and `// ...` line comments from src.
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

// ── PCK4BITS evaluation ──────────────────────────────────────────────────────

/// Resolve a token that may be a state-machine sentinel (eError/eStart/eItsMe)
/// or a plain decimal/hex integer. Returns a u32.
fn resolveU32Token(tok: []const u8) !u32 {
	const t = std.mem.trim(u8, tok, " \t\r\n");
	if (std.mem.eql(u8, t, "eError")) return eError;
	if (std.mem.eql(u8, t, "eStart")) return eStart;
	if (std.mem.eql(u8, t, "eItsMe")) return eItsMe;
	// std.fmt.parseInt with base 0 auto-detects 0x… or decimal
	return std.fmt.parseInt(u32, t, 0);
}

/// Evaluate `PCK4BITS(a,b,c,d,e,f,g,h)` given the 8 already-resolved u32 args.
/// The macro packs 8 4-bit nibbles (a=bits[3:0], b=bits[7:4], …, h=bits[31:28]).
///   PCK4BITS(a,b,c,d,e,f,g,h)
///     = (h<<28)|(g<<24)|(f<<20)|(e<<16)|(d<<12)|(c<<8)|(b<<4)|a
fn pck4bits(args: [8]u32) u32 {
	var v: u32 = 0;
	for (args, 0..) |a, i| {
		v |= (a & 0xF) << @intCast(i * 4);
	}
	return v;
}

/// Evaluate a PCK4BITS(…) call found in the already-comment-stripped source.
/// `pos` points to the 'P' of PCK4BITS; returns the u32 value and sets
/// `*end_pos` to one past the closing ')'.
fn evalPck4bits(stripped: []const u8, pos: usize, end_pos: *usize) !u32 {
	// Find the opening '('
	const open = std.mem.indexOfScalarPos(u8, stripped, pos, '(') orelse
		return error.MalformedPCK4BITS;
	// Find the matching closing ')'
	const close = std.mem.indexOfScalarPos(u8, stripped, open + 1, ')') orelse
		return error.MalformedPCK4BITS;
	const inner = stripped[open + 1 .. close];
	end_pos.* = close + 1;

	// Split into exactly 8 comma-separated tokens
	var args: [8]u32 = undefined;
	var i: usize = 0;
	var it = std.mem.splitScalar(u8, inner, ',');
	while (it.next()) |raw| {
		if (i >= 8) return error.TooManyPCK4BITSArgs;
		args[i] = try resolveU32Token(raw);
		i += 1;
	}
	if (i != 8) return error.TooFewPCK4BITSArgs;
	return pck4bits(args);
}

// ── Public parsers ───────────────────────────────────────────────────────────

/// Parse all `static const PRUint32 <NAME> [ … ] = { … };` blocks from src.
/// Values within the block may be bare integers, state-sentinel names
/// (eError/eStart/eItsMe), or PCK4BITS(…) macro calls — all are evaluated.
/// Returns a slice of U32Array; caller owns all memory.
pub fn parseU32Arrays(alloc: std.mem.Allocator, src: []const u8) ![]U32Array {
	var arrays: std.ArrayListUnmanaged(U32Array) = .empty;
	errdefer {
		for (arrays.items) |a| {
			alloc.free(a.name);
			alloc.free(a.values);
		}
		arrays.deinit(alloc);
	}

	const stripped = try stripComments(alloc, src);
	defer alloc.free(stripped);

	const needle = "static const PRUint32 ";
	var offset: usize = 0;

	while (std.mem.indexOfPos(u8, stripped, offset, needle)) |pos| {
		const after_needle = pos + needle.len;
		// Find '[' to delimit the name
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

		// Evaluate the block: tokens are separated by ',' but PCK4BITS(…) contains commas
		// internally, so we must scan character by character.
		var vals: std.ArrayListUnmanaged(u32) = .empty;
		errdefer vals.deinit(alloc);

		var bi: usize = 0;
		while (bi < block.len) {
			// Skip whitespace
			while (bi < block.len and (block[bi] == ' ' or block[bi] == '\t' or
				block[bi] == '\r' or block[bi] == '\n')) : (bi += 1)
			{}
			if (bi >= block.len) break;

			// Check for PCK4BITS macro
			if (bi + 8 <= block.len and std.mem.eql(u8, block[bi .. bi + 8], "PCK4BITS")) {
				var end_pos: usize = undefined;
				const v = try evalPck4bits(block, bi, &end_pos);
				try vals.append(alloc, v);
				bi = end_pos;
				// Skip optional comma after the call
				while (bi < block.len and (block[bi] == ',' or block[bi] == ' ' or
					block[bi] == '\t' or block[bi] == '\r' or block[bi] == '\n')) : (bi += 1)
				{}
				continue;
			}

			// Plain token: read until ',' or end-of-block
			const tok_start = bi;
			while (bi < block.len and block[bi] != ',') : (bi += 1) {}
			const tok = std.mem.trim(u8, block[tok_start..bi], " \t\r\n");
			if (bi < block.len) bi += 1; // skip ','
			if (tok.len == 0) continue;
			const v = resolveU32Token(tok) catch continue;
			try vals.append(alloc, v);
		}

		try arrays.append(alloc, .{
			.name = name,
			.values = try vals.toOwnedSlice(alloc),
		});
		offset = close_brace + 2;
	}

	return arrays.toOwnedSlice(alloc);
}

/// Parse all SMModel declarations from src.
/// Handles both `SMModel const <NAME>` and `const SMModel <NAME>` spellings.
/// Returns a slice of SMModelDecl; caller owns all memory.
pub fn parseSMModels(alloc: std.mem.Allocator, src: []const u8) ![]SMModelDecl {
	var models: std.ArrayListUnmanaged(SMModelDecl) = .empty;
	errdefer {
		for (models.items) |m| freeSMModelDecl(alloc, m);
		models.deinit(alloc);
	}

	const stripped = try stripComments(alloc, src);
	defer alloc.free(stripped);

	// We look for "SMModel const ", "const SMModel ", and bare "SMModel " (non-const form)
	// Three needles — we merge-scan across all styles to handle them in source order.
	const needles = [_][]const u8{ "SMModel const ", "const SMModel ", "SMModel " };
	var offset: usize = 0;

	// We'll collect (position, style-index) pairs and process in order.
	// Simpler: just do two passes and sort — but that's complex. Instead, use a
	// merge-scan: advance offset past whichever hit comes first.
	while (true) {
		// Find the earliest hit across all needle variants
		var best_pos: usize = std.math.maxInt(usize);
		var best_ni: usize = 0;
		for (needles, 0..) |ndl, ni| {
			if (std.mem.indexOfPos(u8, stripped, offset, ndl)) |p| {
				if (p < best_pos) {
					best_pos = p;
					best_ni = ni;
				}
			}
		}
		if (best_pos == std.math.maxInt(usize)) break; // no more matches

		const pos = best_pos;
		const needle = needles[best_ni];
		const after_needle = pos + needle.len;

		// Skip if preceded by "static " → "static const SMModel" (data array, not decl)
		if (pos >= 7) {
			const prefix = stripped[pos - 7 .. pos];
			if (std.mem.eql(u8, prefix, "static ")) {
				offset = after_needle;
				continue;
			}
		}

		// For the bare "SMModel " needle (index 2): skip if what follows is "const "
		// (it will be caught by needle 0 "SMModel const ") or if it's preceded by
		// "const " (it will be caught by needle 1 "const SMModel ").
		if (best_ni == 2) {
			// Check what immediately follows the needle
			if (std.mem.startsWith(u8, stripped[after_needle..], "const ")) {
				offset = after_needle;
				continue;
			}
			// Check if preceded by "const " (= part of "const SMModel " match)
			if (pos >= 6) {
				const prefix6 = stripped[pos - 6 .. pos];
				if (std.mem.eql(u8, prefix6, "const ")) {
					offset = after_needle;
					continue;
				}
			}
		}

		// Read the variable name up to '='
		const eq = std.mem.indexOfScalarPos(u8, stripped, after_needle, '=') orelse {
			offset = after_needle;
			continue;
		};
		const var_name_raw = std.mem.trim(u8, stripped[after_needle..eq], " \t\r\n");
		const var_name = try alloc.dupe(u8, var_name_raw);
		errdefer alloc.free(var_name);

		// Find the opening '{'
		const open = std.mem.indexOfScalarPos(u8, stripped, eq, '{') orelse {
			alloc.free(var_name);
			offset = after_needle;
			continue;
		};
		// Find the matching closing '};'
		const close_brace = std.mem.indexOfPos(u8, stripped, open + 1, "};") orelse {
			alloc.free(var_name);
			offset = after_needle;
			continue;
		};
		const block = stripped[open + 1 .. close_brace];

		// The SMModel struct has this layout (C source):
		//   { class_table_pckint, class_factor, state_table_pckint, char_len_ref, name }
		// where each pckint is itself a nested { ... } brace.
		// Strategy: collect brace-aware "top-level" comma-separated fields.
		const decl_opt = parseSMModelBlock(alloc, var_name, block) catch |err| {
			alloc.free(var_name);
			std.debug.print("WARNING: failed to parse SMModel '{s}': {}\n", .{ var_name_raw, err });
			offset = close_brace + 2;
			continue;
		};
		if (decl_opt) |decl| {
			try models.append(alloc, decl);
		} else {
			alloc.free(var_name);
		}
		offset = close_brace + 2;
	}

	return models.toOwnedSlice(alloc);
}

/// Free all memory owned by an SMModelDecl.
pub fn freeSMModelDecl(alloc: std.mem.Allocator, m: SMModelDecl) void {
	alloc.free(m.var_name);
	for (m.class_descriptors) |d| alloc.free(d);
	alloc.free(m.class_data_ref);
	for (m.state_descriptors) |d| alloc.free(d);
	alloc.free(m.state_data_ref);
	alloc.free(m.char_len_ref);
	alloc.free(m.name);
}

/// Parse the brace body of an SMModel struct literal.
/// Returns null if the block cannot be parsed.
fn parseSMModelBlock(alloc: std.mem.Allocator, var_name: []const u8, block: []const u8) !?SMModelDecl {
	// The struct body has 5 top-level elements separated by top-level commas:
	//   0: { idxSft, sftMsk, bitSft, unitMsk, cls_array }   (class_table pckint)
	//   1: class_factor  (plain integer)
	//   2: { idxSft, sftMsk, bitSft, unitMsk, st_array }    (state_table pckint)
	//   3: char_len_ref  (bare identifier)
	//   4: "encoding-name"  (string literal)
	//
	// We split on top-level commas (depth-tracking for nested braces).

	var fields: std.ArrayListUnmanaged([]const u8) = .empty;
	defer fields.deinit(alloc);

	var depth: usize = 0;
	var fi_start: usize = 0;
	var i: usize = 0;
	while (i < block.len) : (i += 1) {
		const c = block[i];
		if (c == '{') {
			depth += 1;
		} else if (c == '}') {
			if (depth > 0) depth -= 1;
		} else if (c == ',' and depth == 0) {
			const field = std.mem.trim(u8, block[fi_start..i], " \t\r\n");
			try fields.append(alloc, field);
			fi_start = i + 1;
		}
	}
	// Last field (after final comma or the whole block if no comma)
	const last = std.mem.trim(u8, block[fi_start..], " \t\r\n");
	if (last.len > 0) try fields.append(alloc, last);

	if (fields.items.len < 5) return null;

	// Field 0: class_table pckint { idxSft, sftMsk, bitSft, unitMsk, data_ref }
	const cls_decl = try parsePckIntField(alloc, fields.items[0]) orelse return null;
	errdefer {
		for (cls_decl.descriptors) |d| alloc.free(d);
		alloc.free(cls_decl.data_ref);
	}

	// Field 1: class_factor
	const cf_str = std.mem.trim(u8, fields.items[1], " \t\r\n");
	const class_factor = std.fmt.parseInt(u32, cf_str, 10) catch return null;

	// Field 2: state_table pckint
	const st_decl = try parsePckIntField(alloc, fields.items[2]) orelse return null;
	errdefer {
		for (st_decl.descriptors) |d| alloc.free(d);
		alloc.free(st_decl.data_ref);
	}

	// Field 3: char_len_ref (bare identifier)
	const char_len_ref_raw = std.mem.trim(u8, fields.items[3], " \t\r\n");
	const char_len_ref = try alloc.dupe(u8, char_len_ref_raw);
	errdefer alloc.free(char_len_ref);

	// Field 4: encoding name (string literal, may have trailing comma-less tokens)
	// Join remaining fields in case the name contains commas (unlikely but safe).
	var name_str = std.mem.trim(u8, fields.items[4], " \t\r\n");
	// Strip surrounding quotes
	if (name_str.len >= 2 and name_str[0] == '"') {
		name_str = name_str[1..];
		if (name_str.len > 0 and name_str[name_str.len - 1] == '"')
			name_str = name_str[0 .. name_str.len - 1];
	}
	const enc_name = try alloc.dupe(u8, name_str);
	errdefer alloc.free(enc_name);

	return SMModelDecl{
		.var_name = var_name,
		.class_descriptors = cls_decl.descriptors,
		.class_data_ref = cls_decl.data_ref,
		.class_factor = class_factor,
		.state_descriptors = st_decl.descriptors,
		.state_data_ref = st_decl.data_ref,
		.char_len_ref = char_len_ref,
		.name = enc_name,
	};
}

const PckIntField = struct {
	descriptors: [4][]const u8,
	data_ref: []const u8,
};

/// Parse a pckint initialiser: `{ idxSft, sftMsk, bitSft, unitMsk, data_ref }`.
/// `field` is the raw brace-including text. Returns null on failure.
fn parsePckIntField(alloc: std.mem.Allocator, field: []const u8) !?PckIntField {
	const trimmed = std.mem.trim(u8, field, " \t\r\n");
	if (trimmed.len < 2 or trimmed[0] != '{') return null;
	// Strip outer braces
	const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t\r\n");

	// Split on commas (no nested braces expected here)
	var parts: [5][]const u8 = undefined;
	var pi: usize = 0;
	var it = std.mem.splitScalar(u8, inner, ',');
	while (it.next()) |raw| {
		if (pi >= 5) break;
		parts[pi] = std.mem.trim(u8, raw, " \t\r\n");
		pi += 1;
	}
	if (pi < 5) return null;

	var descriptors: [4][]const u8 = undefined;
	for (parts[0..4], 0..) |p, di| {
		descriptors[di] = try alloc.dupe(u8, p);
	}
	errdefer for (descriptors) |d| alloc.free(d);

	const data_ref = try alloc.dupe(u8, parts[4]);
	return PckIntField{ .descriptors = descriptors, .data_ref = data_ref };
}
