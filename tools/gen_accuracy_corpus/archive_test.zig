const std = @import("std");
const archive = @import("archive.zig");

const gpa = std.testing.allocator;

/// `tar --format=ustar` of a/x.bin ("hello") and b.txt ("world\n"), then
/// `zstd -19`: made by the GNU tools, so the reader is checked against an
/// archive it did not write.
const gnu_fixture = "\x28\xb5\x2f\xfd\x04\x68\xdd\x02\x00\xe2\x83\x0d\x12\x90\xcf\x01\xe0\xc2\xa1\x04\x45\xff\x5f\x36\xd8\x22\x94\xfe\xa9\x02\x29\xa0\x45\x3a\xb1\x29\x2a\xa5\xdf\x66\x2b\xd8\x67\x8c\xee\xbd\xfb\x74\xd9\x7a\xff\x0e\x27\x85\xa8\xee\xf7\x51\xff\x9c\xd4\x97\x90\x89\x3c\x56\x0e\x20\xd0\xd7\x37\xfd\xdf\x83\x7b\xb5\x8c\xa9\x14\xdd\xe5\x03\xa4\xe6\xbe\x5a\xe6\xd4\xf9\x99\xf6\xc4\x00\x1e\x30\x28\xc0\x72\x62\x71\x40\xe6\xcb\xff";

test "unpack reads a GNU tar.zst into memory" {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const files = try archive.unpack(arena.allocator(), gnu_fixture);
    try std.testing.expectEqual(@as(usize, 2), files.count());
    try std.testing.expectEqualStrings("hello", files.get("a/x.bin").?);
    try std.testing.expectEqualStrings("world\n", files.get("b.txt").?);
}

test "unpack rejects input that is not zstd" {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    try std.testing.expectError(error.BadArchive, archive.unpack(arena.allocator(), "not an archive"));
    try std.testing.expectError(error.BadArchive, archive.unpack(arena.allocator(), gnu_fixture[0 .. gnu_fixture.len - 8]));
}

test "pack then parse round-trips names, bytes and order, including empty and long-named files" {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const long_name = "d/" ++ "n" ** 150 ++ ".bin";
    var files: archive.Files = .empty;
    try files.put(a, "z/first.bin", "\x00\xff\x00");
    try files.put(a, "empty.txt", "");
    try files.put(a, long_name, "x" ** 513);
    const tar = try archive.pack(a, files);
    try std.testing.expectEqual(@as(usize, 0), tar.len % 512);
    const back = try archive.parseTar(a, tar);
    try std.testing.expectEqual(files.count(), back.count());
    for (files.keys(), back.keys()) |want, got| try std.testing.expectEqualStrings(want, got);
    for (files.keys(), files.values()) |k, v| try std.testing.expectEqualStrings(v, back.get(k).?);
}

test "pack is deterministic" {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var files: archive.Files = .empty;
    try files.put(a, "k", "v");
    try std.testing.expectEqualSlices(u8, try archive.pack(a, files), try archive.pack(a, files));
}

test "diff classifies every name as missing, extra, changed or equal" {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var expected: archive.Files = .empty;
    var actual: archive.Files = .empty;
    try expected.put(a, "same", "1");
    try actual.put(a, "same", "1");
    try expected.put(a, "changed", "1");
    try actual.put(a, "changed", "2");
    try expected.put(a, "missing", "1");
    try actual.put(a, "extra", "1");
    try expected.put(a, "emptied", "1");
    try actual.put(a, "emptied", "");

    const d = try archive.diff(a, expected, actual);
    try std.testing.expectEqual(@as(usize, 4), d.len);
    const want = [_]archive.Difference{
        .{ .name = "changed", .kind = .changed },
        .{ .name = "emptied", .kind = .changed },
        .{ .name = "extra", .kind = .extra },
        .{ .name = "missing", .kind = .missing },
    };
    for (want, d) |w, got| {
        try std.testing.expectEqualStrings(w.name, got.name);
        try std.testing.expectEqual(w.kind, got.kind);
    }
    try std.testing.expectEqual(@as(usize, 0), (try archive.diff(a, expected, expected)).len);
}
