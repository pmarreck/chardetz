//! Pure core of the accuracy-corpus generator: UDHR XML to plain text, cutting
//! by codepoints, transcoding through an injected `Transcoder` (iconv in the
//! real tool), and the ground-truth rule "an answer is right when its decoding
//! of the bytes reproduces the encoded text". No I/O.
const std = @import("std");

pub const ConvertError = error{ Unsupported, Invalid, OutOfMemory };

/// Converts `bytes` from charset `from` to charset `to`; the caller owns the
/// result. Injected so the core is testable without iconv.
pub const Transcoder = struct {
    ctx: *anyopaque,
    convertFn: *const fn (ctx: *anyopaque, gpa: std.mem.Allocator, from: []const u8, to: []const u8, bytes: []const u8) ConvertError![]u8,

    pub fn convert(t: Transcoder, gpa: std.mem.Allocator, from: []const u8, to: []const u8, bytes: []const u8) ConvertError![]u8 {
        return t.convertFn(t.ctx, gpa, from, to, bytes);
    }
};

/// Plain text of a UDHR XML document: the trimmed text of each element, one
/// per line, with the five predefined entities and character references
/// decoded. Markup, comments, processing instructions and attributes are
/// dropped. Enough XML for the UDHR files, not a general parser.
pub fn extractText(gpa: std.mem.Allocator, xml: []const u8) error{ OutOfMemory, BadEntity, BadMarkup }![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var node: std.ArrayList(u8) = .empty;
    defer node.deinit(gpa);
    var i: usize = 0;
    while (i < xml.len) {
        if (xml[i] == '<') {
            try flushNode(gpa, &out, node.items);
            node.clearRetainingCapacity();
            const close = if (std.mem.startsWith(u8, xml[i..], "<!--")) "-->" else ">";
            const end = std.mem.indexOfPos(u8, xml, i + 1, close) orelse return error.BadMarkup;
            i = end + close.len;
        } else if (xml[i] == '&') {
            const end = std.mem.indexOfScalarPos(u8, xml, i, ';') orelse return error.BadEntity;
            try decodeEntity(gpa, &node, xml[i + 1 .. end]);
            i = end + 1;
        } else {
            try node.append(gpa, xml[i]);
            i += 1;
        }
    }
    try flushNode(gpa, &out, node.items);
    return out.toOwnedSlice(gpa);
}

fn flushNode(gpa: std.mem.Allocator, out: *std.ArrayList(u8), node: []const u8) !void {
    const trimmed = std.mem.trim(u8, node, " \t\r\n");
    if (trimmed.len == 0) return;
    if (out.items.len > 0) try out.append(gpa, '\n');
    try out.appendSlice(gpa, trimmed);
}

fn decodeEntity(gpa: std.mem.Allocator, node: *std.ArrayList(u8), name: []const u8) !void {
    const named = [_]struct { []const u8, u8 }{ .{ "amp", '&' }, .{ "lt", '<' }, .{ "gt", '>' }, .{ "quot", '"' }, .{ "apos", '\'' } };
    for (named) |n| if (std.mem.eql(u8, name, n[0])) return node.append(gpa, n[1]);
    if (name.len < 2 or name[0] != '#') return error.BadEntity;
    const cp = (if (name[1] == 'x' or name[1] == 'X')
        std.fmt.parseInt(u21, name[2..], 16)
    else
        std.fmt.parseInt(u21, name[1..], 10)) catch return error.BadEntity;
    var buf: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &buf) catch return error.BadEntity;
    try node.appendSlice(gpa, buf[0..n]);
}

/// The first `n` codepoints of valid UTF-8 `s` (all of it if shorter).
pub fn prefixCodepoints(s: []const u8, n: usize) []const u8 {
    var i: usize = 0;
    var count: usize = 0;
    while (i < s.len and count < n) : (count += 1) {
        i += std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
    }
    return s[0..@min(i, s.len)];
}

pub fn codepointCount(s: []const u8) usize {
    return std.unicode.utf8CountCodepoints(s) catch s.len;
}

/// Typographic punctuation that many legacy charsets lack, mapped to ASCII.
/// Used only when a text cannot be encoded as it is.
const punctuation = [_]struct { []const u8, []const u8 }{
    .{ "\u{201C}", "\"" },  .{ "\u{201D}", "\"" }, .{ "\u{201E}", "\"" }, .{ "\u{201F}", "\"" },
    .{ "\u{2018}", "'" },   .{ "\u{2019}", "'" },  .{ "\u{201A}", "'" },  .{ "\u{201B}", "'" },
    .{ "\u{2013}", "-" },   .{ "\u{2014}", "-" },  .{ "\u{2010}", "-" },  .{ "\u{2011}", "-" },
    .{ "\u{2026}", "..." },
};

