// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
// Ported from uchardet (https://github.com/pmarreck/uchardetz @ abacfc1f),
// derived from Mozilla universalchardet. Tri-licensed MPL 1.1 / GPL 2.0-or-later
// / LGPL 2.1-or-later. See COPYING.
//
// Direct port of nsUniversalDetector (.cpp/.h) — the detection dispatcher.
// HandleData performs (in order): a one-time BOM probe, the uchardetz fork's
// BOM-less UTF-16 NUL heuristic, per-byte input classification (pure-ASCII /
// escape / high-byte), then feeds high-byte data to the installed prober array
// (shortcutting on a confident prober). DataEnd reports the detected charset or
// the argmax-confidence prober above MINIMUM_THRESHOLD.
//
// Pure: no I/O, no clock, no allocation in the detection path. The prober array
// is a fixed slice of polymorphic `Prober` handles so later chunks (multibyte
// group, SBCS group, Latin1, escape, Hebrew) plug in without touching the
// dispatcher's control flow — only the array wiring grows.

const std = @import("std");
const prober = @import("prober.zig");
const utf8_prober = @import("probers/utf8.zig");
const sbcs_group_prober = @import("probers/sbcs_group.zig");
const latin1_prober = @import("probers/latin1.zig");

const Prober = prober.Prober;
const ProbingState = prober.ProbingState;

/// Port of nsInputState (nsUniversalDetector.h).
pub const InputState = enum(u32) {
    pure_ascii = 0,
    esc_ascii = 1,
    high_byte = 2,
};

