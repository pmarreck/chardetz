// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported ABI from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING / include/uchardet.h.
//
// The uchardet-compatible C FFI: chardetz is a BINARY DROP-IN for uchardet —
// the six exported functions below match `include/uchardet.h`'s ABI exactly
// (same names, same signatures, same ownership/return semantics). Consumers
// linking against `libchardetz.a` and `#include "uchardet.h"` get chardetz's
// pure-Zig detection engine with zero source changes.
//
// ARCHITECTURE (house rule): this file is the real public API. The C CLI in
// cli/main.c calls THROUGH this ABI (it `#include`s uchardet.h and links the
// static lib), dogfooding the FFI rather than importing Zig directly. The WASM
// target (see chardetz_detect below) also goes through this surface.

const std = @import("std");
const builtin = @import("builtin");
const detector = @import("detector.zig");

const UniversalDetector = detector.UniversalDetector;

/// Allocator for FFI handles. On WASM-freestanding there is no libc, so use the
/// WASM page allocator; everywhere else the lib links libc, so use the C
/// allocator (malloc/free) — which keeps handle lifetime under the C runtime's
/// control, exactly as a uchardet consumer expects.
const ffi_allocator: std.mem.Allocator = if (builtin.target.cpu.arch.isWasm() and builtin.target.os.tag == .freestanding)
    std.heap.wasm_allocator
else
    std.heap.c_allocator;

/// Longest charset name uchardet emits is well under this (e.g. "MAC-CYRILLIC"
/// = 12, "WINDOWS-1255" = 12). 64 leaves generous headroom + the NUL.
const NAME_BUF_LEN = 64;

/// The opaque handle the C ABI hands back as `uchardet_t`. Wraps a heap
/// UniversalDetector plus a private NUL-terminated buffer for get_charset's
/// return. We copy the detected name into our own NUL-terminated buffer rather
/// than returning a pointer into the engine's static string slices: that makes
/// the C-string contract robust (guaranteed NUL terminator, stable for the
/// handle's lifetime) and independent of how the engine happens to slice its
/// charset-name literals.
const Handle = struct {
    det: UniversalDetector,
    /// NUL-terminated snapshot of the most recent get_charset result.
    name: [NAME_BUF_LEN]u8,

    fn refreshName(self: *Handle) void {
        const cs = self.det.getCharset();
        const n = @min(cs.len, NAME_BUF_LEN - 1);
        @memcpy(self.name[0..n], cs[0..n]);
        self.name[n] = 0;
    }
};

/// uchardet_t — opaque pointer to a detector instance. Matches the typedef in
/// uchardet.h (`typedef struct uchardet * uchardet_t`).
pub const uchardet_t = ?*anyopaque;

fn fromOpaque(ud: uchardet_t) ?*Handle {
    return @ptrCast(@alignCast(ud));
}

/// uchardet_new — allocate a detector handle. Returns NULL on OOM (a C consumer
/// must null-check, same as any allocating C API).
pub fn uchardet_new() callconv(.c) uchardet_t {
    const h = ffi_allocator.create(Handle) catch return null;
    h.det = UniversalDetector.init(ffi_allocator);
    h.name[0] = 0;
    return @ptrCast(h);
}

/// uchardet_delete — free a detector handle. NULL-safe (no-op on NULL).
pub fn uchardet_delete(ud: uchardet_t) callconv(.c) void {
    const h = fromOpaque(ud) orelse return;
    ffi_allocator.destroy(h);
}

/// uchardet_handle_data — feed bytes (streaming). Returns 0 on success,
/// non-zero on failure (NULL handle, or NULL data with non-zero len).
pub fn uchardet_handle_data(ud: uchardet_t, data: ?[*]const u8, len: usize) callconv(.c) c_int {
    const h = fromOpaque(ud) orelse return 1;
    if (len == 0) return 0; // nothing to feed; matches uchardet (no-op, success)
    const ptr = data orelse return 1;
    h.det.handleData(ptr[0..len]);
    return 0;
}

/// uchardet_data_end — signal end of input; finalizes the verdict. NULL-safe.
pub fn uchardet_data_end(ud: uchardet_t) callconv(.c) void {
    const h = fromOpaque(ud) orelse return;
    h.det.dataEnd();
}