pub fn normalizePunctuation(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    outer: while (i < s.len) {
        for (punctuation) |p| if (std.mem.startsWith(u8, s[i..], p[0])) {
            try out.appendSlice(gpa, p[1]);
            i += p[0].len;
            continue :outer;
        };
        try out.append(gpa, s[i]);
        i += 1;
    }
    return out.toOwnedSlice(gpa);
}

/// How faithfully a case reproduces its source text.
pub const Fidelity = enum {
    exact,
    /// Typographic punctuation was mapped to ASCII first.
    normalized,
    /// Additionally, a few characters the charset lacks were dropped.
    lossy,
};

/// One generated input: its bytes, and the UTF-8 text those bytes encode in
/// the target charset (the ground truth every answer is checked against).
pub const Case = struct {
    bytes: []u8,
    truth: []u8,
    fidelity: Fidelity,

    pub fn deinit(c: *Case, gpa: std.mem.Allocator) void {
        gpa.free(c.bytes);
        gpa.free(c.truth);
    }
};

/// At most this share of a text's codepoints (or one codepoint) may be
/// dropped as unrepresentable before a case is skipped instead.
pub const max_dropped_percent = 2;

/// Encodes UTF-8 `text` as `encoding`: as it is, else with normalized
/// punctuation, else also without the characters the charset lacks if there
/// are few of them. Null when none of these works.
pub fn encodeCase(gpa: std.mem.Allocator, t: Transcoder, text: []const u8, encoding: []const u8) ConvertError!?Case {
    if (try tryEncode(gpa, t, text, encoding)) |bytes| return finish(gpa, t, bytes, encoding, .exact);
    const plain = try normalizePunctuation(gpa, text);
    defer gpa.free(plain);
    if (try tryEncode(gpa, t, plain, encoding)) |bytes| return finish(gpa, t, bytes, encoding, .normalized);
    var dropped: usize = 0;
    const kept = try dropUnrepresentable(gpa, t, plain, encoding, &dropped);
    defer gpa.free(kept);
    if (dropped > @max(1, codepointCount(plain) * max_dropped_percent / 100)) return null;
    if (try tryEncode(gpa, t, kept, encoding)) |bytes| return finish(gpa, t, bytes, encoding, .lossy);
    return null;
}

fn tryEncode(gpa: std.mem.Allocator, t: Transcoder, text: []const u8, encoding: []const u8) ConvertError!?[]u8 {
    return t.convert(gpa, "UTF-8", encoding, text) catch |e| switch (e) {
        error.Invalid => null,
        else => e,
    };
}

/// Takes ownership of `bytes`; the truth is the bytes' own decoding.
fn finish(gpa: std.mem.Allocator, t: Transcoder, bytes: []u8, encoding: []const u8, fidelity: Fidelity) ConvertError!?Case {
    const truth = t.convert(gpa, encoding, "UTF-8", bytes) catch |e| {
        gpa.free(bytes);
        return switch (e) {
            error.Invalid => null,
            else => e,
        };
    };
    return .{ .bytes = bytes, .truth = truth, .fidelity = fidelity };
}

/// `text` without the codepoints `encoding` cannot represent on their own,
/// counted in `dropped`. Each distinct codepoint is tried once.
fn dropUnrepresentable(gpa: std.mem.Allocator, t: Transcoder, text: []const u8, encoding: []const u8, dropped: *usize) ConvertError![]u8 {
    var verdicts: std.AutoHashMapUnmanaged(u21, bool) = .empty;
    defer verdicts.deinit(gpa);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var it = (std.unicode.Utf8View.init(text) catch return error.Invalid).iterator();
    while (it.nextCodepointSlice()) |cp_bytes| {
        const cp = std.unicode.utf8Decode(cp_bytes) catch return error.Invalid;
        const entry = try verdicts.getOrPut(gpa, cp);
        if (!entry.found_existing) {
            const encoded = try tryEncode(gpa, t, cp_bytes, encoding);
            if (encoded) |e| gpa.free(e);
            entry.value_ptr.* = encoded != null;
        }
        if (entry.value_ptr.*) try out.appendSlice(gpa, cp_bytes) else dropped.* += 1;
    }
    return out.toOwnedSlice(gpa);
}

/// The candidates whose decoding of `bytes` is exactly `truth`, in the
/// candidates' order. The slice is owned by the caller; its names are not.
pub fn acceptable(gpa: std.mem.Allocator, t: Transcoder, bytes: []const u8, truth: []const u8, candidates: []const []const u8) error{OutOfMemory}![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    errdefer out.deinit(gpa);
    for (candidates) |c| {
        const decoded = t.convert(gpa, c, "UTF-8", bytes) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        defer gpa.free(decoded);
        if (std.mem.eql(u8, decoded, truth)) try out.append(gpa, c);
    }
    return out.toOwnedSlice(gpa);
}

