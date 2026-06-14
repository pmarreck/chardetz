// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Unit tests for the uchardet-compatible C FFI + the WASM one-shot ABI.
//
// Reaches the FFI through the named `chardetz` module (per the project's
// import convention — no `../src` relative paths across module roots). Tests
// in src/ffi.zig are NOT auto-discovered by the aggregator's bare
// `_ = @import("chardetz")` (Zig only collects test blocks from files
// explicitly pulled into the test-root import graph), so we exercise the
// exported C-ABI functions here, in a file the aggregator imports directly.

const std = @import("std");
const chardetz = @import("chardetz");
const ffi = chardetz.ffi;

test "ffi: new/handle_data/data_end/get_charset roundtrip on ASCII" {
    const ud = ffi.uchardet_new();
    try std.testing.expect(ud != null);
    defer ffi.uchardet_delete(ud);
    const data = "hello world this is plain ascii";
    try std.testing.expectEqual(@as(c_int, 0), ffi.uchardet_handle_data(ud, data.ptr, data.len));
    ffi.uchardet_data_end(ud);
    const cs = ffi.uchardet_get_charset(ud);
    try std.testing.expectEqualStrings("ASCII", std.mem.span(cs));
}

test "ffi: get_charset is NUL-terminated for a multi-char name" {
    const ud = ffi.uchardet_new();
    defer ffi.uchardet_delete(ud);
    const data = "\xEF\xBB\xBFhello"; // UTF-8 BOM forces "UTF-8"
    _ = ffi.uchardet_handle_data(ud, data.ptr, data.len);
    ffi.uchardet_data_end(ud);
    const cs = ffi.uchardet_get_charset(ud);
    try std.testing.expectEqualStrings("UTF-8", std.mem.span(cs));
    const name = std.mem.span(cs);
    try std.testing.expectEqual(@as(u8, 0), cs[name.len]); // explicit NUL
}

test "ffi: empty input yields empty string (undetermined)" {
    const ud = ffi.uchardet_new();
    defer ffi.uchardet_delete(ud);
    ffi.uchardet_data_end(ud);
    try std.testing.expectEqualStrings("", std.mem.span(ffi.uchardet_get_charset(ud)));
}

test "ffi: reset clears verdict for reuse" {
    const ud = ffi.uchardet_new();
    defer ffi.uchardet_delete(ud);
    const a = "\xEF\xBB\xBFx";
    _ = ffi.uchardet_handle_data(ud, a.ptr, a.len);
    ffi.uchardet_data_end(ud);
    try std.testing.expectEqualStrings("UTF-8", std.mem.span(ffi.uchardet_get_charset(ud)));
    ffi.uchardet_reset(ud);
    const b = "plain ascii again";
    _ = ffi.uchardet_handle_data(ud, b.ptr, b.len);
    ffi.uchardet_data_end(ud);
    try std.testing.expectEqualStrings("ASCII", std.mem.span(ffi.uchardet_get_charset(ud)));
}

test "ffi: NULL handle is safe and returns empty string" {
    try std.testing.expectEqual(@as(c_int, 1), ffi.uchardet_handle_data(null, "x", 1));
    ffi.uchardet_data_end(null); // no crash
    ffi.uchardet_reset(null); // no crash
    ffi.uchardet_delete(null); // no crash
    try std.testing.expectEqualStrings("", std.mem.span(ffi.uchardet_get_charset(null)));
}

test "ffi: handle_data with zero len is a successful no-op" {
    const ud = ffi.uchardet_new();
    defer ffi.uchardet_delete(ud);
    try std.testing.expectEqual(@as(c_int, 0), ffi.uchardet_handle_data(ud, null, 0));
}

test "wasm-shape: chardetz_detect one-shot returns NUL-terminated name" {
    const data = "\xEF\xBB\xBFhi";
    const cs = ffi.chardetz_detect(data.ptr, data.len);
    try std.testing.expectEqualStrings("UTF-8", std.mem.span(cs));
}
