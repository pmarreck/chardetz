// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
//! chardetz benchmark harness — measures detection throughput and gates against
//! algorithmic-complexity regressions.
//!
//! Two MFIC controls live here:
//!   1. SCALING-RATIO GATE (primary, hard, machine-INDEPENDENT). A metamorphic
//!      test: run a hot kernel at N/2N/4N/8N and assert the per-doubling growth
//!      ratio matches the declared O(n) complexity. The *ratio* needs no
//!      per-machine baseline, so this is a build-breaking gate (exit nonzero).
//!   2. CONSTANT-FACTOR THROUGHPUT (secondary, statistical). Emits an ndjson
//!      line the `./bm` driver appends to bench/<machine-id>.ndjson and compares
//!      two-sided against the previous run for THIS machine. Also reports the
//!      headline number: chardetz vs the C++ uchardet oracle (same C ABI the
//!      differential suites link).
//!
//! Inputs are synthetic, deterministic path-exercisers (no clock/RNG/I-O in
//! their construction) — one per major detection path (pure-ASCII classifier,
//! the SBCS group's 34-prober path, the CJK MBCS group, UTF-8 multibyte
//! validation). Correctness across the real corpus is the oracle's job
//! (./test); this harness is strictly about speed and growth shape.
//!
//! ReleaseFast only (house rule): refuses to run as a Debug build.

const std = @import("std");
const builtin = @import("builtin");
const cz = @import("chardetz");
// uchardet's 6-function C ABI via translate-c (wired in build.zig under -Dwith-bench).
const c = @import("c");

const SingleByteCharSetProber = cz.probers.sbcs.SingleByteCharSetProber;

/// O(n) growth claim: each input doubling should ~double the time (ratio ≈ 2).
/// Fail the build if any doubling exceeds this — that is the signature of an
/// accidental super-linear algorithm (the regression this gate exists to catch).
const SCALE_FAIL_RATIO: f64 = 2.5;

const WARMUP = 5;
const ITERS = 31; // odd; we take the MIN (least scheduler noise) of the timed runs

/// Defeats dead-code elimination: every measured call folds a result byte in
/// here, and we print it at the end so the optimizer cannot elide the work.
var sink: u64 = 0;

const alloc = std.heap.c_allocator; // matches the FFI's handle allocator

// ── timing ───────────────────────────────────────────────────────────────────
// Monotonic clock (.awake). For a single-threaded tight compute loop, wall ≈ CPU;
// taking the MIN over many runs rejects preemption noise, approximating CPU time
// (the house rule's preferred signal for compute kernels) without a CPU-clock dep.
fn nowNs(io: std.Io) u64 {
    return @intCast(std.Io.Timestamp.now(io, .awake).toNanoseconds());
}

fn mbps(bytes: usize, ns: u64) f64 {
    if (ns == 0) return 0;
    return @as(f64, @floatFromInt(bytes)) * 1000.0 / @as(f64, @floatFromInt(ns));
}

// ── deterministic synthetic inputs ─────────────────────────────────────────────
fn fillAscii(buf: []u8) void {
    const pat = "the quick brown fox jumps over the lazy dog. ";
    for (buf, 0..) |*b, i| b.* = pat[i % pat.len];
}

/// Lowercase Cyrillic (windows-1251 0xE0..0xFF) in space-delimited "words". All
/// bytes are valid word characters for the Russian models (never the ILL order),
/// so the SBCS prober scans the whole buffer — a clean O(n) inner kernel.
fn fillCyrillic(buf: []u8) void {
    for (buf, 0..) |*b, i| {
        if (i % 7 == 6) {
            b.* = ' ';
        } else {
            b.* = 0xE0 + @as(u8, @intCast((i * 7 + 3) % 0x20));
        }
    }
}

/// Valid GB-style 2-byte chars: lead 0xB0..0xF7, trail 0xA1..0xFE. Exercises the
/// MBCS group's high-byte slicing + the CJK char-distribution analyzers.
fn fillCjk(buf: []u8) void {
    var i: usize = 0;
    while (i + 1 < buf.len) : (i += 2) {
        const k = i / 2;
        buf[i] = 0xB0 + @as(u8, @intCast(k % 0x48)); // 0xB0..0xF7
        buf[i + 1] = 0xA1 + @as(u8, @intCast((k * 3) % 0x5E)); // 0xA1..0xFE
    }
    if (i < buf.len) buf[i] = ' ';
}

/// Repeated E4 B8 AD (中) — valid 3-byte UTF-8; exercises UTF-8 validation.
fn fillUtf8(buf: []u8) void {
    const pat = [_]u8{ 0xE4, 0xB8, 0xAD };
    for (buf, 0..) |*b, i| b.* = pat[i % 3];
}

const FillFn = *const fn ([]u8) void;

