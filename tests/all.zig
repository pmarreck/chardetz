//! Test aggregator. `zig build test` runs every `test {}` block reachable from
//! here. As test modules are added, append a `_ = @import("...");` line below.
//!
//! Import conventions (Zig 0.16 forbids importing across module roots via
//! relative `../` paths):
//!   - Production code: via the named module — `@import("chardetz")` (and, once
//!     the generator exists, `@import("gen_tables")`). NEVER `../src/...`.
//!   - Sibling test files under tests/: relative is fine — `@import("unit/foo_test.zig")`.

comptime {
	_ = @import("chardetz");
	_ = @import("unit/sbcs_model_test.zig");
	_ = @import("unit/state_machine_test.zig");
	_ = @import("unit/dist_jp_test.zig");
	// Phase 3: generator tests
	_ = @import("gen_tables/parse_sbcs_test.zig");
	_ = @import("gen_tables/emit_test.zig");
}

test "test harness wired" {
	try @import("std").testing.expect(true);
}
