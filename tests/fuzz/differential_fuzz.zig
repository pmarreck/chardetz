//! Differential FUZZ harness — chardetz core vs the uchardet C ABI oracle.
//!
//! The 59-file labelled corpus proves parity on *real* text; this harness
//! attacks the gaps the corpus cannot reach — partial multibyte sequences,
//! adversarial byte soup, lone BOMs, truncations, near-UTF-8 runs — by feeding
//! MANY (default 5000+) generated/mutated buffers to BOTH detectors and
//! asserting they agree on the detected charset. This is the strongest member
//! of chardetz's MFIC battery: an oracle-free* metamorphic comparison against a
//! causally-independent reference (uchardetz's own C++ build), so any green is
//! a biting refutation rather than a self-check. (*free of an authored oracle —
//! the "expected" answer is whatever uchardet says, never anything chardetz
//! produced.)
//!
//! DETERMINISM (house rule): the PRNG is seeded from a FIXED constant (overridable
//! via the CHARDETZ_FUZZ_SEED env var) and the iteration count from
//! CHARDETZ_FUZZ_ITERS — NO time-based seeds, NO sleeps. Same seed ⇒ same run,
//! so any disagreement is exactly reproducible.
//!
//! On ANY disagreement we print the offending input as hex + both verdicts and
//! FAIL. Per the brief, a disagreement is a PORTING BUG to investigate — it is
//! NOT to be fenced/suppressed. (`expected_divergences.json` is the one place a
//! *documented, accepted* divergence could be recorded, but the default
//! expectation is full agreement; flag any to Peter rather than silently
//! fencing.)
//!
//! Runs via the dedicated `test-fuzz` build step (it links uchardetz's C++,
//! exactly like the Phase-8 oracle test) — intentionally NOT in tests/all.zig /
//! the default hermetic `test` (fuzz is a separate suite per house convention).
//! Invoked through `./fuzz`.

const std = @import("std");
// `c` is the translate-c module created in build.zig from c_imports.h, which
// #includes uchardet.h. (Zig 0.16 deprecates source-level @cImport.)
const c = @import("c");
// The chardetz core under test (the named module wired in build.zig).
const cz = @import("chardetz");

/// Default fixed seed (deterministic). Override with CHARDETZ_FUZZ_SEED.
const DEFAULT_SEED: u64 = 0xC0FFEE_F00D_1972;
/// Default iteration budget. Override with CHARDETZ_FUZZ_ITERS. The brief asks
/// for 5000+; we split it across the three generators below.
const DEFAULT_ITERS: usize = 6000;

/// Drive uchardet's C API over a byte buffer and return its charset verdict
/// (copied out before uchardet_delete frees the detector's internal buffer).
/// Mirrors the canonical new → handle_data → data_end → get_charset → delete.
fn oracleDetect(alloc: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const ud = c.uchardet_new();
    defer c.uchardet_delete(ud);
    const ptr: [*c]const u8 = if (bytes.len == 0) "" else bytes.ptr;
    _ = c.uchardet_handle_data(ud, ptr, bytes.len);
    c.uchardet_data_end(ud);
    const charset = std.mem.span(c.uchardet_get_charset(ud));
    return alloc.dupe(u8, charset);
}

/// A single differential check: feed `input` to both detectors and assert they
/// agree (exact, case-insensitive). Returns true on agreement; on disagreement
/// prints a reproduction (label, hex dump, both verdicts) and returns false.
/// The caller tallies and ultimately FAILS the test — we do NOT fence here.
fn checkAgreement(
    alloc: std.mem.Allocator,
    label: []const u8,
    input: []const u8,
) !bool {
    const oracle = try oracleDetect(alloc, input);
    defer alloc.free(oracle);
    const got = cz.detect(alloc, input);

    if (std.ascii.eqlIgnoreCase(oracle, got)) return true;

    // DISAGREEMENT — print a fully reproducible report (do NOT suppress).
    std.debug.print(
        "\n!! FUZZ DISAGREEMENT [{s}]  oracle=\"{s}\"  chardetz=\"{s}\"  len={d}\n",
        .{ label, oracle, got, input.len },
    );
    std.debug.print("   input (hex): ", .{});
    const max_dump = 256; // cap the dump so a huge buffer doesn't flood the log
    const dump_len = @min(input.len, max_dump);
    for (input[0..dump_len]) |b| std.debug.print("{x:0>2}", .{b});
    if (input.len > max_dump) std.debug.print("…(+{d} more bytes)", .{input.len - max_dump});
    std.debug.print("\n", .{});
    return false;
}

