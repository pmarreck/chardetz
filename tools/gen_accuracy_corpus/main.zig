//! gen-accuracy-corpus: I/O shell around core.zig.
//! Usage: gen-accuracy-corpus MATRIX UDHR_DATA_DIR OUT_DIR
//! Writes OUT_DIR/<id>.bin for every case, OUT_DIR/prefix.txt (the 64 KiB
//! ASCII prefix) and OUT_DIR/cases.tsv, one line per case:
//!   id  language  encoding  length  acceptable  prefixed_acceptable  normalized
//! where the acceptable columns are comma-separated charset names ("-" when
//! the prefixed variant does not apply) and length is codepoints or "full".
const std = @import("std");
const core = @import("core.zig");
const iconv = @import("iconv.zig");

const max_xml_bytes = 4 << 20;
/// The ASCII prefix fills exactly one of uchardet's 64 KiB reads.
pub const prefix_len = 65536;
const prefix_source_key = "eng";

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var err_buf: [1024]u8 = undefined;
    var err_w = std.Io.File.stderr().writer(io, &err_buf);
    const stderr = &err_w.interface;
    defer stderr.flush() catch {};
    if (args.len != 4) {
        try stderr.writeAll("usage: gen-accuracy-corpus MATRIX UDHR_DATA_DIR OUT_DIR\n");
        return 2;
    }
    const cwd = std.Io.Dir.cwd();
    const matrix_text = try cwd.readFileAlloc(io, args[1], gpa, .limited(1 << 20));
    defer gpa.free(matrix_text);
    var matrix = try core.parseMatrix(gpa, matrix_text);
    defer matrix.deinit(gpa);
    var udhr = try cwd.openDir(io, args[2], .{ .iterate = true });
    defer udhr.close(io);
    var out_dir = try cwd.createDirPathOpen(io, args[3], .{});
    defer out_dir.close(io);

    var gen: Generator = .{ .gpa = gpa, .io = io, .udhr = udhr, .out = out_dir, .matrix = &matrix, .t = iconv.transcoder() };
    defer gen.deinit();

    const eng = try gen.text(prefix_source_key);
    defer gpa.free(eng);
    gen.prefix = try core.asciiPrefix(gpa, eng, prefix_len);
    try out_dir.writeFile(io, .{ .sub_path = "prefix.txt", .data = gen.prefix });

    for (matrix.texts) |t| for (t.encodings) |e| try gen.cases(t.key, t.language, e);
    if (matrix.utf8_all) {
        const keys = try udhrKeys(gpa, io, udhr);
        defer {
            for (keys) |k| gpa.free(k);
            gpa.free(keys);
        }
        for (keys) |k| try gen.cases(k, k, "UTF-8");
    }
    try out_dir.writeFile(io, .{ .sub_path = "cases.tsv", .data = gen.manifest.items });
    const summary = try std.fmt.allocPrint(gpa, "cases {d}\nnormalized {d}\nlossy {d}\nskipped {d}\n", .{ gen.count, gen.normalized, gen.lossy, gen.skipped });
    defer gpa.free(summary);
    try out_dir.writeFile(io, .{ .sub_path = "summary.txt", .data = summary });
    return 0;
}

/// Every udhr_<key>.xml in the directory, sorted.
fn udhrKeys(gpa: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) ![][]const u8 {
    var keys: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (keys.items) |k| gpa.free(k);
        keys.deinit(gpa);
    }
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, entry.name, "udhr_") or !std.mem.endsWith(u8, entry.name, ".xml")) continue;
        try keys.append(gpa, try gpa.dupe(u8, entry.name["udhr_".len .. entry.name.len - ".xml".len]));
    }
    std.mem.sort([]const u8, keys.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return keys.toOwnedSlice(gpa);
}

