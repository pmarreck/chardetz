const std = @import("std");
const core = @import("core.zig");

const gpa = std.testing.allocator;

test "extractText keeps element text, one line per element, with entities decoded" {
    const xml =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!-- a comment <para>not text</para> -->
        \\<udhr key='x' n="Name &amp; more">
        \\   <title>Caf&#233; &amp; th&#xE9;</title>
        \\   <para>a &lt;b&gt; &quot;c&quot; &apos;d&apos;</para>
        \\   <orderedlist><listitem><para>  nested  </para></listitem></orderedlist>
        \\   <para/>
        \\</udhr>
    ;
    const text = try core.extractText(gpa, xml);
    defer gpa.free(text);
    try std.testing.expectEqualStrings("Café & thé\na <b> \"c\" 'd'\nnested", text);
}

test "extractText rejects an unknown entity" {
    try std.testing.expectError(error.BadEntity, core.extractText(gpa, "<p>&nbsp;</p>"));
}

test "prefixCodepoints cuts on codepoint boundaries" {
    const s = "a\xC3\xA9\xE2\x82\xACz"; // a é € z
    try std.testing.expectEqualStrings("", core.prefixCodepoints(s, 0));
    try std.testing.expectEqualStrings("a\xC3\xA9", core.prefixCodepoints(s, 2));
    try std.testing.expectEqualStrings("a\xC3\xA9\xE2\x82\xAC", core.prefixCodepoints(s, 3));
    try std.testing.expectEqualStrings(s, core.prefixCodepoints(s, 99));
    try std.testing.expectEqual(@as(usize, 4), core.codepointCount(s));
}

test "normalizePunctuation maps typographic punctuation to ASCII" {
    const out = try core.normalizePunctuation(gpa, "\xE2\x80\x9Cx\xE2\x80\x9D \xE2\x80\x98y\xE2\x80\x99 a\xE2\x80\x94b\xE2\x80\xA6 \xC2\xAB\xC3\xA9\xC2\xBB");
    defer gpa.free(out);
    try std.testing.expectEqualStrings("\"x\" 'y' a-b... \xC2\xAB\xC3\xA9\xC2\xBB", out);
}

/// Fake transcoder over three made-up encodings, all decoding to UTF-8:
/// "ID" passes bytes through; "ASC" accepts only bytes < 0x80; "SHIFT" stores
/// each byte plus one.
const Fake = struct {
    calls: usize = 0,

    fn convert(ctx: *anyopaque, a: std.mem.Allocator, from: []const u8, to: []const u8, bytes: []const u8) core.ConvertError![]u8 {
        const self: *Fake = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        const encoding = if (std.mem.eql(u8, from, "UTF-8")) to else from;
        const out = try a.dupe(u8, bytes);
        errdefer a.free(out);
        if (std.mem.eql(u8, encoding, "ID")) return out;
        if (std.mem.eql(u8, encoding, "ASC")) {
            for (out) |b| if (b >= 0x80) return error.Invalid;
            return out;
        }
        if (std.mem.eql(u8, encoding, "SHIFT")) {
            const decoding = !std.mem.eql(u8, from, "UTF-8");
            for (out) |*b| b.* = if (decoding) b.* -% 1 else b.* +% 1;
            return out;
        }
        return error.Unsupported;
    }

    fn transcoder(self: *Fake) core.Transcoder {
        return .{ .ctx = self, .convertFn = convert };
    }
};

test "acceptable lists exactly the candidates that decode the bytes to the truth" {
    var fake: Fake = .{};
    const t = fake.transcoder();
    const set = try core.acceptable(gpa, t, "ab", "ab", &.{ "ID", "ASC", "SHIFT", "NOPE" });
    defer gpa.free(set);
    try std.testing.expectEqual(@as(usize, 2), set.len);
    try std.testing.expectEqualStrings("ID", set[0]);
    try std.testing.expectEqualStrings("ASC", set[1]);

    const high = try core.acceptable(gpa, t, "a\xC3\xA9", "a\xC3\xA9", &.{ "ID", "ASC", "SHIFT" });
    defer gpa.free(high);
    try std.testing.expectEqual(@as(usize, 1), high.len);
    try std.testing.expectEqualStrings("ID", high[0]);
}

test "encodeCase uses the bytes' own decoding as the truth" {
    var fake: Fake = .{};
    const t = fake.transcoder();
    var c = (try core.encodeCase(gpa, t, "abc", "SHIFT")).?;
    defer c.deinit(gpa);
    try std.testing.expectEqualStrings("bcd", c.bytes);
    try std.testing.expectEqualStrings("abc", c.truth);
    try std.testing.expectEqual(core.Fidelity.exact, c.fidelity);
}