// ── Corpus loading (for the mutation generator) ──────────────────────────────

const Entry = struct {
    path: []const u8,
    label: []const u8,
};

const CorpusFile = struct {
    path: []const u8,
    bytes: []const u8,
};

/// Load every corpus file's raw bytes into memory so the mutation generator can
/// derive adversarial neighbours of real text. Caller owns the returned slice
/// and each file's bytes/path (freed via freeCorpus).
fn loadCorpus(alloc: std.mem.Allocator, io: std.Io) ![]CorpusFile {
    const cwd = std.Io.Dir.cwd();
    const manifest_json = try cwd.readFileAlloc(io, "tests/corpus/manifest.json", alloc, .unlimited);
    defer alloc.free(manifest_json);
    const parsed = try std.json.parseFromSlice([]Entry, alloc, manifest_json, .{});
    defer parsed.deinit();

    var list: std.ArrayList(CorpusFile) = .empty;
    errdefer list.deinit(alloc);

    for (parsed.value) |e| {
        const path = try std.fmt.allocPrint(alloc, "tests/corpus/{s}", .{e.path});
        const data = try cwd.readFileAlloc(io, path, alloc, .unlimited);
        try list.append(alloc, .{ .path = path, .bytes = data });
    }
    return list.toOwnedSlice(alloc);
}

fn freeCorpus(alloc: std.mem.Allocator, corpus: []CorpusFile) void {
    for (corpus) |f| {
        alloc.free(f.path);
        alloc.free(f.bytes);
    }
    alloc.free(corpus);
}

// ── Input generators ─────────────────────────────────────────────────────────

/// (a) Uniform-random buffer of a random length (0..max_len). Catches the
/// "adversarial byte soup" case the corpus never exercises.
fn genUniformRandom(rng: std.Random, alloc: std.mem.Allocator) ![]u8 {
    const len = rng.intRangeAtMost(usize, 0, 512);
    const buf = try alloc.alloc(u8, len);
    rng.bytes(buf);
    return buf;
}

/// (b) Mutation of a random corpus file: a copy with one of {bit flips, a
/// truncation, byte injections} applied. Probes the neighbourhood of real text
/// where boundary/partial-sequence divergences hide.
fn genMutation(rng: std.Random, alloc: std.mem.Allocator, corpus: []CorpusFile) ![]u8 {
    const src = corpus[rng.intRangeLessThan(usize, 0, corpus.len)].bytes;

    // Decide a mutation kind. Truncation shrinks; the others keep length and may
    // append a few injected bytes.
    const kind = rng.intRangeLessThan(u8, 0, 3);
    switch (kind) {
        0 => { // truncation: keep a random prefix (partial multibyte sequences!)
            const keep = if (src.len == 0) 0 else rng.intRangeAtMost(usize, 0, src.len);
            const buf = try alloc.alloc(u8, keep);
            @memcpy(buf, src[0..keep]);
            return buf;
        },
        1 => { // bit flips: copy, then flip 1..8 random bits
            const buf = try alloc.alloc(u8, src.len);
            @memcpy(buf, src);
            if (buf.len > 0) {
                const flips = rng.intRangeAtMost(usize, 1, 8);
                var i: usize = 0;
                while (i < flips) : (i += 1) {
                    const pos = rng.intRangeLessThan(usize, 0, buf.len);
                    const bit: u3 = @intCast(rng.intRangeLessThan(u8, 0, 8));
                    buf[pos] ^= (@as(u8, 1) << bit);
                }
            }
            return buf;
        },
        else => { // byte injection: copy, then overwrite 1..8 random positions
            const buf = try alloc.alloc(u8, src.len);
            @memcpy(buf, src);
            if (buf.len > 0) {
                const injections = rng.intRangeAtMost(usize, 1, 8);
                var i: usize = 0;
                while (i < injections) : (i += 1) {
                    const pos = rng.intRangeLessThan(usize, 0, buf.len);
                    buf[pos] = rng.int(u8);
                }
            }
            return buf;
        },
    }
}

