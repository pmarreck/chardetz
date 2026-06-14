//! Unit tests for emit helpers.
const std = @import("std");
const gen_tables = @import("gen_tables");
const emit = gen_tables.emit;

test "writeHeader produces license prefix" {
	var buf: [4096]u8 = undefined;
	var w: std.Io.Writer = .fixed(&buf);
	try emit.writeHeader(&w, "LangModels/LangFrenchModel.cpp");
	const written = w.buffered();
	try std.testing.expect(std.mem.indexOf(u8, written, "SPDX-License-Identifier") != null);
	try std.testing.expect(std.mem.indexOf(u8, written, "@generated from") != null);
	try std.testing.expect(std.mem.indexOf(u8, written, "LangModels/LangFrenchModel.cpp") != null);
}

test "emitOrderMap produces valid Zig literal" {
	var buf: [8192]u8 = undefined;
	var w: std.Io.Writer = .fixed(&buf);
	var vals: [256]u8 = undefined;
	for (&vals, 0..) |*v, i| v.* = @intCast(i % 256);
	try emit.emitOrderMap(&w, "TestMap", vals);
	const written = w.buffered();
	try std.testing.expect(std.mem.indexOf(u8, written, "pub const TestMap = [256]u8{") != null);
}

test "emitMatrix produces valid Zig literal" {
	var buf: [8192]u8 = undefined;
	var w: std.Io.Writer = .fixed(&buf);
	const vals = [_]u8{ 3, 2, 1, 0 };
	try emit.emitMatrix(&w, "TestMatrix", &vals);
	const written = w.buffered();
	try std.testing.expect(std.mem.indexOf(u8, written, "pub const TestMatrix = [_]u8{") != null);
	try std.testing.expect(std.mem.indexOf(u8, written, "3,") != null);
}