/// uchardet_reset — reset to the initial state for reuse. NULL-safe.
pub fn uchardet_reset(ud: uchardet_t) callconv(.c) void {
    const h = fromOpaque(ud) orelse return;
    h.det.reset();
}

/// uchardet_get_charset — NUL-terminated iconv-compatible charset name, or ""
/// if undetermined. The pointer is valid until the next call on this handle or
/// uchardet_delete. NULL handle yields "".
pub fn uchardet_get_charset(ud: uchardet_t) callconv(.c) [*:0]const u8 {
    const h = fromOpaque(ud) orelse return empty_cstr;
    h.refreshName();
    // Reinterpret the NUL-terminated buffer as a sentinel-terminated C string.
    return @ptrCast(&h.name);
}

const empty_cstr: [*:0]const u8 = "";

// ── Export the C ABI symbols (Zig 0.16: @export takes a pointer) ─────────────
// These land in libchardetz.a because src/chardetz.zig force-references this
// module (`comptime { _ = @import("ffi.zig"); }`).
comptime {
    @export(&uchardet_new, .{ .name = "uchardet_new", .linkage = .strong });
    @export(&uchardet_delete, .{ .name = "uchardet_delete", .linkage = .strong });
    @export(&uchardet_handle_data, .{ .name = "uchardet_handle_data", .linkage = .strong });
    @export(&uchardet_data_end, .{ .name = "uchardet_data_end", .linkage = .strong });
    @export(&uchardet_reset, .{ .name = "uchardet_reset", .linkage = .strong });
    @export(&uchardet_get_charset, .{ .name = "uchardet_get_charset", .linkage = .strong });
}

// ── WASM one-shot ABI ────────────────────────────────────────────────────────
// Freestanding WASM has no libc, so it cannot use the uchardet streaming ABI's
// implied malloc/free lifecycle the same way. Instead we export a clean
// one-shot: the host writes input bytes into WASM linear memory, calls
// chardetz_detect(ptr, len), and reads back a NUL-terminated charset name from
// the returned pointer (the static charset-name literals live at valid WASM
// addresses). See docs/wasm_abi.md for the JS-side recipe.
//
// We keep a module-level NUL-terminated buffer so the returned pointer is
// stable and the name is guaranteed NUL-terminated (the engine's name slices
// may not be). Single-shot, single-threaded — fine for the WASM host model.
var wasm_name_buf: [NAME_BUF_LEN]u8 = undefined;

/// chardetz_detect — one-shot detection over WASM linear memory. Returns a
/// pointer to a NUL-terminated charset name ("" if undetermined). Valid until
/// the next chardetz_detect call.
pub fn chardetz_detect(ptr: [*]const u8, len: usize) callconv(.c) [*:0]const u8 {
    const cs = detector.detect(ffi_allocator, ptr[0..len]);
    const n = @min(cs.len, NAME_BUF_LEN - 1);
    @memcpy(wasm_name_buf[0..n], cs[0..n]);
    wasm_name_buf[n] = 0;
    return @ptrCast(&wasm_name_buf);
}

/// chardetz_alloc — allocate `len` bytes in WASM linear memory and return the
/// pointer, so the host can write input bytes there before calling
/// chardetz_detect. Returns NULL on failure. (Only meaningful on WASM; harmless
/// elsewhere.) The companion chardetz_free returns the memory.
pub fn chardetz_alloc(len: usize) callconv(.c) ?[*]u8 {
    if (len == 0) return null;
    const slice = ffi_allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

/// chardetz_free — return memory obtained from chardetz_alloc. The host must
/// pass back the same len it requested (WASM allocators are size-classed).
pub fn chardetz_free(ptr: ?[*]u8, len: usize) callconv(.c) void {
    const p = ptr orelse return;
    if (len == 0) return;
    ffi_allocator.free(p[0..len]);
}

comptime {
    if (builtin.target.cpu.arch.isWasm()) {
        @export(&chardetz_detect, .{ .name = "chardetz_detect", .linkage = .strong });
        @export(&chardetz_alloc, .{ .name = "chardetz_alloc", .linkage = .strong });
        @export(&chardetz_free, .{ .name = "chardetz_free", .linkage = .strong });
    }
}

// Tests for this FFI surface live in tests/unit/ffi_test.zig (reached via the
// named `chardetz` module so the aggregator discovers them — Zig does not
// auto-collect test blocks from transitively-imported files).
