// ***** BEGIN LICENSE BLOCK *****
// Version: MPL 1.1/GPL 2.0/LGPL 2.1
//
// The contents of this file are subject to the Mozilla Public License Version
// 1.1 (the "License"); you may not use this file except in compliance with
// the License. You may obtain a copy of the License at
// http://www.mozilla.org/MPL/
//
// Software distributed under the License is distributed on an "AS IS" basis,
// WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
// for the specific language governing rights and limitations under the
// License.
//
// The Original Code is Mozilla Universal charset detector code.
//
// The Initial Developer of the Original Code is
// Netscape Communications Corporation.
// Portions created by the Initial Developer are Copyright (C) 2001
// the Initial Developer. All Rights Reserved.
//
// Contributor(s):
//          BYVoid <byvoid.kcp@gmail.com>
//
// Alternatively, the contents of this file may be used under the terms of
// either the GNU General Public License Version 2 or later (the "GPL"), or
// the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
// in which case the provisions of the GPL or the LGPL are applicable instead
// of those above. If you wish to allow use of your version of this file only
// under the terms of either the GPL or the LGPL, and not to allow others to
// use your version of this file under the terms of the MPL, indicate your
// decision by deleting the provisions above and replace them with the notice
// and other provisions required by the GPL or the LGPL. If you do not delete
// the provisions above, a recipient may use your version of this file under
// the terms of any one of the MPL, the GPL or the LGPL.
//
// ***** END LICENSE BLOCK *****
//
// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Translated to Zig from uchardetz src/uchardet.cpp @ abacfc1f.

//! uchardet's C ABI (include/uchardet.h, byte-identical to upstream) over the
//! Zig Detector, so existing uchardet consumers can link chardetz instead.
//! Buffers are length-delimited: embedded NUL bytes are ordinary data.
const std = @import("std");
const builtin = @import("builtin");
const Detector = @import("root.zig").Detector;

/// Heap used for handles and their scratch buffers.
const allocator = if (builtin.cpu.arch.isWasm())
    std.heap.wasm_allocator
else if (builtin.link_libc)
    std.heap.c_allocator
else
    std.heap.smp_allocator;

/// Opaque to C: `typedef struct uchardet *uchardet_t`.
const Handle = opaque {};

fn detectorOf(ud: *Handle) *Detector {
    return @ptrCast(@alignCast(ud));
}

/// Returns a new detector, or NULL when memory is exhausted.
export fn uchardet_new() callconv(.c) ?*Handle {
    const d = allocator.create(Detector) catch return null;
    d.* = .init(allocator);
    return @ptrCast(d);
}

/// Frees a detector; NULL is ignored, like C++ `delete` of a null pointer.
export fn uchardet_delete(ud: ?*Handle) callconv(.c) void {
    const h = ud orelse return;
    const d = detectorOf(h);
    d.deinit();
    allocator.destroy(d);
}

/// Feeds `len` bytes; returns non-zero only when memory is exhausted. `data`
/// may be NULL when `len` is 0.
export fn uchardet_handle_data(ud: *Handle, data: ?[*]const u8, len: usize) callconv(.c) c_int {
    const bytes: []const u8 = if (len == 0) &.{} else (data orelse return 1)[0..len];
    detectorOf(ud).handleData(bytes) catch return 1;
    return 0;
}

export fn uchardet_data_end(ud: *Handle) callconv(.c) void {
    detectorOf(ud).dataEnd();
}

export fn uchardet_reset(ud: *Handle) callconv(.c) void {
    detectorOf(ud).reset();
}

/// The detected charset name, or "" when none. The string is static, so it
/// stays valid for the life of the program (uchardet only promises until the
/// next reset or delete).
export fn uchardet_get_charset(ud: *Handle) callconv(.c) [*:0]const u8 {
    return detectorOf(ud).charset().ptr;
}

// -- One-shot ABI, mainly for WebAssembly hosts (see docs/wasm_abi.md) --

/// Detects `len` bytes at `ptr` in one call. Returns a NUL-terminated charset
/// name ("" when undetermined, or when memory is exhausted). Names are static,
/// so the pointer stays valid for the life of the module.
export fn chardetz_detect(ptr: ?[*]const u8, len: usize) callconv(.c) [*:0]const u8 {
    const bytes: []const u8 = if (len == 0) &.{} else (ptr orelse return "")[0..len];
    const name = @import("root.zig").detect(allocator, bytes) catch return "";
    return name.ptr;
}

/// Reserves `len` bytes for the host to write input into; NULL on failure.
export fn chardetz_alloc(len: usize) callconv(.c) ?[*]u8 {
    const buf = allocator.alloc(u8, len) catch return null;
    return buf.ptr;
}

/// Returns memory obtained from `chardetz_alloc` (pass the same `len`).
export fn chardetz_free(ptr: ?[*]u8, len: usize) callconv(.c) void {
    const p = ptr orelse return;
    allocator.free(p[0..len]);
}