test "encodeCase retries with normalized punctuation" {
    var fake: Fake = .{};
    const t = fake.transcoder();
    var c = (try core.encodeCase(gpa, t, "\xE2\x80\x9Cok\xE2\x80\x9D", "ASC")).?;
    defer c.deinit(gpa);
    try std.testing.expectEqualStrings("\"ok\"", c.bytes);
    try std.testing.expectEqual(core.Fidelity.normalized, c.fidelity);
    try std.testing.expectEqual(@as(?core.Case, null), try core.encodeCase(gpa, t, "\xC3\xA9\xC3\xA9\xC3\xA9", "ASC"));
}

test "parseMatrix reads lengths, candidates, texts and utf8-all" {
    const text =
        \\# comment
        \\lengths 8 16 full
        \\candidate A B
        \\candidate C
        \\
        \\text rus ru KOI8-R UTF-16
        \\utf8-all
    ;
    var m = try core.parseMatrix(gpa, text);
    defer m.deinit(gpa);
    try std.testing.expectEqualSlices(?usize, &.{ 8, 16, null }, m.lengths);
    try std.testing.expectEqual(@as(usize, 3), m.candidates.len);
    try std.testing.expectEqualStrings("C", m.candidates[2]);
    try std.testing.expectEqual(@as(usize, 1), m.texts.len);
    try std.testing.expectEqualStrings("rus", m.texts[0].key);
    try std.testing.expectEqualStrings("ru", m.texts[0].language);
    try std.testing.expectEqualStrings("UTF-16", m.texts[0].encodings[1]);
    try std.testing.expect(m.utf8_all);
}

test "parseMatrix rejects unknown directives and candidates naming nothing" {
    try std.testing.expectError(error.BadMatrix, core.parseMatrix(gpa, "bogus x\n"));
    try std.testing.expectError(error.BadMatrix, core.parseMatrix(gpa, "candidate\n"));
    try std.testing.expectError(error.BadMatrix, core.parseMatrix(gpa, "lengths 8 x\n"));
}

test "asciiCompatible classifies encodings by whether ASCII bytes keep their meaning" {
    const yes = [_][]const u8{ "ASCII", "UTF-8", "ISO-8859-1", "KOI8-R", "SHIFT_JIS", "ISO-2022-JP", "GB18030" };
    const no = [_][]const u8{ "UTF-16", "UTF-16LE", "UTF-16BE", "UTF-32" };
    for (yes) |e| try std.testing.expect(core.asciiCompatible(e));
    for (no) |e| try std.testing.expect(!core.asciiCompatible(e));
}

test "asciiPrefix repeats the ASCII bytes of a text to an exact length" {
    const p = try core.asciiPrefix(gpa, "ab\xC3\xA9 \xE2\x80\x9Cc\xE2\x80\x9D", 11);
    defer gpa.free(p);
    try std.testing.expectEqualStrings("ab \"c\"ab \"c", p);
    try std.testing.expectError(error.NoAscii, core.asciiPrefix(gpa, "\xC3\xA9", 4));
}

test "encodeCase drops a few unrepresentable characters, but not many" {
    var fake: Fake = .{};
    const t = fake.transcoder();
    // One of 50 codepoints (2%) may go.
    const one_in_fifty = "caf\xC3\xA9" ++ "x" ** 46;
    var c = (try core.encodeCase(gpa, t, one_in_fifty, "ASC")).?;
    defer c.deinit(gpa);
    try std.testing.expectEqual(core.Fidelity.lossy, c.fidelity);
    try std.testing.expectEqualStrings("caf" ++ "x" ** 46, c.bytes);
    try std.testing.expectEqualStrings(c.bytes, c.truth);
    // A single character may always go, so short texts are not all skipped.
    var short = (try core.encodeCase(gpa, t, "caf\xC3\xA9", "ASC")).?;
    defer short.deinit(gpa);
    try std.testing.expectEqualStrings("caf", short.bytes);
    // Two of 50 is too many.
    const two_in_fifty = "caf\xC3\xA9\xC3\xA9" ++ "x" ** 45;
    try std.testing.expectEqual(@as(?core.Case, null), try core.encodeCase(gpa, t, two_in_fifty, "ASC"));
}

test "parseMatrix reads compose directives" {
    var m = try core.parseMatrix(gpa, "lengths full\ncandidate A\ncompose vie WINDOWS-1258\n");
    defer m.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 1), m.compose.len);
    try std.testing.expectEqualStrings("vie", m.compose[0].key);
    try std.testing.expectEqualStrings("WINDOWS-1258", m.compose[0].via);
    try std.testing.expectEqualStrings("WINDOWS-1258", m.composeVia("vie").?);
    try std.testing.expectEqual(@as(?[]const u8, null), m.composeVia("fra"));
}
