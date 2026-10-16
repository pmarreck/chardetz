//! chardetz public Zig API: a pure in-memory character-encoding detector
//! translated from uchardet. No I/O happens in this module tree.
const std = @import("std");

pub const tables = @import("tables/all.zig");

/// Record types used by the generated tables (exported for tests).
pub const table_types = @import("tables/types.zig");

/// Streaming detector with uchardet's semantics: `handleData` per chunk,
/// `dataEnd`, then `charset` ("" when nothing was detected).
pub const Detector = @import("detector.zig").Detector;

/// Detects the encoding of a complete buffer in one chunk.
pub fn detect(gpa: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}![:0]const u8 {
    var d: Detector = .init(gpa);
    defer d.deinit();
    try d.handleData(bytes);
    d.dataEnd();
    return d.charset();
}

test {
    _ = @import("prober.zig");
    _ = @import("filter.zig");
    _ = @import("detector.zig");
}