/// The detection dispatcher. Holds its own concrete probers inline (so no heap
/// is required for the current set) plus a slice of polymorphic handles the
/// HandleData/DataEnd loops iterate over.
pub const UniversalDetector = struct {
    input_state: InputState = .pure_ascii,
    nbsp_found: bool = false,
    done: bool = false,
    start: bool = true,
    got_data: bool = false,
    last_char: u8 = 0,
    /// Internal "best detected charset so far" — mirrors nsUniversalDetector's
    /// mDetectedCharset. NOT the externally visible answer: it is set during
    /// HandleData (BOM/heuristic/ASCII) but only becomes the result if DataEnd
    /// Reports it. null until a charset is decided; borrows a static string slice.
    detected_charset: ?[]const u8 = null,
    /// The externally visible verdict — mirrors the C ABI's m_charset, which is
    /// populated ONLY by Report() (called solely from DataEnd). Starts "" and
    /// stays "" for empty/undetermined input, exactly like uchardet's
    /// get_charset (which returns m_charset ?: ""). Keeping this separate from
    /// detected_charset is load-bearing: e.g. empty input sets detected_charset
    /// to "ASCII" internally but DataEnd returns early (no data) so nothing is
    /// reported → the verdict is "".
    reported: []const u8 = "",

    // ── Concrete probers owned by the detector ──────────────────────────────
    // Later chunks add fields here (mbcs group, sbcs group, latin1, escape) and
    // extend `buildProberSlice()` to include their `asProber()` handles.
    utf8: utf8_prober.UTF8Prober,
    /// The single-byte charset group (35 sub-probers incl. Hebrew). uchardet's
    /// dispatcher slot [1]. Allocates internally for the buffer filters.
    sbcs_group: sbcs_group_prober.SBCSGroupProber,
    /// The Latin-1 / WINDOWS-1252 class-model prober. uchardet's slot [2].
    latin1: latin1_prober.Latin1Prober,
    /// Backing storage for the polymorphic prober array, (re)built on demand
    /// from the concrete prober fields. Built lazily — never in init() — so the
    /// erased `ptr`s always point at THIS struct's fields, never a stale copy
    /// (init() returns by value, which would invalidate pointers captured into
    /// a local). The count is fixed per detector, so the slice is stable across
    /// a single detect() lifetime.
    prober_storage: [MAX_PROBERS]Prober = undefined,

    const MAX_PROBERS = 8;
    /// Number of probers wired for the high-byte path. Grows in later chunks.
    /// uchardet's order is [MBCSGroup, SBCSGroup, Latin1]; the MBCS group lands
    /// in the CJK chunk, so for now slot 0 is the standalone UTF-8 prober,
    /// followed by the SBCS group and Latin1.
    const PROBER_COUNT = 3;

    pub fn init(allocator: std.mem.Allocator) UniversalDetector {
        return UniversalDetector{
            .utf8 = utf8_prober.UTF8Prober.init(),
            .sbcs_group = sbcs_group_prober.SBCSGroupProber.init(allocator),
            .latin1 = latin1_prober.Latin1Prober.init(allocator),
        };
    }

    /// (Re)build the polymorphic prober array from the concrete fields against
    /// the CURRENT address of `self`, then return it. uchardet's order is
    /// [MBCSGroup, SBCSGroup, Latin1]; the MBCS group is not ported yet, so
    /// slot 0 is the standalone UTF-8 prober, then the SBCS group + Latin1.
    /// Cheap (a few pointer writes); called per dispatch.
    fn proberSlice(self: *UniversalDetector) []Prober {
        self.prober_storage[0] = self.utf8.asProber();
        self.prober_storage[1] = self.sbcs_group.asProber();
        self.prober_storage[2] = self.latin1.asProber();
        return self.prober_storage[0..PROBER_COUNT];
    }

    pub fn reset(self: *UniversalDetector) void {
        self.input_state = .pure_ascii;
        self.nbsp_found = false;
        self.done = false;
        self.start = true;
        self.got_data = false;
        self.last_char = 0;
        self.detected_charset = null;
        self.reported = "";
        for (self.proberSlice()) |p| p.reset();
    }

    /// nsUniversalDetector::HandleData.
    pub fn handleData(self: *UniversalDetector, buf: []const u8) void {
        if (self.done) return;

        if (buf.len > 0) self.got_data = true;

        // ── If the data starts with a BOM, we know it is UTF. ──
        if (self.start) {
            self.start = false;
            if (buf.len > 2) {
                switch (buf[0]) {
                    0xEF => {
                        // EF BB BF: UTF-8 encoded BOM.
                        if (buf[1] == 0xBB and buf[2] == 0xBF)
                            self.detected_charset = "UTF-8";
                    },
                    0xFE => {
                        // FE FF: UTF-16, big endian BOM.
                        if (buf[1] == 0xFF)
                            self.detected_charset = "UTF-16";
                    },
                    0xFF => {
                        if (buf[1] == 0xFE) {
                            if (buf.len > 3 and buf[2] == 0x00 and buf[3] == 0x00) {
                                // FF FE 00 00: UTF-32 (LE).
                                self.detected_charset = "UTF-32";
                            } else {
                                // FF FE: UTF-16, little endian BOM.
                                self.detected_charset = "UTF-16";
                            }
                        }
                    },
                    0x00 => {
                        // 00 00 FE FF: UTF-32 (BE).
                        if (buf.len > 3 and buf[1] == 0x00 and buf[2] == 0xFE and buf[3] == 0xFF)
                            self.detected_charset = "UTF-32";
                    },
                    else => {},
                }

                if (self.detected_charset) |_| {
                    self.done = true;
                    return;
                }

                // ── BOM-less UTF-16 heuristic (uchardetz fork addition) ──
                // Count NULs at even vs odd byte positions over the first
                // min(len, 256) bytes (rounded down to even). A dominant NUL
                // position (≥20%) with the other position nearly NUL-free
                // (<5%) indicates BMP UTF-16: even-NUL → BE, odd-NUL → LE.
                if (buf.len >= 8) {
                    var check_len: usize = if (buf.len < 256) buf.len else 256;
                    check_len &= ~@as(usize, 1); // round down to even
                    var even_nulls: usize = 0;
                    var odd_nulls: usize = 0;
                    var j: usize = 0;
                    while (j < check_len) : (j += 2) {
                        if (buf[j] == 0x00) even_nulls += 1;
                        if (buf[j + 1] == 0x00) odd_nulls += 1;
                    }
                    const half_len = check_len / 2;
                    if (even_nulls * 5 >= half_len and odd_nulls * 20 < half_len) {
                        // NULs at even positions → high byte is 0 → big-endian.
                        self.detected_charset = "UTF-16BE";
                        self.done = true;
                        return;
                    }
                    if (odd_nulls * 5 >= half_len and even_nulls * 20 < half_len) {
                        // NULs at odd positions → little-endian.
                        self.detected_charset = "UTF-16LE";
                        self.done = true;
                        return;
                    }
                }
            }
        }

        // ── Per-byte input classification ──
        for (buf) |c| {
            // High-byte iff the top bit is set AND it is not 0xA0 (NBSP), which
            // is a common near-ASCII exception we do not treat as high-byte.
            if ((c & 0x80) != 0 and c != 0xA0) {
                if (self.input_state != .high_byte) {
                    self.input_state = .high_byte;
                    // (uchardet would kill an active escape prober and lazily
                    // construct the high-byte probers here; this chunk's probers
                    // are preconstructed in init(), so nothing to allocate.)
                }
            } else {
                // Pure ASCII or NBSP so far.
                if (c == 0xA0) {
                    self.nbsp_found = true;
                } else if (self.input_state == .pure_ascii and
                    (c == 0o33 or (c == '{' and self.last_char == '~')))
                {
                    // An escape character (0x1B) or HZ "~{".
                    self.input_state = .esc_ascii;
                }
                self.last_char = c;
            }
        }

        // ── Dispatch on input state ──
        switch (self.input_state) {
            .esc_ascii => {
                // Escape prober lands in a later chunk. Until then, mirror the
                // upstream fallbacks for the escape branch: NBSP → ISO-8859-1,
                // otherwise still ASCII until proven otherwise.
                if (self.nbsp_found) {
                    self.detected_charset = "ISO-8859-1";
                } else {
                    self.detected_charset = "ASCII";
                }
            },
            .high_byte => {
                for (self.proberSlice()) |p| {
                    const st = p.handleData(buf);
                    if (st == .found_it) {
                        self.done = true;
                        self.detected_charset = p.charsetName();
                        return;
                    }
                }
            },
            .pure_ascii => {
                if (self.nbsp_found) {
                    self.detected_charset = "ISO-8859-1";
                } else {
                    self.detected_charset = "ASCII";
                }
            },
        }
    }

    /// nsUniversalDetector::DataEnd.
    pub fn dataEnd(self: *UniversalDetector) void {
        if (!self.got_data) {
            // No data yet — return immediately (caller may DataEnd prematurely).
            return;
        }

        if (self.detected_charset) |cs| {
            self.done = true;
            self.report(cs);
            return;
        }

        switch (self.input_state) {
            .high_byte => {
                var max_conf: f32 = 0.0;
                var max_prober: usize = 0;
                for (self.proberSlice(), 0..) |p, i| {
                    const conf = p.getConfidence();
                    if (conf > max_conf) {
                        max_conf = conf;
                        max_prober = i;
                    }
                }
                // Do not report unless confident — a low max is a negative answer.
                if (max_conf > prober.MINIMUM_THRESHOLD) {
                    self.report(self.proberSlice()[max_prober].charsetName());
                }
            },
            .esc_ascii => {},
            .pure_ascii => {},
        }
    }

    /// nsUniversalDetector::Report (the C ABI override): set the externally
    /// visible verdict. Internal-only; called from dataEnd.
    fn report(self: *UniversalDetector, charset: []const u8) void {
        self.reported = charset;
    }

    /// The reported charset, or "" if the detector reported nothing — mirrors
    /// the C ABI's get_charset (returns m_charset ?: "").
    pub fn getCharset(self: *UniversalDetector) []const u8 {
        return self.reported;
    }
};

/// One-shot convenience: construct a detector, feed all bytes, finalize, and
/// return the charset verdict. Mirrors uchardet's new → handle_data → data_end
/// → get_charset usage. The returned charset name is a static string slice; the
/// allocator is used internally by the SBCS group / Latin1 probers' buffer
/// filters (freed before return), so nothing the caller sees is allocated.
pub fn detect(allocator: std.mem.Allocator, bytes: []const u8) []const u8 {
    var det = UniversalDetector.init(allocator);
    det.handleData(bytes);
    det.dataEnd();
    return det.getCharset();
}
