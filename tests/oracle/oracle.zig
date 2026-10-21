//! Test-only adapter over the original C++ uchardet, linked from the pinned
//! uchardetz source. This is the differential oracle; it never ships.
const std = @import("std");

const Handle = *opaque {};
extern fn uchardet_new() ?Handle;
extern fn uchardet_delete(ud: Handle) void;
extern fn uchardet_handle_data(ud: Handle, data: [*]const u8, len: usize) c_int;
extern fn uchardet_data_end(ud: Handle) void;
extern fn uchardet_get_charset(ud: Handle) [*:0]const u8;

/// Detects `bytes` with the C++ detector, feeding it in `chunk_len` pieces
/// (chunking matters: probers carry state across calls). Caller owns result.
pub fn detect(gpa: std.mem.Allocator, bytes: []const u8, chunk_len: usize) ![]u8 {
    const ud = uchardet_new() orelse return error.OutOfMemory;
    defer uchardet_delete(ud);
    var rest = bytes;
    while (rest.len > 0) {
        const n = @min(rest.len, chunk_len);
        if (uchardet_handle_data(ud, rest.ptr, n) != 0) return error.OracleHandleData;
        rest = rest[n..];
    }
    uchardet_data_end(ud);
    return gpa.dupe(u8, std.mem.span(uchardet_get_charset(ud)));
}