const Generator = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    udhr: std.Io.Dir,
    out: std.Io.Dir,
    matrix: *const core.Matrix,
    t: core.Transcoder,
    prefix: []u8 = &.{},
    manifest: std.ArrayList(u8) = .empty,
    count: usize = 0,
    normalized: usize = 0,
    lossy: usize = 0,
    skipped: usize = 0,

    fn deinit(g: *Generator) void {
        g.gpa.free(g.prefix);
        g.manifest.deinit(g.gpa);
    }

    fn text(g: *Generator, key: []const u8) ![]u8 {
        const name = try std.fmt.allocPrint(g.gpa, "udhr_{s}.xml", .{key});
        defer g.gpa.free(name);
        const xml = try g.udhr.readFileAlloc(g.io, name, g.gpa, .limited(max_xml_bytes));
        defer g.gpa.free(xml);
        return core.extractText(g.gpa, xml);
    }

    /// One case per matrix length for text `key` in `encoding`. Lengths at or
    /// beyond the text's own length are covered by "full" and skipped.
    fn cases(g: *Generator, key: []const u8, language: []const u8, encoding: []const u8) !void {
        const raw = try g.text(key);
        defer g.gpa.free(raw);
        // UTF-8 cases keep the source text exactly as published.
        const via = if (std.mem.eql(u8, encoding, "UTF-8")) null else g.matrix.composeVia(key);
        const composed = if (via) |v| try compose(g.gpa, g.t, raw, v) else null;
        defer if (composed) |c| g.gpa.free(c);
        const whole = composed orelse raw;
        const total = core.codepointCount(whole);
        for (g.matrix.lengths) |len| {
            if (len) |n| if (n >= total) continue;
            const cut = if (len) |n| core.prefixCodepoints(whole, n) else whole;
            var c = (try core.encodeCase(g.gpa, g.t, cut, encoding)) orelse {
                g.skipped += 1;
                continue;
            };
            defer c.deinit(g.gpa);
            switch (c.fidelity) {
                .exact => {},
                .normalized => g.normalized += 1,
                .lossy => g.lossy += 1,
            }

            var len_buf: [20]u8 = undefined;
            const len_label = if (len) |n| try std.fmt.bufPrint(&len_buf, "{d}", .{n}) else "full";
            const id = try std.fmt.allocPrint(g.gpa, "{s}/{s}/{s}", .{ key, encoding, len_label });
            defer g.gpa.free(id);
            const file = try std.fmt.allocPrint(g.gpa, "{s}.bin", .{id});
            defer g.gpa.free(file);
            if (std.fs.path.dirname(file)) |d| try g.out.createDirPath(g.io, d);
            try g.out.writeFile(g.io, .{ .sub_path = file, .data = c.bytes });

            const ok = try core.acceptable(g.gpa, g.t, c.bytes, c.truth, g.matrix.candidates);
            defer g.gpa.free(ok);
            const w = &g.manifest;
            try w.print(g.gpa, "{s}\t{s}\t{s}\t{s}\t", .{ id, language, encoding, len_label });
            try writeList(g.gpa, w, ok);
            try w.append(g.gpa, '\t');
            if (core.asciiCompatible(encoding)) {
                const joined = try std.mem.concat(g.gpa, u8, &.{ g.prefix, c.bytes });
                defer g.gpa.free(joined);
                const truth = try std.mem.concat(g.gpa, u8, &.{ g.prefix, c.truth });
                defer g.gpa.free(truth);
                const pok = try core.acceptable(g.gpa, g.t, joined, truth, g.matrix.candidates);
                defer g.gpa.free(pok);
                try writeList(g.gpa, w, pok);
            } else try w.append(g.gpa, '-');
            try w.print(g.gpa, "\t{s}\n", .{@tagName(c.fidelity)});
            g.count += 1;
        }
    }
};

fn writeList(gpa: std.mem.Allocator, w: *std.ArrayList(u8), names: []const []const u8) !void {
    if (names.len == 0) return w.append(gpa, '-');
    for (names, 0..) |n, i| {
        if (i > 0) try w.append(gpa, ',');
        try w.appendSlice(gpa, n);
    }
}

/// `text` after a round trip through charset `via` (see core.Compose).
fn compose(gpa: std.mem.Allocator, t: core.Transcoder, text: []const u8, via: []const u8) ![]u8 {
    const bytes = try t.convert(gpa, "UTF-8", via, text);
    defer gpa.free(bytes);
    return t.convert(gpa, via, "UTF-8", bytes);
}
