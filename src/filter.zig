// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Port of nsCharSetProber::FilterWithoutEnglishLetters / FilterWithEnglishLetters
// (nsCharSetProber.cpp). These reduce a raw buffer to just the text segments
// relevant to a given prober family, collapsing runs of delimiters to a single
// space, before the SBCS group / Latin1 probers score it.
//
// Both allocate a new buffer (at most aLen bytes; the result is always shorter
// or equal) which the caller frees. Returning an allocated slice (rather than
// the upstream out-param + bool) is the idiomatic Zig shape; OOM surfaces as an
// error the caller handles (the callers mirror upstream's graceful fallback).

const std = @import("std");

/// FilterWithoutEnglishLetters — for scripts that do NOT use English letters
/// (every SBCS-group sub-prober). Keeps only segments that contain a high-bit
/// (MSB-set) byte and span more than a single symbol; ASCII letters and
/// pure-symbol/English runs are dropped, each kept segment terminated by a
/// single space. The kept bytes are the ORIGINAL high-ASCII bytes (unchanged),
/// which is what the language-model probers expect.
pub fn withoutEnglishLetters(allocator: std.mem.Allocator, buf: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, buf.len);
    errdefer allocator.free(out);

    var meet_msb = false;
    var w: usize = 0; // write index into out
    var prev: usize = 0; // start of the current candidate segment
    var cur: usize = 0;
    while (cur < buf.len) : (cur += 1) {
        const c = buf[cur];
        if ((c & 0x80) != 0) {
            meet_msb = true;
        } else if (c < 'A' or (c > 'Z' and c < 'a') or c > 'z') {
            // Symbol/punctuation → segment delimiter.
            if (meet_msb and cur > prev) {
                // Segment has >1 char and contains upper ASCII — keep it.
                while (prev < cur) : (prev += 1) {
                    out[w] = buf[prev];
                    w += 1;
                }
                prev += 1; // skip the delimiter
                out[w] = ' ';
                w += 1;
                meet_msb = false;
            } else {
                // Drop the segment (just a symbol or an English word).
                prev = cur + 1;
            }
        }
    }
    if (meet_msb and cur > prev) {
        while (prev < cur) : (prev += 1) {
            out[w] = buf[prev];
            w += 1;
        }
    }

    return try allocator.realloc(out, w);
}

/// FilterWithEnglishLetters — for scripts that mix English + upper ASCII
/// (the Latin1 prober). Drops HTML-tag contents and isolated symbols, keeping
/// text segments (collapsing delimiter runs to a single space). Unlike the
/// other filter, it does NOT require a high-bit byte in the segment.
pub fn withEnglishLetters(allocator: std.mem.Allocator, buf: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, buf.len);
    errdefer allocator.free(out);

    var is_in_tag = false;
    var w: usize = 0;
    var prev: usize = 0;
    var cur: usize = 0;
    while (cur < buf.len) : (cur += 1) {
        const c = buf[cur];
        if (c == '>') {
            is_in_tag = false;
        } else if (c == '<') {
            is_in_tag = true;
        }

        if ((c & 0x80) == 0 and (c < 'A' or (c > 'Z' and c < 'a') or c > 'z')) {
            if (cur > prev and !is_in_tag) {
                // Segment >1 char and not inside a tag — keep it.
                while (prev < cur) : (prev += 1) {
                    out[w] = buf[prev];
                    w += 1;
                }
                prev += 1;
                out[w] = ' ';
                w += 1;
            } else {
                prev = cur + 1;
            }
        }
    }
    if (!is_in_tag) {
        while (prev < cur) : (prev += 1) {
            out[w] = buf[prev];
            w += 1;
        }
    }

    return try allocator.realloc(out, w);
}
