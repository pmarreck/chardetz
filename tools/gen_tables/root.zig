//! gen_tables module root — re-exports parser/emit pieces for unit tests.
pub const emit = @import("emit.zig");
pub const manifest = @import("manifest.zig");
pub const parse_sbcs = @import("parse_sbcs.zig");
