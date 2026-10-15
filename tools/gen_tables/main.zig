//! gen-tables: I/O adapter around the pure table translator.
//! Usage: gen-tables MANIFEST UPSTREAM_ROOT OUT_DIR [--check | --shims]
//! Default: (re)writes OUT_DIR/<stem>.zig and OUT_DIR/all.zig.
//! --check: writes nothing; exits 1 if any committed file is stale.
//! --shims: writes the test-only C++ shims OUT_DIR/shim_<stem>.cpp.
const std = @import("std");
const translate = @import("translate.zig");
const manifest = @import("manifest.zig");

const max_source_bytes = 16 << 20;

const Mode = enum { write, check, shims };

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var err_buf: [1024]u8 = undefined;
    var err_w = std.Io.File.stderr().writer(io, &err_buf);
    const stderr = &err_w.interface;
    defer stderr.flush() catch {};

    const mode: Mode = if (args.len == 4)
        .write
    else if (args.len == 5 and std.mem.eql(u8, args[4], "--check"))
        .check
    else if (args.len == 5 and std.mem.eql(u8, args[4], "--shims"))
        .shims
    else {
        try stderr.writeAll("usage: gen-tables MANIFEST UPSTREAM_ROOT OUT_DIR [--check | --shims]\n");
        return 2;
    };
    const check = mode == .check;
    const cwd = std.Io.Dir.cwd();

    const manifest_text = try cwd.readFileAlloc(io, args[1], gpa, .limited(max_source_bytes));
    defer gpa.free(manifest_text);
    var m = try manifest.parse(gpa, manifest_text);
    defer m.deinit(gpa);

    var upstream = try cwd.openDir(io, args[2], .{});
    defer upstream.close(io);
    var out_dir = if (check) try cwd.openDir(io, args[3], .{}) else try cwd.createDirPathOpen(io, args[3], .{});
    defer out_dir.close(io);

    var symbols: translate.Symbols = .empty;
    defer symbols.deinit(gpa);
    for (m.headers) |h| {
        const text = try upstream.readFileAlloc(io, h, gpa, .limited(max_source_bytes));
        defer gpa.free(text);
        translate.collectHeaderSymbols(gpa, &symbols, text) catch |e| {
            try stderr.print("gen-tables: {s}: {s}\n", .{ h, @errorName(e) });
            return 1;
        };
    }

    var stale: usize = 0;
    for (m.tables) |t| {
        const text = try upstream.readFileAlloc(io, t.source, gpa, .limited(max_source_bytes));
        defer gpa.free(text);
        var translated = translate.translateDetailed(gpa, &symbols, text, .{ .source_path = t.source, .source_rev = m.rev }) catch |e| {
            try stderr.print("gen-tables: {s}: {s}\n", .{ t.source, @errorName(e) });
            return 1;
        };
        defer translated.deinit(gpa);
        if (mode == .shims) {
            const include = try std.fs.path.join(gpa, &.{ args[2], t.source });
            defer gpa.free(include);
            const shim = try translate.renderShim(gpa, t.stem, include, translated.emitted);
            defer gpa.free(shim);
            const shim_name = try std.fmt.allocPrint(gpa, "shim_{s}.cpp", .{t.stem});
            defer gpa.free(shim_name);
            try out_dir.writeFile(io, .{ .sub_path = shim_name, .data = shim });
            continue;
        }
        const name = try std.fmt.allocPrint(gpa, "{s}.zig", .{t.stem});
        defer gpa.free(name);
        stale += try emit(io, gpa, out_dir, name, translated.zig, check, stderr);
    }
    if (mode == .shims) return 0;

    const index = try manifest.renderIndex(gpa, m);
    defer gpa.free(index);
    stale += try emit(io, gpa, out_dir, "all.zig", index, check, stderr);

    if (check and stale != 0) {
        try stderr.print("gen-tables: {d} generated file(s) stale; run `zig build gen-tables`\n", .{stale});
        return 1;
    }
    return 0;
}

/// Writes `content` to `name`, or in check mode compares it and reports a mismatch.
fn emit(io: std.Io, gpa: std.mem.Allocator, dir: std.Io.Dir, name: []const u8, content: []const u8, check: bool, stderr: *std.Io.Writer) !usize {
    if (!check) {
        try dir.writeFile(io, .{ .sub_path = name, .data = content });
        return 0;
    }
    const existing = dir.readFileAlloc(io, name, gpa, .limited(max_source_bytes)) catch |e| switch (e) {
        error.FileNotFound => {
            try stderr.print("gen-tables: missing {s}\n", .{name});
            return 1;
        },
        else => return e,
    };
    defer gpa.free(existing);
    if (std.mem.eql(u8, existing, content)) return 0;
    try stderr.print("gen-tables: stale {s}\n", .{name});
    return 1;
}
