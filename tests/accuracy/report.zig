//! Pure core of the accuracy report: scores each detector's answer against a
//! case's ground truth (the charsets that decode its bytes to its text),
//! finds where chardetz and uchardet differ, and renders the committed ledger
//! (tests/accuracy/differences.tsv) and report (docs/ACCURACY_REPORT.md).
//! No I/O; tests/accuracy/runner.zig supplies the rows.
const std = @import("std");

/// How a case is fed to both detectors.
pub const Mode = enum {
    /// One call with the whole input.
    whole,
    /// One byte per call.
    bytewise,
    /// 64 KiB of plain ASCII first, then the case, read 64 KiB at a time as
    /// uchardet's own tool does.
    ascii_prefix,

    pub fn slug(m: Mode) []const u8 {
        return switch (m) {
            .whole => "whole",
            .bytewise => "bytewise",
            .ascii_prefix => "ascii-prefix",
        };
    }

    pub fn label(m: Mode) []const u8 {
        return switch (m) {
            .whole => "whole input",
            .bytewise => "1-byte chunks",
            .ascii_prefix => "after 64 KiB of ASCII",
        };
    }
};

pub const Row = struct {
    id: []const u8,
    language: []const u8,
    /// The charset the case was written in.
    encoding: []const u8,
    length: []const u8,
    fidelity: []const u8,
    mode: Mode,
    /// Every charset whose decoding of the input reproduces its text.
    acceptable: []const []const u8,
    upstream: []const u8,
    chardetz: []const u8,
    /// The accuracy fix (a `Fixes` field) whose effect alone turns uchardet's
    /// answer into chardetz's; "" when the answers agree.
    fix: []const u8,

    pub fn upstreamRight(r: Row) bool {
        return correct(r.upstream, r.acceptable);
    }
    pub fn chardetzRight(r: Row) bool {
        return correct(r.chardetz, r.acceptable);
    }
    pub fn differs(r: Row) bool {
        return !std.ascii.eqlIgnoreCase(r.upstream, r.chardetz);
    }
};

pub fn correct(answer: []const u8, acceptable: []const []const u8) bool {
    if (answer.len == 0) return false;
    for (acceptable) |a| if (std.ascii.eqlIgnoreCase(answer, a)) return true;
    return false;
}

/// Rows where chardetz is wrong although uchardet is right. Any of these
/// fails the suite: chardetz must never be less accurate than uchardet.
pub fn regressions(gpa: std.mem.Allocator, rows: []const Row) ![]Row {
    var out: std.ArrayList(Row) = .empty;
    errdefer out.deinit(gpa);
    for (rows) |r| if (r.upstreamRight() and !r.chardetzRight()) try out.append(gpa, r);
    return out.toOwnedSlice(gpa);
}

pub const Summary = struct {
    cases: usize = 0,
    chardetz_right: usize = 0,
    upstream_right: usize = 0,
    chardetz_only: usize = 0,
    upstream_only: usize = 0,
    both_wrong: usize = 0,
    chardetz_exact: usize = 0,
    upstream_exact: usize = 0,

    fn add(s: *Summary, r: Row) void {
        const c = r.chardetzRight();
        const u = r.upstreamRight();
        s.cases += 1;
        if (c) s.chardetz_right += 1;
        if (u) s.upstream_right += 1;
        if (c and !u) s.chardetz_only += 1;
        if (u and !c) s.upstream_only += 1;
        if (!c and !u) s.both_wrong += 1;
        if (std.ascii.eqlIgnoreCase(r.chardetz, r.encoding)) s.chardetz_exact += 1;
        if (std.ascii.eqlIgnoreCase(r.upstream, r.encoding)) s.upstream_exact += 1;
    }
};

pub fn summarize(rows: []const Row, mode: Mode) Summary {
    var s: Summary = .{};
    for (rows) |r| if (r.mode == mode) s.add(r);
    return s;
}

/// chardetz's correct answers per feeding mode, recorded in the report so a
/// regeneration can refuse to lower them.
pub const Counts = std.EnumArray(Mode, usize);

const ratchet_open = "<!-- ratchet:";

