// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Pins nsCharSetProber::FilterWithoutEnglishLetters / FilterWithEnglishLetters.
// The differential gate is the authoritative oracle; these check the byte-level
// segment-keeping/collapsing logic directly.

const std = @import("std");
const cz = @import("chardetz");
const filter = cz.filter;

const alloc = std.testing.allocator;

test "withoutEnglishLetters: pure ASCII letters/symbols are dropped entirely" {
    const out = try filter.withoutEnglishLetters(alloc, "hello, world!");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("", out);
}

test "withoutEnglishLetters: a high-ASCII run is kept, terminated by a space" {
    // "ab\xC0\xC1cd!" — the segment "ab\xC0\xC1cd" has a high bit, so it is kept
    // and a delimiter (the '!') becomes a single trailing space.
    const out = try filter.withoutEnglishLetters(alloc, "ab\xC0\xC1cd!");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("ab\xC0\xC1cd ", out);
}

test "withoutEnglishLetters: pure-English word segments between symbols are dropped" {
    // "foo \xE0\xE1 bar" → only the high-ASCII segment survives.
    const out = try filter.withoutEnglishLetters(alloc, "foo \xE0\xE1 bar");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("\xE0\xE1 ", out);
}

test "withEnglishLetters: keeps text but drops HTML tag contents" {
    const out = try filter.withEnglishLetters(alloc, "hi <b>x</b> bye");
    defer alloc.free(out);
    // The tag bodies are dropped; words are kept, delimiters collapse to spaces.
    try std.testing.expect(std.mem.indexOf(u8, out, "hi") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "bye") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<") == null);
}

test "withEnglishLetters: empty input → empty output" {
    const out = try filter.withEnglishLetters(alloc, "");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("", out);
}
