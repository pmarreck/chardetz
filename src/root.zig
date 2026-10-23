//! chardetz public Zig API: a pure in-memory character-encoding detector
//! translated from uchardet. No I/O happens in this module tree.
const std = @import("std");

/// Streaming detector with uchardet's semantics: `handleData` per chunk,
/// `dataEnd`, then `charset` ("" when nothing was detected).
pub const Detector = @import("detector.zig").Detector;
pub const UpstreamDetector = @import("detector.zig").UpstreamDetector;
pub const Fixes = @import("detector.zig").Fixes;
/// A detector with a chosen set of accuracy fixes (used to attribute differences).
pub const DetectorWith = @import("detector.zig").DetectorWith;

/// Prober verdicts (nsProbingState).
pub const ProbingState = @import("prober.zig").State;

/// The PRINTABLE-BINARY prober, a chardetz extension beyond uchardet.
pub const PBProber = @import("printable_binary_prober.zig").PBProber;
pub const printable_binary_table = @import("printable_binary_table.zig");

/// Generated uchardet data tables.
pub const tables = @import("tables/all.zig");

/// Record types used by the generated tables.
pub const table_types = @import("tables/types.zig");

/// Building blocks exposed for tests and benchmarks; not a stable API.
pub const internal = struct {
    pub const SingleByteProber = @import("sbcs.zig").SingleByteProber;
    pub const CodingStateMachine = @import("prober.zig").CodingStateMachine;
};

/// Detects the encoding of a complete buffer: one `handleData`, then
/// `dataEnd`. Returns uchardet's charset name, or "" when undetermined.
pub fn detect(gpa: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}![:0]const u8 {
    var d: Detector = .init(gpa);
    defer d.deinit();
    try d.handleData(bytes);
    d.dataEnd();
    return d.charset();
}

test {
    _ = @import("prober.zig");
    _ = @import("filter.zig");
    _ = @import("detector.zig");
    _ = @import("printable_binary_prober.zig");
}