pub fn parseRatchet(text: []const u8) ?Counts {
    const start = std.mem.indexOf(u8, text, ratchet_open) orelse return null;
    const end = std.mem.indexOfPos(u8, text, start, "-->") orelse return null;
    var counts: Counts = .initFill(0);
    var seen: usize = 0;
    var words = std.mem.tokenizeScalar(u8, text[start + ratchet_open.len .. end], ' ');
    while (words.next()) |w| {
        const eq = std.mem.indexOfScalar(u8, w, '=') orelse return null;
        const n = std.fmt.parseInt(usize, w[eq + 1 ..], 10) catch return null;
        inline for (std.meta.fields(Mode)) |f| {
            const m: Mode = @enumFromInt(f.value);
            if (std.mem.eql(u8, w[0..eq], m.slug())) {
                counts.set(m, n);
                seen += 1;
            }
        }
    }
    return if (seen == std.meta.fields(Mode).len) counts else null;
}

fn lessByModeThenId(_: void, a: Row, b: Row) bool {
    const o = std.mem.order(u8, a.mode.slug(), b.mode.slug());
    if (o != .eq) return o == .lt;
    return std.mem.lessThan(u8, a.id, b.id);
}

pub fn renderLedger(gpa: std.mem.Allocator, rows: []const Row) ![]u8 {
    var diffs: std.ArrayList(Row) = .empty;
    defer diffs.deinit(gpa);
    for (rows) |r| if (r.differs()) try diffs.append(gpa, r);
    std.mem.sort(Row, diffs.items, {}, lessByModeThenId);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "# feeding\tcase\tuchardet\tuchardet_correct\tchardetz\tchardetz_correct\tfix\n");
    for (diffs.items) |r| try out.print(gpa, "{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t{s}\n", .{
        r.mode.slug(), r.id, r.upstream, yesNo(r.upstreamRight()), r.chardetz, yesNo(r.chardetzRight()), r.fix,
    });
    return out.toOwnedSlice(gpa);
}

fn yesNo(b: bool) []const u8 {
    return if (b) "yes" else "no";
}

pub const Meta = struct {
    udhr_rev: []const u8,
    uchardet_rev: []const u8,
    cases: usize,
    normalized: usize,
    lossy: usize,
};

/// A row of a grouped table: a key of up to four strings, how many rows fell
/// into it, and how many of them had each case length.
const Group = struct {
    key: [4][]const u8,
    count: usize = 0,
    lengths: std.ArrayList(LengthCount) = .empty,
    /// The key strings were allocated for this group.
    owns_key: bool = false,
};

const LengthCount = struct { length: []const u8, count: usize };

fn lengthOrder(l: []const u8) usize {
    return std.fmt.parseInt(usize, l, 10) catch std.math.maxInt(usize);
}

/// "8 (120), 16 (40), full (3)": distinct lengths in numeric order.
fn renderLengths(out: *std.ArrayList(u8), gpa: std.mem.Allocator, g: *Group) !void {
    std.mem.sort(LengthCount, g.lengths.items, {}, struct {
        fn lt(_: void, a: LengthCount, b: LengthCount) bool {
            return lengthOrder(a.length) < lengthOrder(b.length);
        }
    }.lt);
    for (g.lengths.items, 0..) |lc, i| {
        if (i > 0) try out.appendSlice(gpa, ", ");
        try out.print(gpa, "{s} ({d})", .{ lc.length, lc.count });
    }
}

fn groupInto(gpa: std.mem.Allocator, groups: *std.ArrayList(Group), key: [4][]const u8, length: []const u8) !void {
    const g = for (groups.items) |*g| {
        if (for (g.key, key) |a, b| {
            if (!std.mem.eql(u8, a, b)) break false;
        } else true) break g;
    } else blk: {
        try groups.append(gpa, .{ .key = key });
        break :blk &groups.items[groups.items.len - 1];
    };
    g.count += 1;
    for (g.lengths.items) |*lc| if (std.mem.eql(u8, lc.length, length)) {
        lc.count += 1;
        return;
    };
    try g.lengths.append(gpa, .{ .length = length, .count = 1 });
}

fn moreFirst(_: void, a: Group, b: Group) bool {
    if (a.count != b.count) return a.count > b.count;
    for (a.key, b.key) |x, y| {
        const o = std.mem.order(u8, x, y);
        if (o != .eq) return o == .lt;
    }
    return false;
}

fn freeGroups(gpa: std.mem.Allocator, groups: *std.ArrayList(Group)) void {
    for (groups.items) |*g| {
        g.lengths.deinit(gpa);
        if (g.owns_key) for (g.key) |k| gpa.free(k);
    }
    groups.deinit(gpa);
}

fn orNone(s: []const u8) []const u8 {
    return if (s.len == 0) "(none)" else s;
}

fn pct(out: *std.ArrayList(u8), gpa: std.mem.Allocator, n: usize, total: usize) !void {
    if (total == 0) return out.appendSlice(gpa, "0");
    const tenths = (n * 1000 + total / 2) / total;
    try out.print(gpa, "{d} ({d}.{d}%)", .{ n, tenths / 10, tenths % 10 });
}

