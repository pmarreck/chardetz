//! SBCS + SM table generator entry point. Reads uchardet LangModel and state-machine
//! C++ source files and emits Zig equivalents into src/tables/.
//!
//! Usage: gen-tables [upstream_src_dir] [out_dir]
//! Defaults: upstream_src_dir = manifest.UPSTREAM_SRC, out_dir = "src/tables"

const std = @import("std");
const manifest = @import("manifest.zig");
const parse_sbcs = @import("parse_sbcs.zig");
const parse_sm = @import("parse_sm.zig");
const emit_mod = @import("emit.zig");

pub fn main(init: std.process.Init) !void {
	const io = init.io;
	const alloc = init.gpa; // init.gpa is already a std.mem.Allocator
	const args = try init.minimal.args.toSlice(init.arena.allocator());

	const upstream_src = if (args.len > 1) args[1] else manifest.UPSTREAM_SRC;
	const out_dir_path = if (args.len > 2) args[2] else "src/tables";

	// Create output directories
	const cwd = std.Io.Dir.cwd();
	const sbcs_dir_path = try std.fmt.allocPrint(alloc, "{s}/sbcs", .{out_dir_path});
	defer alloc.free(sbcs_dir_path);

	cwd.createDirPath(io, sbcs_dir_path) catch |err| switch (err) {
		error.PathAlreadyExists => {},
		else => return err,
	};

	// Track all lang names for the re-export file
	var lang_names: std.ArrayListUnmanaged([]const u8) = .empty;
	defer {
		for (lang_names.items) |n| alloc.free(n);
		lang_names.deinit(alloc);
	}

	var total_models: usize = 0;

	for (manifest.sbcs_sources) |rel_path| {
		// Derive lang name: "LangModels/LangDanishModel.cpp" -> "danish"
		const basename = std.fs.path.basename(rel_path);
		// Strip "Lang" prefix and "Model.cpp" suffix
		const without_lang = if (std.mem.startsWith(u8, basename, "Lang")) basename[4..] else basename;
		const without_suffix = if (std.mem.endsWith(u8, without_lang, "Model.cpp"))
			without_lang[0 .. without_lang.len - "Model.cpp".len]
		else
			without_lang;
		var lang_name_buf: [64]u8 = undefined;
		const lang_name_lower = std.ascii.lowerString(&lang_name_buf, without_suffix);
		const lang_name = try alloc.dupe(u8, lang_name_lower);
		errdefer alloc.free(lang_name);

		// Read source file
		const src_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ upstream_src, rel_path });
		defer alloc.free(src_path);

		const src_content = cwd.readFileAlloc(io, src_path, alloc, .unlimited) catch |err| {
			std.debug.print("ERROR: failed to read {s}: {}\n", .{ src_path, err });
			alloc.free(lang_name);
			continue;
		};
		defer alloc.free(src_content);

		// Parse
		const order_maps = try parse_sbcs.parseOrderMaps(alloc, src_content);
		defer {
			for (order_maps) |m| alloc.free(m.name);
			alloc.free(order_maps);
		}

		const lang_mats = try parse_sbcs.parseLangModels(alloc, src_content);
		defer {
			for (lang_mats) |m| {
				alloc.free(m.name);
				alloc.free(m.values);
			}
			alloc.free(lang_mats);
		}

		const seq_models = try parse_sbcs.parseSequenceModels(alloc, src_content);
		defer {
			for (seq_models) |m| {
				alloc.free(m.var_name);
				alloc.free(m.map_ref);
				alloc.free(m.matrix_ref);
				alloc.free(m.charset_name);
			}
			alloc.free(seq_models);
		}

		total_models += seq_models.len;

		// Write src/tables/sbcs/<lang>.zig
		const out_file_path = try std.fmt.allocPrint(alloc, "{s}/{s}.zig", .{ sbcs_dir_path, lang_name });
		defer alloc.free(out_file_path);

		const out_file = try cwd.createFile(io, out_file_path, .{});
		defer out_file.close(io);

		var out_buf: [65536]u8 = undefined;
		var fw = out_file.writer(io, &out_buf);
		const w = &fw.interface;

		// Header
		try emit_mod.writeHeader(w, rel_path);
		// Import sbcs_model
		try w.writeAll("const sbcs_model = @import(\"../../sbcs_model.zig\");\n\n");

		// Order maps
		for (order_maps) |om| {
			try emit_mod.emitOrderMap(w, om.name, om.values);
		}

		// Lang matrices
		for (lang_mats) |lm| {
			try emit_mod.emitMatrix(w, lm.name, lm.values);
		}

		// Sequence models
		for (seq_models) |sm| {
			try emit_mod.emitSequenceModel(w, sm);
		}

		try w.flush();

		try lang_names.append(alloc, lang_name);
		std.debug.print("Generated {s} ({d} maps, {d} matrices, {d} models)\n", .{
			out_file_path, order_maps.len, lang_mats.len, seq_models.len,
		});
	}

	// Write src/tables/sbcs.zig re-export
	const sbcs_reexport_path = try std.fmt.allocPrint(alloc, "{s}/sbcs.zig", .{out_dir_path});
	defer alloc.free(sbcs_reexport_path);

	{
		const f = try cwd.createFile(io, sbcs_reexport_path, .{});
		defer f.close(io);
		var out_buf: [16384]u8 = undefined;
		var fw = f.writer(io, &out_buf);
		const w = &fw.interface;
		try w.writeAll("// @generated — do not edit (regenerate via `zig build gen-tables`).\n");
		for (lang_names.items) |n| {
			try w.print("pub const {s} = @import(\"sbcs/{s}.zig\");\n", .{ n, n });
		}
		try w.flush();
	}

	// ── SM table generation ────────────────────────────────────────────────────
	// Map from sm_sources filename to output file stem
	const sm_out_stems = [_][]const u8{ "mbcs_sm", "esc_sm" };
	var total_sm_models: usize = 0;

	for (manifest.sm_sources, sm_out_stems) |sm_rel, out_stem| {
		const sm_src_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ upstream_src, sm_rel });
		defer alloc.free(sm_src_path);

		const sm_src = cwd.readFileAlloc(io, sm_src_path, alloc, .unlimited) catch |err| {
			std.debug.print("ERROR: failed to read {s}: {}\n", .{ sm_src_path, err });
			continue;
		};
		defer alloc.free(sm_src);

		// Parse arrays and model declarations
		const arrays = try parse_sm.parseU32Arrays(alloc, sm_src);
		defer {
			for (arrays) |a| {
				alloc.free(a.name);
				alloc.free(a.values);
			}
			alloc.free(arrays);
		}

		const sm_models = try parse_sm.parseSMModels(alloc, sm_src);
		defer {
			for (sm_models) |m| parse_sm.freeSMModelDecl(alloc, m);
			alloc.free(sm_models);
		}

		total_sm_models += sm_models.len;

		// Write src/tables/<stem>.zig
		const sm_out_path = try std.fmt.allocPrint(alloc, "{s}/{s}.zig", .{ out_dir_path, out_stem });
		defer alloc.free(sm_out_path);

		const sm_out_file = try cwd.createFile(io, sm_out_path, .{});
		defer sm_out_file.close(io);

		var sm_buf: [131072]u8 = undefined;
		var sm_fw = sm_out_file.writer(io, &sm_buf);
		const sw = &sm_fw.interface;

		try emit_mod.writeHeader(sw, sm_rel);
		try sw.writeAll("const state_machine = @import(\"../state_machine.zig\");\n\n");

		// Emit all u32 arrays
		for (arrays) |a| {
			try emit_mod.emitU32Array(sw, a.name, a.values);
		}

		// Emit all SMModel declarations
		for (sm_models) |m| {
			try emit_mod.emitSMModel(sw, m);
		}

		try sw.flush();

		std.debug.print("Generated {s} ({d} arrays, {d} SMModels)\n", .{
			sm_out_path, arrays.len, sm_models.len,
		});
	}

	// Write src/tables.zig (includes both sbcs and SM tables)
	const tables_path = try std.fmt.allocPrint(alloc, "{s}/../tables.zig", .{out_dir_path});
	defer alloc.free(tables_path);

	{
		const f = try cwd.createFile(io, tables_path, .{});
		defer f.close(io);
		var out_buf: [4096]u8 = undefined;
		var fw = f.writer(io, &out_buf);
		const w = &fw.interface;
		try w.writeAll("// @generated — do not edit (regenerate via `zig build gen-tables`).\n");
		try w.writeAll("pub const sbcs = @import(\"tables/sbcs.zig\");\n");
		try w.writeAll("pub const mbcs_sm = @import(\"tables/mbcs_sm.zig\");\n");
		try w.writeAll("pub const esc_sm = @import(\"tables/esc_sm.zig\");\n");
		try w.flush();
	}

	std.debug.print("Total: {d} SequenceModels across {d} SBCS files; {d} SMModels across {d} SM files.\n", .{
		total_models, manifest.sbcs_sources.len, total_sm_models, manifest.sm_sources.len,
	});
}
