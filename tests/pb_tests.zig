//! PRINTABLE-BINARY extension tests (chardetz-only; uchardet has no such
//! charset, so these are authored and metamorphic tests, not oracle checks).
//! Rooted here so the fixtures in tests/fixtures/pb are inside the package.
test {
    _ = @import("unit/printable_binary_prober_test.zig");
    _ = @import("unit/printable_binary_table_test.zig");
    _ = @import("unit/pb_metamorphic_test.zig");
}