/// Renders docs/ACCURACY_REPORT.md. Deterministic for a given row set.
pub fn renderReport(gpa: std.mem.Allocator, rows: []const Row, meta: Meta) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const modes = [_]Mode{ .whole, .bytewise, .ascii_prefix };

    try out.appendSlice(gpa,
        \\# Accuracy report
        \\
        \\Generated by `zig build accuracy-report`; `zig build test` fails when this file is stale. Do not edit by hand. The policy behind it is in `docs/ACCURACY.md`.
        \\
        \\
    );
    try out.print(gpa,
        \\Every case is a text from the Universal Declaration of Human Rights (UDHR in XML, revision `{s}`), cut to a length in characters and written in one charset with iconv. An answer is **right** when decoding the case's bytes with the named charset gives back exactly the text they encode, so for French text without `€`, ISO-8859-1, ISO-8859-15 and WINDOWS-1252 are all right. "Exact label" counts only the charset the case was written in. uchardet is the C++ original at uchardetz revision `{s}`; chardetz is the default build with every accuracy fix on.
        \\
        \\The corpus has {d} cases: every language and charset pair uchardet claims to detect, and every UDHR text as UTF-8, each at 8, 16, 32, 64, 128, 256 and 1024 characters and in full. {d} needed typographic punctuation replaced by ASCII to fit their charset, and {d} also had a few unrepresentable characters dropped (`tests/accuracy/matrix.txt` has the rules). HZ-GB-2312 is not covered because glibc iconv cannot write it.
        \\
        \\
    , .{ meta.udhr_rev, meta.uchardet_rev, meta.cases, meta.normalized, meta.lossy });

    try out.appendSlice(gpa, "## Summary\n\n| Feeding | Cases | chardetz right | uchardet right | Only chardetz right | Only uchardet right | Both wrong |\n|---|---|---|---|---|---|---|\n");
    var counts: Counts = .initFill(0);
    for (modes) |m| {
        const s = summarize(rows, m);
        counts.set(m, s.chardetz_right);
        try out.print(gpa, "| {s} | {d} | ", .{ m.label(), s.cases });
        try pct(&out, gpa, s.chardetz_right, s.cases);
        try out.appendSlice(gpa, " | ");
        try pct(&out, gpa, s.upstream_right, s.cases);
        try out.print(gpa, " | {d} | {d} | {d} |\n", .{ s.chardetz_only, s.upstream_only, s.both_wrong });
    }
    try out.print(gpa, "\n{s} whole={d} bytewise={d} ascii-prefix={d} -->\n\n", .{ ratchet_open, counts.get(.whole), counts.get(.bytewise), counts.get(.ascii_prefix) });
    try out.appendSlice(gpa, "\"After 64 KiB of ASCII\" covers only the charsets in which ASCII bytes mean ASCII, so not UTF-16 or UTF-32.\n\n");

    // Per encoding and per length, whole input.
    try out.appendSlice(gpa, "## By charset (whole input)\n\n| Charset | Cases | chardetz right | uchardet right | chardetz exact label | uchardet exact label |\n|---|---|---|---|---|---|\n");
    var encodings: std.ArrayList([]const u8) = .empty;
    defer encodings.deinit(gpa);
    for (rows) |r| if (r.mode == .whole) {
        for (encodings.items) |e| {
            if (std.mem.eql(u8, e, r.encoding)) break;
        } else try encodings.append(gpa, r.encoding);
    };
    std.mem.sort([]const u8, encodings.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    for (encodings.items) |e| {
        var s: Summary = .{};
        for (rows) |r| if (r.mode == .whole and std.mem.eql(u8, r.encoding, e)) s.add(r);
        try out.print(gpa, "| {s} | {d} | ", .{ e, s.cases });
        try pct(&out, gpa, s.chardetz_right, s.cases);
        try out.appendSlice(gpa, " | ");
        try pct(&out, gpa, s.upstream_right, s.cases);
        try out.appendSlice(gpa, " | ");
        try pct(&out, gpa, s.chardetz_exact, s.cases);
        try out.appendSlice(gpa, " | ");
        try pct(&out, gpa, s.upstream_exact, s.cases);
        try out.appendSlice(gpa, " |\n");
    }

    try out.appendSlice(gpa, "\n## By length (whole input)\n\n| Characters | Cases | chardetz right | uchardet right |\n|---|---|---|---|\n");
    var lengths: std.ArrayList([]const u8) = .empty;
    defer lengths.deinit(gpa);
    for (rows) |r| if (r.mode == .whole) {
        for (lengths.items) |l| {
            if (std.mem.eql(u8, l, r.length)) break;
        } else try lengths.append(gpa, r.length);
    };
    std.mem.sort([]const u8, lengths.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return lengthOrder(a) < lengthOrder(b);
        }
    }.lt);
    for (lengths.items) |l| {
        var s: Summary = .{};
        for (rows) |r| if (r.mode == .whole and std.mem.eql(u8, r.length, l)) s.add(r);
        try out.print(gpa, "| {s} | {d} | ", .{ l, s.cases });
        try pct(&out, gpa, s.chardetz_right, s.cases);
        try out.appendSlice(gpa, " | ");
        try pct(&out, gpa, s.upstream_right, s.cases);
        try out.appendSlice(gpa, " |\n");
    }

    // Differences.
    try out.appendSlice(gpa, "\n## Where chardetz and uchardet differ\n\nEach row groups cases with the same feeding, charset and pair of answers. \"Right\" says whose answer decodes the text correctly; \"Fix\" names the switch in `Fixes` (`src/detector.zig`) that accounts for the difference, explained in `docs/ACCURACY.md`: \"a or b\" means either switch alone gives chardetz's answer, and \"a+b+c\" means no single switch does but all of them together do. Every case is listed in `tests/accuracy/differences.tsv`.\n\n| Feeding | Charset | uchardet says | chardetz says | Cases | Right | Fix |\n|---|---|---|---|---|---|---|\n");
    var detailed: std.ArrayList(Group) = .empty;
    defer freeGroups(gpa, &detailed);
    for (rows) |r| if (r.differs()) {
        const who: []const u8 = if (r.chardetzRight()) "chardetz" else if (r.upstreamRight()) "uchardet" else "neither";
        // Feeding and charset are folded into one key slot to fit right and fix.
        const fm = try std.fmt.allocPrint(gpa, "{s} | {s}", .{ r.mode.label(), r.encoding });
        defer gpa.free(fm);
        const answers = try std.fmt.allocPrint(gpa, "{s} | {s}", .{ orNone(r.upstream), orNone(r.chardetz) });
        defer gpa.free(answers);
        try groupOwned(gpa, &detailed, .{ fm, answers, who, r.fix });
    };
    std.mem.sort(Group, detailed.items, {}, moreFirst);
    if (detailed.items.len == 0) try out.appendSlice(gpa, "| (none) | | | | | | |\n");
    for (detailed.items) |g| try out.print(gpa, "| {s} | {s} | {d} | {s} | `{s}` |\n", .{ g.key[0], g.key[1], g.count, g.key[2], g.key[3] });

    // Both wrong, whole input: candidates for future fixes.
    var wrong: std.ArrayList(Group) = .empty;
    defer freeGroups(gpa, &wrong);
    for (rows) |r| if (r.mode == .whole and !r.chardetzRight() and !r.upstreamRight()) {
        try groupInto(gpa, &wrong, .{ r.encoding, orNone(r.chardetz), "", "" }, r.length);
    };
    std.mem.sort(Group, wrong.items, {}, moreFirst);
    try out.appendSlice(gpa, "\n## Where both are wrong (whole input)\n\nCandidates for future accuracy fixes. Each row groups cases written in one charset that chardetz answers the same wrong way; \"Lengths\" lists the case lengths in characters.\n\n| Charset | chardetz says | Cases | Lengths |\n|---|---|---|---|\n");
    if (wrong.items.len == 0) try out.appendSlice(gpa, "| (none) | | | |\n");
    for (wrong.items) |*g| {
        try out.print(gpa, "| {s} | {s} | {d} | ", .{ g.key[0], g.key[1], g.count });
        try renderLengths(&out, gpa, g);
        try out.appendSlice(gpa, " |\n");
    }

    return out.toOwnedSlice(gpa);
}

/// Like groupInto, but the key strings are copied into the group's storage
/// (they are formatted per row).
fn groupOwned(gpa: std.mem.Allocator, groups: *std.ArrayList(Group), key: [4][]const u8) !void {
    for (groups.items) |*g| {
        if (for (g.key, key) |a, b| {
            if (!std.mem.eql(u8, a, b)) break false;
        } else true) {
            g.count += 1;
            return;
        }
    }
    var owned: [4][]const u8 = undefined;
    for (key, 0..) |k, i| owned[i] = try gpa.dupe(u8, k);
    try groups.append(gpa, .{ .key = owned, .count = 1, .owns_key = true });
}
