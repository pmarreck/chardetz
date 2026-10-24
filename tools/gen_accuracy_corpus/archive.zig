//! In-memory form of the committed accuracy corpus: a tar of name to bytes,
//! zstd-compressed in the repository. Reading it needs no tar or zstd tools
//! (std.compress.zstd and std.tar) and writes nothing to disk.
const std = @import("std");

/// Archive member names to contents, in archive order.
pub const Files = std.StringArrayHashMapUnmanaged([]const u8);

pub const Difference = struct {
    name: []const u8,
    kind: enum { missing, extra, changed },
};

/// Decompresses a zstd-compressed tar and returns its regular files. Names
/// and contents are allocated in `arena`.
pub fn unpack(arena: std.mem.Allocator, compressed: []const u8) error{ BadArchive, OutOfMemory }!Files {
    var in: std.Io.Reader = .fixed(compressed);
    // std does not verify zstd checksums yet (it panics if asked); git already
    // hashes the committed file.
    var zstd: std.compress.zstd.Decompress = .init(&in, &.{}, .{});
    var out: std.Io.Writer.Allocating = .init(arena);
    _ = zstd.reader.streamRemaining(&out.writer) catch |e| switch (e) {
        error.WriteFailed => return error.OutOfMemory,
        error.ReadFailed => return error.BadArchive,
    };
    // A truncated stream can end cleanly between frames; a corpus is never empty.
    if (out.written().len == 0) return error.BadArchive;
    return parseTar(arena, out.written()) catch |e| switch (e) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.BadArchive,
    };
}

/// Regular files of an uncompressed tar (ustar, GNU or pax headers).
/// Directories and links are skipped.
pub fn parseTar(arena: std.mem.Allocator, tar: []const u8) !Files {
    var in: std.Io.Reader = .fixed(tar);
    var name_buf: [std.fs.max_path_bytes]u8 = undefined;
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;
    var it: std.tar.Iterator = .init(&in, .{ .file_name_buffer = &name_buf, .link_name_buffer = &link_buf });
    var files: Files = .empty;
    while (try it.next()) |f| {
        if (f.kind != .file) continue;
        var body: std.Io.Writer.Allocating = .init(arena);
        try it.streamRemaining(f, &body.writer);
        try files.put(arena, try arena.dupe(u8, f.name), body.written());
    }
    return files;
}

/// A deterministic tar of `files` in their map order: mtime 0, default mode,
/// GNU long-name headers for names over the ustar limit.
pub fn pack(arena: std.mem.Allocator, files: Files) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    var w: std.tar.Writer = .{ .underlying_writer = &out.writer };
    for (files.keys(), files.values()) |name, bytes| try w.writeFileBytes(name, bytes, .{});
    try w.finishPedantically();
    return out.written();
}

/// Every name whose contents differ between `expected` and `actual`, sorted
/// by name: missing (only expected), extra (only actual) or changed.
pub fn diff(arena: std.mem.Allocator, expected: Files, actual: Files) ![]Difference {
    var out: std.ArrayList(Difference) = .empty;
    for (expected.keys(), expected.values()) |name, bytes| {
        const other = actual.get(name) orelse {
            try out.append(arena, .{ .name = name, .kind = .missing });
            continue;
        };
        if (!std.mem.eql(u8, bytes, other)) try out.append(arena, .{ .name = name, .kind = .changed });
    }
    for (actual.keys()) |name| {
        if (!expected.contains(name)) try out.append(arena, .{ .name = name, .kind = .extra });
    }
    std.mem.sort(Difference, out.items, {}, struct {
        fn lt(_: void, a: Difference, b: Difference) bool {
            return std.mem.lessThan(u8, a.name, b.name);
        }
    }.lt);
    return out.items;
}