/// Whether ASCII bytes mean ASCII characters in `encoding`, so a plain-ASCII
/// prefix can be prepended without changing the encoding of what follows.
pub fn asciiCompatible(encoding: []const u8) bool {
    return !std.mem.startsWith(u8, encoding, "UTF-16") and !std.mem.startsWith(u8, encoding, "UTF-32");
}

pub const Text = struct {
    key: []const u8,
    language: []const u8,
    encodings: []const []const u8,
};

/// A source text to normalize by a round trip through a charset whose decoder
/// composes characters. glibc's WINDOWS-1258 decoder turns combining
/// Vietnamese accents into the precomposed letters VISCII needs.
pub const Compose = struct {
    key: []const u8,
    via: []const u8,
};

/// tests/accuracy/matrix.txt. Slices point into the input text.
pub const Matrix = struct {
    /// Codepoint lengths; null means the whole text.
    lengths: []const ?usize,
    candidates: []const []const u8,
    texts: []const Text,
    compose: []const Compose,
    utf8_all: bool,

    pub fn composeVia(m: *const Matrix, key: []const u8) ?[]const u8 {
        for (m.compose) |c| if (std.mem.eql(u8, c.key, key)) return c.via;
        return null;
    }

    pub fn deinit(m: *Matrix, gpa: std.mem.Allocator) void {
        gpa.free(m.lengths);
        gpa.free(m.candidates);
        for (m.texts) |t| gpa.free(t.encodings);
        gpa.free(m.texts);
        gpa.free(m.compose);
    }
};

pub fn parseMatrix(gpa: std.mem.Allocator, text: []const u8) error{ OutOfMemory, BadMatrix }!Matrix {
    var lengths: std.ArrayList(?usize) = .empty;
    errdefer lengths.deinit(gpa);
    var candidates: std.ArrayList([]const u8) = .empty;
    errdefer candidates.deinit(gpa);
    var texts: std.ArrayList(Text) = .empty;
    errdefer {
        for (texts.items) |t| gpa.free(t.encodings);
        texts.deinit(gpa);
    }
    var compose: std.ArrayList(Compose) = .empty;
    errdefer compose.deinit(gpa);
    var utf8_all = false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var words = std.mem.tokenizeAny(u8, line, " \t");
        const directive = words.next().?;
        if (std.mem.eql(u8, directive, "lengths")) {
            while (words.next()) |w| try lengths.append(gpa, if (std.mem.eql(u8, w, "full")) null else std.fmt.parseInt(usize, w, 10) catch return error.BadMatrix);
        } else if (std.mem.eql(u8, directive, "candidate")) {
            const before = candidates.items.len;
            while (words.next()) |w| try candidates.append(gpa, w);
            if (candidates.items.len == before) return error.BadMatrix;
        } else if (std.mem.eql(u8, directive, "text")) {
            const key = words.next() orelse return error.BadMatrix;
            const language = words.next() orelse return error.BadMatrix;
            var encodings: std.ArrayList([]const u8) = .empty;
            errdefer encodings.deinit(gpa);
            while (words.next()) |w| try encodings.append(gpa, w);
            if (encodings.items.len == 0) return error.BadMatrix;
            const owned = try encodings.toOwnedSlice(gpa);
            errdefer gpa.free(owned);
            try texts.append(gpa, .{ .key = key, .language = language, .encodings = owned });
        } else if (std.mem.eql(u8, directive, "compose")) {
            const key = words.next() orelse return error.BadMatrix;
            const via = words.next() orelse return error.BadMatrix;
            try compose.append(gpa, .{ .key = key, .via = via });
        } else if (std.mem.eql(u8, directive, "utf8-all")) {
            utf8_all = true;
        } else return error.BadMatrix;
    }
    if (lengths.items.len == 0 or candidates.items.len == 0) return error.BadMatrix;
    return .{
        .lengths = try lengths.toOwnedSlice(gpa),
        .candidates = try candidates.toOwnedSlice(gpa),
        .texts = try texts.toOwnedSlice(gpa),
        .compose = try compose.toOwnedSlice(gpa),
        .utf8_all = utf8_all,
    };
}

/// Exactly `len` bytes of plain ASCII made by repeating the ASCII bytes of
/// `text` after punctuation normalization (other non-ASCII bytes dropped).
pub fn asciiPrefix(gpa: std.mem.Allocator, text: []const u8, len: usize) error{ OutOfMemory, NoAscii }![]u8 {
    const plain = try normalizePunctuation(gpa, text);
    defer gpa.free(plain);
    var ascii: std.ArrayList(u8) = .empty;
    defer ascii.deinit(gpa);
    for (plain) |b| if (b < 0x80) try ascii.append(gpa, b);
    if (ascii.items.len == 0) return error.NoAscii;
    const out = try gpa.alloc(u8, len);
    for (out, 0..) |*b, i| b.* = ascii.items[i % ascii.items.len];
    return out;
}