fn makeInput(n: usize, fill: FillFn) ![]u8 {
    const buf = try alloc.alloc(u8, n);
    fill(buf);
    return buf;
}

// ── measured kernels (min-of-ITERS, ns) ────────────────────────────────────────
fn timeChardetz(io: std.Io, buf: []const u8) u64 {
    var best: u64 = std.math.maxInt(u64);
    var i: usize = 0;
    while (i < WARMUP + ITERS) : (i += 1) {
        const t0 = nowNs(io);
        const cs = cz.detect(alloc, buf);
        const t1 = nowNs(io);
        sink +%= cs.len;
        if (i >= WARMUP and t1 - t0 < best) best = t1 - t0;
    }
    return best;
}

fn timeUchardet(io: std.Io, buf: []const u8) u64 {
    var best: u64 = std.math.maxInt(u64);
    var i: usize = 0;
    const ptr: [*c]const u8 = if (buf.len == 0) "" else buf.ptr;
    while (i < WARMUP + ITERS) : (i += 1) {
        const t0 = nowNs(io);
        const ud = c.uchardet_new();
        _ = c.uchardet_handle_data(ud, ptr, buf.len);
        c.uchardet_data_end(ud);
        const name = c.uchardet_get_charset(ud);
        c.uchardet_delete(ud);
        const t1 = nowNs(io);
        sink +%= std.mem.span(name).len;
        if (i >= WARMUP and t1 - t0 < best) best = t1 - t0;
    }
    return best;
}

/// Time a single SBCS-prober HandleData scan over `buf` (re-init each run so the
/// scan is independent). This is the heaviest single-byte inner kernel.
fn timeSbcsKernel(io: std.Io, buf: []const u8) u64 {
    var best: u64 = std.math.maxInt(u64);
    var i: usize = 0;
    while (i < WARMUP + ITERS) : (i += 1) {
        var p = SingleByteCharSetProber.init(&cz.tables.sbcs.russian.Win1251RussianModel);
        const t0 = nowNs(io);
        const st = p.handleData(buf);
        const t1 = nowNs(io);
        sink +%= @intFromEnum(st);
        sink +%= p.total_char;
        if (i >= WARMUP and t1 - t0 < best) best = t1 - t0;
    }
    return best;
}

// ── scaling-ratio gate ─────────────────────────────────────────────────────────
const SCALE_SIZES = [_]usize{ 64 * 1024, 128 * 1024, 256 * 1024, 512 * 1024 };

const ScaleResult = struct {
    label: []const u8,
    ns: [SCALE_SIZES.len]u64,
    worst_ratio: f64,
    passed: bool,
};

/// Run `kernel` over the N/2N/4N/8N buffers built by `fill`, print the per-size
/// timings and per-doubling ratios, and decide pass/fail against SCALE_FAIL_RATIO.
fn runScale(
    io: std.Io,
    label: []const u8,
    fill: FillFn,
    kernel: *const fn (std.Io, []const u8) u64,
) !ScaleResult {
    var r = ScaleResult{ .label = label, .ns = undefined, .worst_ratio = 0, .passed = true };
    for (SCALE_SIZES, 0..) |n, idx| {
        const buf = try makeInput(n, fill);
        defer alloc.free(buf);
        r.ns[idx] = kernel(io, buf);
    }
    std.debug.print("  scaling[{s}] (O(n), fail >= {d:.2}x per doubling):\n", .{ label, SCALE_FAIL_RATIO });
    for (SCALE_SIZES, 0..) |n, idx| {
        if (idx == 0) {
            std.debug.print("    {d:>7} KiB: {d:>10} ns\n", .{ n / 1024, r.ns[idx] });
        } else {
            const ratio = @as(f64, @floatFromInt(r.ns[idx])) /
                @as(f64, @floatFromInt(@max(r.ns[idx - 1], 1)));
            if (ratio > r.worst_ratio) r.worst_ratio = ratio;
            if (ratio >= SCALE_FAIL_RATIO) r.passed = false;
            std.debug.print("    {d:>7} KiB: {d:>10} ns   x{d:.2}{s}\n", .{
                n / 1024, r.ns[idx], ratio,
                if (ratio >= SCALE_FAIL_RATIO) "  <<< SUPER-LINEAR" else "",
            });
        }
    }
    return r;
}

// ── throughput comparison vs uchardet ───────────────────────────────────────────
const THROUGHPUT_SIZE = 256 * 1024;

const Cmp = struct {
    label: []const u8,
    cz_ns: u64,
    uc_ns: u64,
};

