// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f).
// Tri-licensed MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later. See COPYING.
//
// Library/WASM artifact root. This is the root_source_file for the static
// library (`libchardetz.a`, exposing the uchardet C ABI) and the WASM target
// (`chardetz.wasm`, exposing the one-shot detect ABI). It force-references the
// FFI module so its `@export`ed symbols land in the artifact, and re-exports
// the pure-Zig core for downstream Zig consumers who link the module directly.
//
// The pure core lives in src/chardetz.zig (no FFI, no libc) so the unit-test
// build can import it without dragging in the C ABI / allocator dependencies.

pub const core = @import("chardetz.zig");
pub const ffi = @import("ffi.zig");

// Force the FFI module's `@export` comptime blocks to be evaluated so the C ABI
// symbols are emitted into the library/wasm artifact.
comptime {
    _ = ffi;
}
