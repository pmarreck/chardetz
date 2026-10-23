//! `core.Transcoder` adapter over the C library's iconv(3). Strict: invalid or
//! unrepresentable input is an error, never transliterated or skipped.
const std = @import("std");
const core = @import("core.zig");

const Descriptor = *anyopaque;
extern "c" fn iconv_open(tocode: [*:0]const u8, fromcode: [*:0]const u8) Descriptor;
extern "c" fn iconv(cd: Descriptor, inbuf: *?[*]u8, inleft: *usize, outbuf: *?[*]u8, outleft: *usize) usize;
extern "c" fn iconv_close(cd: Descriptor) c_int;

const failed_open: usize = std.math.maxInt(usize);
const failed_convert: usize = std.math.maxInt(usize);

pub fn transcoder() core.Transcoder {
    return .{ .ctx = undefined, .convertFn = convert };
}

fn convert(_: *anyopaque, gpa: std.mem.Allocator, from: []const u8, to: []const u8, bytes: []const u8) core.ConvertError![]u8 {
    const from_z = try gpa.dupeZ(u8, from);
    defer gpa.free(from_z);
    const to_z = try gpa.dupeZ(u8, to);
    defer gpa.free(to_z);
    const cd = iconv_open(to_z, from_z);
    if (@intFromPtr(cd) == failed_open) return error.Unsupported;
    defer _ = iconv_close(cd);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.ensureTotalCapacity(gpa, bytes.len * 4 + 16);
    var in_ptr: ?[*]u8 = @constCast(bytes.ptr);
    var in_left: usize = bytes.len;
    // A final call with no input flushes shift state (ISO-2022 escapes back to ASCII).
    var flushing = false;
    while (true) {
        const spare = out.allocatedSlice()[out.items.len..];
        var out_ptr: ?[*]u8 = spare.ptr;
        var out_left: usize = spare.len;
        const rc = if (flushing)
            iconv(cd, @ptrCast(@constCast(&@as(?[*]u8, null))), &in_left, &out_ptr, &out_left)
        else
            iconv(cd, &in_ptr, &in_left, &out_ptr, &out_left);
        out.items.len += spare.len - out_left;
        if (rc == failed_convert) switch (std.c.errno(@as(c_int, -1))) {
            .@"2BIG" => {
                try out.ensureTotalCapacity(gpa, out.capacity * 2);
                continue;
            },
            else => return error.Invalid,
        };
        if (flushing) break;
        flushing = true;
    }
    return out.toOwnedSlice(gpa);
}

test "round-trips Cyrillic through KOI8-R" {
    const gpa = std.testing.allocator;
    const t = transcoder();
    const bytes = try t.convert(gpa, "UTF-8", "KOI8-R", "\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82"); // Привет
    defer gpa.free(bytes);
    try std.testing.expectEqualSlices(u8, "\xF0\xD2\xC9\xD7\xC5\xD4", bytes);
    const back = try t.convert(gpa, "KOI8-R", "UTF-8", bytes);
    defer gpa.free(back);
    try std.testing.expectEqualStrings("\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82", back);
}

test "ISO-2022-JP output returns to ASCII at the end" {
    const gpa = std.testing.allocator;
    const bytes = try transcoder().convert(gpa, "UTF-8", "ISO-2022-JP", "\xE6\x97\xA5"); // 日
    defer gpa.free(bytes);
    try std.testing.expectEqualSlices(u8, "\x1B$BF|\x1B(B", bytes);
}

test "unknown charsets and unrepresentable text are errors" {
    const gpa = std.testing.allocator;
    const t = transcoder();
    try std.testing.expectError(error.Unsupported, t.convert(gpa, "UTF-8", "NO-SUCH-CHARSET", "a"));
    try std.testing.expectError(error.Invalid, t.convert(gpa, "UTF-8", "ISO-8859-1", "\xE2\x82\xAC")); // €
    try std.testing.expectError(error.Invalid, t.convert(gpa, "UTF-8", "ASCII", "\xFF"));
}

test "output larger than the first buffer guess grows" {
    const gpa = std.testing.allocator;
    const input = "\xE6\x97\xA5a" ** 2000;
    const bytes = try transcoder().convert(gpa, "UTF-8", "UTF-32", input);
    defer gpa.free(bytes);
    try std.testing.expectEqual(@as(usize, 4 + 4 * 4000), bytes.len);
}
