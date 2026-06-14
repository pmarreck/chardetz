//! Phase 8 — in-harness differential oracle link.
//!
//! Links the uchardet C++ library (Peter's `uchardetz` fork, pinned in
//! build.zig.zon) into a Zig test and drives it through its 6-function C ABI.
//! This is the trickiest integration in the project: it proves (a) we can link
//! & call the C ABI from Zig inside the hermetic nix sandbox, (b) the corpus
//! filename labels are right, and (c) the harness loop works end-to-end.
//!
//! In M1 there is NO chardetz detection yet, so this validates the ORACLE
//! itself: feed each corpus file to uchardet and assert it returns the charset
//! named in the corpus filename label. The M2 hook (chardetz-vs-oracle
//! comparison) is marked below.
//!
//! Runs via the separate `test-oracle` build step (it needs the C++ link); it
//! is intentionally NOT added to tests/all.zig (the default hermetic `test`).

const std = @import("std");
// `c` is the translate-c module created in build.zig from c_imports.h, which
// #includes uchardet.h. (Zig 0.16 deprecates source-level @cImport.)
const c = @import("c");

/// Drive uchardet's C API over a byte buffer and return its charset verdict.
/// Mirrors the canonical uchardet usage: new → handle_data → data_end →
/// get_charset → delete. The returned slice borrows uchardet-owned memory that
/// is valid until `uchardet_delete`; callers must copy if they outlive `ud`.
fn detect(alloc: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const ud = c.uchardet_new();
    defer c.uchardet_delete(ud);
    // uchardet_handle_data wants a non-null pointer even for empty input.
    const ptr: [*c]const u8 = if (bytes.len == 0) "" else bytes.ptr;
    _ = c.uchardet_handle_data(ud, ptr, bytes.len);
    c.uchardet_data_end(ud);
    const charset = std.mem.span(c.uchardet_get_charset(ud));
    // Copy out before uchardet_delete frees the detector's internal buffer.
    return alloc.dupe(u8, charset);
}

const Entry = struct {
    path: []const u8,
    label: []const u8,
};

test "uchardetz oracle agrees with corpus filename labels" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const cwd = std.Io.Dir.cwd();

    // Read the manifest at runtime from the source tree. (@embedFile can't reach
    // ../corpus/ — Zig forbids embedding outside this module's package path —
    // and the corpus files are read at runtime anyway, so stay consistent.)
    const manifest_json = try cwd.readFileAlloc(io, "tests/corpus/manifest.json", alloc, .unlimited);
    defer alloc.free(manifest_json);
    const parsed = try std.json.parseFromSlice([]Entry, alloc, manifest_json, .{});
    defer parsed.deinit();

    var mismatches: usize = 0;

    for (parsed.value) |e| {
        const path = try std.fmt.allocPrint(alloc, "tests/corpus/{s}", .{e.path});
        defer alloc.free(path);

        const data = cwd.readFileAlloc(io, path, alloc, .unlimited) catch |err| {
            std.debug.print("READ FAIL  {s}: {}\n", .{ e.path, err });
            mismatches += 1;
            continue;
        };
        defer alloc.free(data);

        const got = try detect(alloc, data);
        defer alloc.free(got);

        // M2 HOOK: once chardetz has a detector, add a parallel
        // `chardetz.detect(data)` here and assert it equals `got` (the oracle),
        // gated by tests/expected_divergences.json. For M1 we validate the
        // oracle against the corpus labels only.
        if (!std.ascii.eqlIgnoreCase(got, e.label)) {
            std.debug.print("ORACLE MISMATCH  {s}\tlabel={s}\tgot={s}\n", .{ e.path, e.label, got });
            mismatches += 1;
        }
    }

    if (mismatches != 0) {
        std.debug.print("TOTAL MISMATCHES: {d}/{d}\n", .{ mismatches, parsed.value.len });
    }
    try std.testing.expectEqual(@as(usize, 0), mismatches);
}
