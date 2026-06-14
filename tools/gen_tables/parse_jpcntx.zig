//! Parser for the uchardet JpCntx.cpp 2D hiragana context table.
//!
//! Extracts `const PRUint8 jp2CharContext[R][C] = { { ... }, ... };` and
//! flattens the 2D array into a single row-major `[]u8` slice.
//! The real table is 83×83 (= 6 889 entries).

const std = @import("std");

pub const Jp2dTable = struct {
	rows: usize,
	cols: usize,
	/// Row-major flat array: values[row * cols + col].
	values: []u8,
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

/// Parse a `const PRUint8 <name>[R][C] = { { ... }, ... };` declaration.
///
/// Returns a `Jp2dTable` with `rows`, `cols`, and a row-major flat `values`
/// slice of length `rows * cols`.  Caller owns all returned memory.
pub fn parseJp2dTable(alloc: std.mem.Allocator, src: []const u8) !Jp2dTable {
	// Strip comments first.
	const stripped = try stripComments(alloc, src);
	defer alloc.free(stripped);

	// Locate `[R][C]` — find a `PRUint8` declaration, then two bracketed ints.
	// Pattern: "PRUint8 <name>[<R>][<C>]"
	const needle = "PRUint8 ";
	const decl_pos = std.mem.indexOf(u8, stripped, needle) orelse
		return error.MissingPRUint8Declaration;
	const after_needle = decl_pos + needle.len;

	// Find first '[' — start of [R]
	const r_open = std.mem.indexOfScalarPos(u8, stripped, after_needle, '[') orelse
		return error.MissingRowDimension;
	const r_close = std.mem.indexOfScalarPos(u8, stripped, r_open + 1, ']') orelse
		return error.MissingRowDimensionClose;
	const rows = std.fmt.parseInt(usize, std.mem.trim(u8, stripped[r_open + 1 .. r_close], " \t"), 10) catch
		return error.BadRowDimension;

	// Find second '[' — start of [C]
	const c_open = std.mem.indexOfScalarPos(u8, stripped, r_close + 1, '[') orelse
		return error.MissingColDimension;
	const c_close = std.mem.indexOfScalarPos(u8, stripped, c_open + 1, ']') orelse
		return error.MissingColDimensionClose;
	const cols = std.fmt.parseInt(usize, std.mem.trim(u8, stripped[c_open + 1 .. c_close], " \t"), 10) catch
		return error.BadColDimension;

	// Find the outer '=' then the outer '{'
	const eq = std.mem.indexOfScalarPos(u8, stripped, c_close, '=') orelse
		return error.MissingEquals;
	const outer_open = std.mem.indexOfScalarPos(u8, stripped, eq, '{') orelse
		return error.MissingOuterBrace;

	// Find the matching outer '}' by tracking brace depth.
	var depth: usize = 0;
	var outer_close: usize = outer_open;
	var i: usize = outer_open;
	while (i < stripped.len) : (i += 1) {
		if (stripped[i] == '{') {
			depth += 1;
		} else if (stripped[i] == '}') {
			depth -= 1;
			if (depth == 0) {
				outer_close = i;
				break;
			}
		}
	}
	if (depth != 0) return error.UnterminatedOuterBrace;

	// Now parse each inner row `{ v0, v1, ... }`.
	var vals: std.ArrayListUnmanaged(u8) = .empty;
	errdefer vals.deinit(alloc);

	const outer_body = stripped[outer_open + 1 .. outer_close];
	var bi: usize = 0;
	while (bi < outer_body.len) {
		// Skip whitespace and commas between rows
		while (bi < outer_body.len and
			(outer_body[bi] == ' ' or outer_body[bi] == '\t' or
			outer_body[bi] == '\r' or outer_body[bi] == '\n' or
			outer_body[bi] == ',')) : (bi += 1)
		{}
		if (bi >= outer_body.len) break;
		if (outer_body[bi] != '{') {
			bi += 1;
			continue;
		}
		// Find the closing '}' of this row (no nested braces expected).
		const row_open = bi;
		const row_close = std.mem.indexOfScalarPos(u8, outer_body, row_open + 1, '}') orelse
			return error.UnterminatedRowBrace;
		const row_body = outer_body[row_open + 1 .. row_close];

		// Parse comma-separated u8 values within this row.
		var it = std.mem.tokenizeScalar(u8, row_body, ',');
		while (it.next()) |raw_tok| {
			const tok = std.mem.trim(u8, raw_tok, " \t\r\n");
			if (tok.len == 0) continue;
			const v = std.fmt.parseInt(u8, tok, 10) catch |err| return err;
			try vals.append(alloc, v);
		}

		bi = row_close + 1;
	}

	if (vals.items.len != rows * cols) return error.ValueCountMismatch;

	return Jp2dTable{
		.rows = rows,
		.cols = cols,
		.values = try vals.toOwnedSlice(alloc),
	};
}

/// Free all memory owned by a Jp2dTable.
pub fn freeJp2dTable(alloc: std.mem.Allocator, t: Jp2dTable) void {
	alloc.free(t.values);
}