/// Structured edge-case fragments: lone/partial BOM bytes and near-UTF-8
/// sequences. These are the classic boundary cases where a streaming detector's
/// state machine can diverge. We assemble a small buffer from a random pick of
/// these fragments, sometimes followed by a short random tail.
const EDGE_FRAGMENTS = [_][]const u8{
    // Lone / partial BOMs
    "\xEF", "\xEF\xBB", "\xEF\xBB\xBF", // UTF-8 BOM (partial → full)
    "\xFE", "\xFE\xFF", // UTF-16 BE BOM (partial → full)
    "\xFF", "\xFF\xFE", // UTF-16 LE BOM (partial → full)
    "\x00\x00\xFE\xFF", // UTF-32 BE BOM
    "\xFF\xFE\x00\x00", // UTF-32 LE BOM
    // Near-UTF-8: lead bytes missing continuation, overlong, stray continuations
    "\xC3", "\xC3\x28", "\xE2\x82", "\xE2\x82\xAC", "\xF0\x9F", "\xF0\x9F\x98\x81",
    "\x80\x80", "\xFF\xFF\xFF\xFF", "\xC0\x80", "\xED\xA0\x80",
    // Escape-sequence introducers (ISO-2022 / HZ) — partial
    "\x1B$B", "\x1B$)C", "\x1B$(D", "~{", "\x1B(B",
    // Plain ASCII anchors to mix with the above
    "hello", "A", "café", " ", "\n",
};

fn genEdgeCase(rng: std.Random, alloc: std.mem.Allocator) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(alloc);
    const pieces = rng.intRangeAtMost(usize, 1, 5);
    var i: usize = 0;
    while (i < pieces) : (i += 1) {
        const frag = EDGE_FRAGMENTS[rng.intRangeLessThan(usize, 0, EDGE_FRAGMENTS.len)];
        try buf.appendSlice(alloc, frag);
    }
    // Sometimes append a short random tail to perturb the state machine further.
    if (rng.boolean()) {
        const tail_len = rng.intRangeAtMost(usize, 0, 16);
        const start = buf.items.len;
        try buf.resize(alloc, start + tail_len);
        rng.bytes(buf.items[start..]);
    }
    return buf.toOwnedSlice(alloc);
}

// ── The fuzz test ─────────────────────────────────────────────────────────────

/// Read a numeric env var. Zig 0.16 removed std.posix.getenv; we use std.c.getenv
/// (the fuzz binary links libc) + std.mem.span. Returns `default` if unset or
/// unparseable. `name` must be a NUL-terminated C string literal (it is at the
/// two call sites).
fn envInt(comptime T: type, name: [*:0]const u8, default: T) T {
    const raw = std.c.getenv(name) orelse return default;
    const v = std.mem.span(raw);
    return std.fmt.parseInt(T, v, 10) catch default;
}

test "differential fuzz: chardetz core agrees with the uchardet oracle on generated/mutated inputs" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const seed = envInt(u64, "CHARDETZ_FUZZ_SEED", DEFAULT_SEED);
    const iters = envInt(usize, "CHARDETZ_FUZZ_ITERS", DEFAULT_ITERS);

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    const corpus = try loadCorpus(alloc, io);
    defer freeCorpus(alloc, corpus);
    try std.testing.expect(corpus.len > 0); // vacuity guard: must have inputs to mutate

    std.debug.print(
        "\n[fuzz] seed=0x{x}  iters={d}  corpus_files={d}\n",
        .{ seed, iters, corpus.len },
    );

    var disagreements: usize = 0;
    var checked: usize = 0;

    var i: usize = 0;
    while (i < iters) : (i += 1) {
        // Round-robin the three generators so each gets ~1/3 of the budget.
        const which = i % 3;
        const input: []u8 = switch (which) {
            0 => try genUniformRandom(rng, alloc),
            1 => try genMutation(rng, alloc, corpus),
            else => try genEdgeCase(rng, alloc),
        };
        defer alloc.free(input);

        const label = switch (which) {
            0 => "uniform-random",
            1 => "corpus-mutation",
            else => "edge-case",
        };

        const agreed = try checkAgreement(alloc, label, input);
        checked += 1;
        if (!agreed) {
            disagreements += 1;
            // Cap the noise: after the first handful, stop printing dumps but
            // keep counting so the final tally is honest.
            if (disagreements > 10) {
                std.debug.print("[fuzz] (suppressing further dumps; still counting)\n", .{});
            }
        }
    }

    std.debug.print(
        "[fuzz] checked={d}  disagreements={d}\n",
        .{ checked, disagreements },
    );

    // MFIC verdict: every generated input must agree. A disagreement is a real
    // finding (porting bug) to investigate — we FAIL loudly, never fence.
    try std.testing.expectEqual(@as(usize, 0), disagreements);
    // Vacuity guard: the harness must actually have run its budget.
    try std.testing.expectEqual(iters, checked);
}
