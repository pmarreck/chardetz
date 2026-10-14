//! chardetz public Zig API: a pure in-memory character-encoding detector
//! translated from uchardet. No I/O happens in this module tree.
const std = @import("std");

pub const tables = @import("tables/all.zig");

/// Detects the encoding of a complete buffer, returning uchardet's charset
/// name. Returns null while the probers are still being ported, which the
/// differential gate counts as pending rather than as agreement.
pub fn detectCharset(bytes: []const u8) ?[]const u8 {
    _ = bytes;
    return null;
}
