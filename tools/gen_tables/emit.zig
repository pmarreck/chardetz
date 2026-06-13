//! Shared emission helpers for the table generator: the license/provenance
//! header that every generated table file must carry, plus (added in later
//! phases) the Zig-literal emitters for order maps, matrices, u32/u16 arrays,
//! and struct literals.
//!
//! This file is generator code (new, non-derivative), but the headers it emits
//! reproduce the upstream tri-license onto the generated derivative tables.

const std = @import("std");

/// License + provenance header prepended to every generated table file. The
/// generated tables are a derivative of uchardet's copyrighted data, so they
/// carry the upstream tri-license verbatim.
pub const LICENSE_HEADER =
    \\// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
    \\//
    \\// This file is part of chardetz, a C++→Zig translation of uchardet
    \\// (https://github.com/pmarreck/uchardetz), itself derived from Mozilla's
    \\// universalchardet. The Original Code is Mozilla Universal charset detector
    \\// code; Initial Developer: Netscape Communications Corporation (© 2001).
    \\// Contributor: BYVoid <byvoid.kcp@gmail.com>.
    \\//
    \\// Tri-licensed MPL 1.1 / GPL 2.0-or-later / LGPL 2.1-or-later. See COPYING.
    \\
;

/// Provenance line marking a file as machine-generated from the pinned source.
/// Callers append the specific upstream filename.
pub const GENERATED_PREFIX = "// @generated from ";
pub const PINNED_COMMIT = "abacfc1fc86ef7618547d7dce7cc7501e756fa31";

/// Write the standard header (license + a `@generated from <src> @ <commit>`
/// line + "do not edit") to `w` for a file generated from `upstream_src`.
pub fn writeHeader(w: anytype, upstream_src: []const u8) !void {
    try w.writeAll(LICENSE_HEADER);
    try w.print("//\n// {s}{s} @ {s} — do not edit (regenerate via `zig build gen-tables`).\n\n", .{
        GENERATED_PREFIX, upstream_src, PINNED_COMMIT,
    });
}
