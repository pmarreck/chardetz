//! Differential-oracle bookkeeping: classifies each corpus file as agreement,
//! divergence, fenced (an accepted divergence from the guarded ledger) or
//! pending (the Zig candidate has no answer yet). Pure; no I/O.
const std = @import("std");

/// One accepted divergence. It covers only this exact file, oracle answer and
/// candidate answer, and must state why the divergence is acceptable.
pub const Fence = struct { file: []const u8, oracle: []const u8, candidate: []const u8, reason: []const u8 };

/// The expected-divergences ledger (tests/expected_divergences.json), a JSON
/// array of fences. Malformed entries and empty reasons are rejected.
pub const Ledger = struct {
    parsed: ?std.json.Parsed([]Fence) = null,
    fences: []const Fence = &.{},

    pub fn parse(gpa: std.mem.Allocator, json: []const u8) !Ledger {
        const parsed = std.json.parseFromSlice([]Fence, gpa, json, .{}) catch return error.BadLedger;
        errdefer parsed.deinit();
        for (parsed.value) |f| {
            if (f.file.len == 0 or f.oracle.len == 0 or f.candidate.len == 0) return error.BadLedger;
            if (std.mem.trim(u8, f.reason, " \t\r\n").len == 0) return error.BadLedger;
        }
        return .{ .parsed = parsed, .fences = parsed.value };
    }

    pub fn deinit(self: *Ledger) void {
        if (self.parsed) |p| p.deinit();
        self.* = undefined;
    }

    fn find(self: *const Ledger, file: []const u8, oracle: []const u8, candidate: []const u8) ?usize {
        for (self.fences, 0..) |f, k| {
            if (std.mem.eql(u8, f.file, file) and std.mem.eql(u8, f.oracle, oracle) and std.mem.eql(u8, f.candidate, candidate)) return k;
        }
        return null;
    }
};

pub const Divergence = struct { file: []const u8, oracle: []const u8, candidate: []const u8 };

/// Accumulates verdicts. Strings passed to `record` must outlive the report.
pub const Report = struct {
    agree: usize = 0,
    pending: usize = 0,
    fenced: usize = 0,
    divergences: std.ArrayList(Divergence) = .empty,
    used_fences: std.DynamicBitSetUnmanaged = .{},

    pub fn deinit(self: *Report, gpa: std.mem.Allocator) void {
        self.divergences.deinit(gpa);
        self.used_fences.deinit(gpa);
    }

    pub fn record(self: *Report, gpa: std.mem.Allocator, ledger: *const Ledger, file: []const u8, oracle: []const u8, candidate: ?[]const u8) !void {
        const got = candidate orelse {
            self.pending += 1;
            return;
        };
        if (std.mem.eql(u8, oracle, got)) {
            self.agree += 1;
            return;
        }
        if (ledger.find(file, oracle, got)) |k| {
            if (self.used_fences.bit_length < ledger.fences.len) try self.used_fences.resize(gpa, ledger.fences.len, false);
            self.used_fences.set(k);
            self.fenced += 1;
            return;
        }
        try self.divergences.append(gpa, .{ .file = file, .oracle = oracle, .candidate = got });
    }

    fn fenceUsed(self: *const Report, k: usize) bool {
        return k < self.used_fences.bit_length and self.used_fences.isSet(k);
    }

    /// Passing requires no unfenced divergence and no stale fence: a fence that
    /// matched nothing means the ledger no longer describes reality.
    pub fn passed(self: *const Report, ledger: *const Ledger) bool {
        if (self.divergences.items.len != 0) return false;
        for (0..ledger.fences.len) |k| if (!self.fenceUsed(k)) return false;
        return true;
    }

    pub fn unusedFences(self: *const Report, gpa: std.mem.Allocator, ledger: *const Ledger) ![]const Fence {
        var out: std.ArrayList(Fence) = .empty;
        errdefer out.deinit(gpa);
        for (ledger.fences, 0..) |f, k| if (!self.fenceUsed(k)) try out.append(gpa, f);
        return out.toOwnedSlice(gpa);
    }
};

/// Upstream's test convention: the basename up to its first '.' names the
/// expected encoding (e.g. "fr/utf-16.be" -> "utf-16").
pub fn labelFromPath(path: []const u8) []const u8 {
    const base = if (std.mem.lastIndexOfScalar(u8, path, '/')) |s| path[s + 1 ..] else path;
    const dot = std.mem.indexOfScalar(u8, base, '.') orelse base.len;
    return base[0..dot];
}