fn runCmp(io: std.Io, label: []const u8, fill: FillFn) !Cmp {
    const buf = try makeInput(THROUGHPUT_SIZE, fill);
    defer alloc.free(buf);
    return .{ .label = label, .cz_ns = timeChardetz(io, buf), .uc_ns = timeUchardet(io, buf) };
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    if (builtin.mode == .Debug) {
        std.debug.print("\x1b[31mREFUSING TO BENCHMARK A DEBUG BUILD\x1b[0m — build ReleaseFast (house rule).\n", .{});
        std.process.exit(2);
    }

    std.debug.print("== chardetz benchmark ({s}-{s}, {s}) ==\n", .{
        @tagName(builtin.target.cpu.arch), @tagName(builtin.target.os.tag), @tagName(builtin.mode),
    });

    // ── 1. Scaling-ratio gate (hard, machine-independent) ──
    std.debug.print("\n[1] Scaling-ratio gate\n", .{});
    var all_passed = true;
    var worst: f64 = 0;
    {
        // Pure-ASCII end-to-end detect(): the per-byte classification kernel.
        const r = try runScale(io, "ascii/detect", fillAscii, timeChardetz);
        all_passed = all_passed and r.passed;
        if (r.worst_ratio > worst) worst = r.worst_ratio;
    }
    {
        // The SBCS prober's HandleData scan: the heaviest single-byte inner loop.
        const r = try runScale(io, "sbcs/HandleData", fillCyrillic, timeSbcsKernel);
        all_passed = all_passed and r.passed;
        if (r.worst_ratio > worst) worst = r.worst_ratio;
    }

    // ── 2. Throughput vs uchardet (256 KiB per path) ──
    std.debug.print("\n[2] Throughput: chardetz vs uchardet (C++ oracle), {d} KiB inputs\n", .{THROUGHPUT_SIZE / 1024});
    const cmps = [_]Cmp{
        try runCmp(io, "ascii", fillAscii),
        try runCmp(io, "sbcs ", fillCyrillic),
        try runCmp(io, "cjk  ", fillCjk),
        try runCmp(io, "utf8 ", fillUtf8),
    };
    std.debug.print("    {s:<8} {s:>12} {s:>12} {s:>8}\n", .{ "input", "chardetz", "uchardet", "speedup" });
    var total_bytes: usize = 0;
    var total_cz_ns: u64 = 0;
    var total_uc_ns: u64 = 0;
    for (cmps) |m| {
        const cz_mbps = mbps(THROUGHPUT_SIZE, m.cz_ns);
        const uc_mbps = mbps(THROUGHPUT_SIZE, m.uc_ns);
        const speedup = @as(f64, @floatFromInt(m.uc_ns)) / @as(f64, @floatFromInt(@max(m.cz_ns, 1)));
        std.debug.print("    {s:<8} {d:>9.1} MB/s {d:>9.1} MB/s {d:>7.2}x\n", .{ m.label, cz_mbps, uc_mbps, speedup });
        total_bytes += THROUGHPUT_SIZE;
        total_cz_ns += m.cz_ns;
        total_uc_ns += m.uc_ns;
    }
    const agg_cz = mbps(total_bytes, total_cz_ns);
    const agg_uc = mbps(total_bytes, total_uc_ns);
    const agg_speedup = @as(f64, @floatFromInt(total_uc_ns)) / @as(f64, @floatFromInt(@max(total_cz_ns, 1)));
    std.debug.print("    {s:<8} {d:>9.1} MB/s {d:>9.1} MB/s {d:>7.2}x  (aggregate)\n", .{ "ALL", agg_cz, agg_uc, agg_speedup });

    // ── ndjson line for ./bm to log + compare (machine-id added by ./bm) ──
    std.debug.print(
        "@@NDJSON@@ {{\"v\":1,\"agg_cz_mbps\":{d:.2},\"agg_uc_mbps\":{d:.2},\"agg_speedup\":{d:.3}," ++
            "\"ascii_cz_mbps\":{d:.2},\"sbcs_cz_mbps\":{d:.2},\"cjk_cz_mbps\":{d:.2},\"utf8_cz_mbps\":{d:.2}," ++
            "\"worst_scale_ratio\":{d:.3},\"scale_pass\":{s}}}\n",
        .{
            agg_cz, agg_uc, agg_speedup,
            mbps(THROUGHPUT_SIZE, cmps[0].cz_ns), mbps(THROUGHPUT_SIZE, cmps[1].cz_ns),
            mbps(THROUGHPUT_SIZE, cmps[2].cz_ns), mbps(THROUGHPUT_SIZE, cmps[3].cz_ns),
            worst, if (all_passed) "true" else "false",
        },
    );

    std.debug.print("\n(sink={d})\n", .{sink}); // keep the optimizer honest

    if (!all_passed) {
        std.debug.print("\n\x1b[31mSCALING GATE FAILED\x1b[0m (worst doubling ratio {d:.2}x >= {d:.2}x) — a hot path went super-linear.\n", .{ worst, SCALE_FAIL_RATIO });
        std.process.exit(1);
    }
    std.debug.print("\n\x1b[32mScaling gate PASSED\x1b[0m (worst doubling ratio {d:.2}x).\n", .{worst});
}
