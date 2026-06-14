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
// The chardetz core under test (the named module wired in build.zig). This is
// the M2 flip: the gate now compares chardetz.detect against the uchardet C ABI.
const cz = @import("chardetz");

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

/// Case-insensitive set membership over the charsets chardetz implements THIS
/// chunk. A transient build tracker: it grows toward 100% as later chunks add
/// probers. A charset NOT in this set is "pending" — its prober lands later, so
/// a chardetz≠oracle there is expected and tallied, NOT a divergence, NOT fenced.
const IMPLEMENTED = [_][]const u8{
    // BOM / UTF / Unicode (detector + UTF8 prober)
    "ASCII",        "UTF-8",        "UTF-16",     "UTF-16BE", "UTF-16LE", "UTF-32",
    // Single-byte: Latin1 prober + SBCS group (Cyrillic, Greek, Hebrew, Thai,
    // Latin-1/15, Arabic, Vietnamese, Turkish, etc.) — every charset name these
    // 35 sub-probers + the Latin1 prober report. The CJK (MBCS) group and the
    // escape prober land in later chunks, so their charsets stay pending.
    "WINDOWS-1250", "WINDOWS-1251", "WINDOWS-1252", "WINDOWS-1253", "WINDOWS-1255", "WINDOWS-1256", "WINDOWS-1258",
    "ISO-8859-1",   "ISO-8859-2",   "ISO-8859-3",   "ISO-8859-5",   "ISO-8859-6",   "ISO-8859-7",
    "ISO-8859-8",   "ISO-8859-9",   "ISO-8859-11",  "ISO-8859-15",
    "KOI8-R",       "IBM855",       "IBM866",       "MAC-CYRILLIC", "TIS-620",      "VISCII",
};

fn isImplemented(charset: []const u8) bool {
    for (IMPLEMENTED) |c_set| {
        if (std.ascii.eqlIgnoreCase(charset, c_set)) return true;
    }
    return false;
}

test "chardetz.detect matches the uchardet oracle on every IMPLEMENTED-charset corpus file" {
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

    var mismatches: usize = 0; // chardetz≠oracle on an IMPLEMENTED charset → FAIL
    var read_failures: usize = 0;
    var checked: usize = 0; // IMPLEMENTED-charset files asserted strictly
    var pending: usize = 0; // files whose oracle charset's prober lands later

    // Track distinct pending charsets for the end-of-run report.
    var pending_set = std.StringHashMap(void).init(alloc);
    defer {
        var it = pending_set.keyIterator();
        while (it.next()) |k| alloc.free(k.*);
        pending_set.deinit();
    }

    for (parsed.value) |e| {
        const path = try std.fmt.allocPrint(alloc, "tests/corpus/{s}", .{e.path});
        defer alloc.free(path);

        const data = cwd.readFileAlloc(io, path, alloc, .unlimited) catch |err| {
            std.debug.print("READ FAIL  {s}: {}\n", .{ e.path, err });
            read_failures += 1;
            continue;
        };
        defer alloc.free(data);

        // The oracle (uchardet C ABI) is the spec.
        const oracle = try detect(alloc, data);
        defer alloc.free(oracle);

        // chardetz under test (pure Zig, no alloc — but pass the allocator for
        // API symmetry with the eventual allocating probers).
        const got = cz.detect(alloc, data);

        if (isImplemented(oracle)) {
            checked += 1;
            // STRICT, case-insensitive equality against the oracle.
            if (!std.ascii.eqlIgnoreCase(got, oracle)) {
                std.debug.print(
                    "DIVERGENCE  {s}\toracle={s}\tchardetz={s}\n",
                    .{ e.path, oracle, got },
                );
                mismatches += 1;
            }
        } else {
            // Pending: a charset whose prober is not in this chunk. Not a
            // divergence, not fenced — just tallied so coverage growth is visible.
            pending += 1;
            if (!pending_set.contains(oracle)) {
                try pending_set.put(try alloc.dupe(u8, oracle), {});
            }
        }
    }

    // ── End-of-run report ──
    std.debug.print(
        "\n[differential] checked(IMPLEMENTED)={d}  pending={d}  read_failures={d}  divergences={d}\n",
        .{ checked, pending, read_failures, mismatches },
    );
    std.debug.print("[differential] distinct pending charsets ({d}):\n", .{pending_set.count()});
    {
        var it = pending_set.keyIterator();
        while (it.next()) |k| std.debug.print("  - {s}\n", .{k.*});
    }

    // The gate passes iff every IMPLEMENTED-charset file matched the oracle and
    // no corpus file failed to read.
    try std.testing.expectEqual(@as(usize, 0), read_failures);
    try std.testing.expectEqual(@as(usize, 0), mismatches);
    // Vacuity guard: the gate must actually have ASSERTED something. If the
    // corpus ever stops covering any IMPLEMENTED charset, fail loudly rather
    // than pass green on zero assertions.
    try std.testing.expect(checked > 0);
}
