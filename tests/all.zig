//! Test aggregator. `zig build test` runs every `test {}` block reachable from
//! here. As test modules are added (struct defs, the table generator, the
//! differential harness), append a `_ = @import("...");` line below.

comptime {
    _ = @import("../src/chardetz.zig");
}

test "test harness wired" {
    try @import("std").testing.expect(true);
}
