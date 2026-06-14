//! Shared emission helpers for the table generator: the license/provenance
//! header that every generated table file must carry, plus the Zig-literal
//! emitters for order maps, matrices, and SequenceModel struct literals.
//!
//! This file is generator code (new, non-derivative), but the headers it emits
//! reproduce the upstream tri-license onto the generated derivative tables.

const std = @import("std");

/// License + provenance header prepended to every generated table file. The
/// generated tables are a derivative of uchardet's copyrighted data, so they
/// carry the upstream tri-license verbatim.
pub const LICENSE_HEADER =
	\\// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
	\\//
	\\// This file is part of chardetz, a C++→Zig translation of uchardet
	\\// (https://github.com/pmarreck/uchardetz), itself derived from Mozilla's
	\\// universalchardet. The Original Code is Mozilla Universal charset detector
	\\// code; Initial Developer: Netscape Communications Corporation (© 2001).
	\\// Contributor: BYVoid <byvoid.kcp@gmail.com>.
	\\//
	\\// Tri-licensed MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later. See COPYING.
	\\
;

/// Provenance line marking a file as machine-generated from the pinned source.
/// Callers append the specific upstream filename.
pub const GENERATED_PREFIX = "// @generated from ";
pub const PINNED_COMMIT = "abacfc1fc86ef7618547d7dce7cc7501e756fa31";

/// Write the standard header (license + a `@generated from <src> @ <commit>`
/// line + "do not edit") to `w` for a file generated from `upstream_src`.
/// `w` must be an anytype writer with `.print()` and `.writeAll()` methods.
pub fn writeHeader(w: anytype, upstream_src: []const u8) !void {
	try w.writeAll(LICENSE_HEADER);
	try w.print("//\n{s}{s} @ {s} — do not edit (regenerate via `zig build gen-tables`).\n\n", .{
		GENERATED_PREFIX, upstream_src, PINNED_COMMIT,
	});
}

/// Emit a [256]u8 order map constant.
/// `w` must be an anytype writer with `.print()` and `.writeAll()` methods.
pub fn emitOrderMap(w: anytype, name: []const u8, vals: [256]u8) !void {
	try w.print("pub const {s} = [256]u8{{", .{name});
	for (vals, 0..) |v, i| {
		if (i % 16 == 0) try w.writeAll("\n\t");
		try w.print("{d}", .{v});
		if (i < 255) try w.writeAll(",");
		if (i % 16 == 15 and i < 255) try w.writeAll(" //");
	}
	try w.writeAll("\n};\n\n");
}

/// Emit a [_]u8 matrix constant.
/// `w` must be an anytype writer with `.print()` and `.writeAll()` methods.
pub fn emitMatrix(w: anytype, name: []const u8, vals: []const u8) !void {
	try w.print("pub const {s} = [_]u8{{", .{name});
	for (vals, 0..) |v, i| {
		if (i % 16 == 0) try w.writeAll("\n\t");
		try w.print("{d}", .{v});
		if (i < vals.len - 1) try w.writeAll(",");
	}
	try w.writeAll("\n};\n\n");
}

/// Emit a SequenceModel struct literal.
/// Uses anytype so emit.zig need not import parse_sbcs; any struct with the
/// expected fields (var_name, map_ref, matrix_ref, freq_char_count,
/// typical_positive_ratio, keep_english_letter, charset_name) is accepted.
/// `w` must be an anytype writer with `.print()` methods.
pub fn emitSequenceModel(w: anytype, model: anytype) !void {
	try w.print("pub const {s} = sbcs_model.SequenceModel{{\n", .{model.var_name});
	try w.print("\t.char_to_order_map = &{s},\n", .{model.map_ref});
	try w.print("\t.precedence_matrix = &{s},\n", .{model.matrix_ref});
	try w.print("\t.freq_char_count = {d},\n", .{model.freq_char_count});
	try w.print("\t.typical_positive_ratio = {d:.9},\n", .{model.typical_positive_ratio});
	try w.print("\t.keep_english_letter = {s},\n", .{if (model.keep_english_letter) "true" else "false"});
	try w.print("\t.charset_name = \"{s}\",\n", .{model.charset_name});
	try w.writeAll("};\n\n");
}

/// Emit a `[N]u32` packed integer array constant (used for class/state tables).
/// Values are emitted as hex literals for readability.
/// `w` must be an anytype writer with `.print()` and `.writeAll()` methods.
pub fn emitU32Array(w: anytype, name: []const u8, vals: []const u32) !void {
	try w.print("pub const {s} = [{}]u32{{", .{ name, vals.len });
	for (vals, 0..) |v, i| {
		if (i % 8 == 0) try w.writeAll("\n\t");
		try w.print("0x{X:0>8}", .{v});
		if (i < vals.len - 1) try w.writeAll(",");
	}
	try w.writeAll("\n};\n\n");
}

/// Emit a state_machine.SMModel struct literal referencing previously-emitted arrays.
/// Uses anytype so emit.zig need not import parse_sm; any struct with the expected
/// fields (var_name, class_descriptors[4], class_data_ref, class_factor,
/// state_descriptors[4], state_data_ref, char_len_ref, name) is accepted.
/// `w` must be an anytype writer with `.print()` and `.writeAll()` methods.
pub fn emitSMModel(w: anytype, model: anytype) !void {
	try w.print("pub const {s} = state_machine.SMModel{{\n", .{model.var_name});
	try w.writeAll("\t.class_table = .{\n");
	try w.print("\t\t.idx_sft = state_machine.{s},\n", .{model.class_descriptors[0]});
	try w.print("\t\t.sft_msk = state_machine.{s},\n", .{model.class_descriptors[1]});
	try w.print("\t\t.bit_sft = state_machine.{s},\n", .{model.class_descriptors[2]});
	try w.print("\t\t.unit_msk = state_machine.{s},\n", .{model.class_descriptors[3]});
	try w.print("\t\t.data = &{s},\n", .{model.class_data_ref});
	try w.writeAll("\t},\n");
	try w.print("\t.class_factor = {d},\n", .{model.class_factor});
	try w.writeAll("\t.state_table = .{\n");
	try w.print("\t\t.idx_sft = state_machine.{s},\n", .{model.state_descriptors[0]});
	try w.print("\t\t.sft_msk = state_machine.{s},\n", .{model.state_descriptors[1]});
	try w.print("\t\t.bit_sft = state_machine.{s},\n", .{model.state_descriptors[2]});
	try w.print("\t\t.unit_msk = state_machine.{s},\n", .{model.state_descriptors[3]});
	try w.print("\t\t.data = &{s},\n", .{model.state_data_ref});
	try w.writeAll("\t},\n");
	try w.print("\t.char_len_table = &{s},\n", .{model.char_len_ref});
	try w.print("\t.name = \"{s}\",\n", .{model.name});
	try w.writeAll("};\n\n");
}
