//! corpus-compare: the freshness check for the committed accuracy corpus.
//! Usage: corpus-compare GENERATED_TAR COMMITTED_TAR_ZST
//! Exits 0 when the committed archive holds exactly the files the generator
//! just produced, and 1 with the differing names otherwise. Contents are
//! compared after decompression, so the zstd version that wrote the archive
//! does not matter.
const std = @import("std");
const archive = @import("archive.zig");

const max_archive_bytes = 256 << 20;
const max_listed = 20;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var err_buf: [4096]u8 = undefined;
    var err_w = std.Io.File.stderr().writer(io, &err_buf);
    const stderr = &err_w.interface;
    defer stderr.flush() catch {};
    if (args.len != 3) {
        try stderr.writeAll("usage: corpus-compare GENERATED_TAR COMMITTED_TAR_ZST\n");
        return 2;
    }
    const cwd = std.Io.Dir.cwd();
    const generated = try archive.parseTar(arena, try cwd.readFileAlloc(io, args[1], arena, .limited(max_archive_bytes)));
    const committed = try archive.unpack(arena, try cwd.readFileAlloc(io, args[2], arena, .limited(max_archive_bytes)));
    const d = try archive.diff(arena, generated, committed);
    if (d.len == 0) return 0;
    for (d[0..@min(d.len, max_listed)]) |x| try stderr.print("{s} {s}\n", .{ @tagName(x.kind), x.name });
    try stderr.print("corpus-compare: {s} differs from the generator output in {d} file(s); run `zig build accuracy-corpus-update`, then `zig build accuracy-report`\n", .{ args[2], d.len });
    return 1;
}
