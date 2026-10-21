//! Table-level differential check. Each upstream table file is compiled by
//! the C++ compiler inside a generated shim, and every declaration in
//! src/tables must match the compiler's own bytes: arrays byte-for-byte,
//! constants exactly (floats bit-for-bit), and model records field by field.
const std = @import("std");
const all = @import("chardetz").tables;
const types = @import("chardetz").table_types;

const Ref = extern struct {
    name: [*:0]const u8,
    kind: c_int,
    ptr: ?*const anyopaque,
    size: usize,
    ival: c_longlong,
    fval: f64,
};
const kind_int = 0;
const kind_float = 1;
const kind_array = 2;
const kind_sequence_model = 3;
const kind_sm_model = 4;

/// C layout of uchardet's SequenceModel (nsSBCharSetProber.h).
const CSequenceModel = extern struct {
    charToOrderMap: [*]const u8,
    precedenceMatrix: [*]const u8,
    freqCharCount: c_int,
    mTypicalPositiveRatio: f32,
    keepEnglishLetter: bool,
    charsetName: [*:0]const u8,
};

/// C layout of uchardet's nsPkgInt (nsPkgInt.h); its enum fields are int-sized.
const CPkgInt = extern struct {
    idxsft: c_int,
    sftmsk: c_int,
    bitsft: c_int,
    unitmsk: c_int,
    data: [*]const u32,
};

/// C layout of uchardet's SMModel (nsCodingStateMachine.h).
const CSMModel = extern struct {
    classTable: CPkgInt,
    classFactor: u32,
    stateTable: CPkgInt,
    charLenTable: [*]const u32,
    name: [*:0]const u8,
};

fn findRef(refs: []const Ref, name: []const u8) !Ref {
    for (refs) |r| if (std.mem.eql(u8, std.mem.span(r.name), name)) return r;
    std.debug.print("no C++ counterpart for {s}\n", .{name});
    return error.MissingCounterpart;
}

fn expectKind(r: Ref, kind: c_int) !void {
    if (r.kind != kind) {
        std.debug.print("{s}: C++ kind {d}, expected {d}\n", .{ r.name, r.kind, kind });
        return error.KindMismatch;
    }
}

fn expectBytes(what: []const u8, zig_bytes: []const u8, c_ptr: [*]const u8) !void {
    if (!std.mem.eql(u8, zig_bytes, c_ptr[0..zig_bytes.len])) {
        std.debug.print("{s}: bytes differ from C++\n", .{what});
        return error.BytesDiffer;
    }
}

fn expectPkgInt(z: types.PkgInt, c: CPkgInt) !void {
    try std.testing.expectEqual(@as(c_int, z.idxsft), c.idxsft);
    try std.testing.expectEqual(@as(c_int, @intCast(z.sftmsk)), c.sftmsk);
    try std.testing.expectEqual(@as(c_int, z.bitsft), c.bitsft);
    try std.testing.expectEqual(@as(c_int, @intCast(z.unitmsk)), c.unitmsk);
    try expectBytes("packed table", std.mem.sliceAsBytes(z.data), @ptrCast(c.data));
}

fn checkDecl(comptime name: []const u8, value: anytype, refs: []const Ref) !void {
    const T = @TypeOf(value);
    const r = try findRef(refs, name);
    if (T == comptime_int) {
        try expectKind(r, kind_int);
        try std.testing.expectEqual(@as(c_longlong, value), r.ival);
    } else if (T == f32 or T == f64) {
        try expectKind(r, kind_float);
        try std.testing.expectEqual(@as(u64, @bitCast(@as(f64, value))), @as(u64, @bitCast(r.fval)));
    } else if (T == types.SequenceModel) {
        try expectKind(r, kind_sequence_model);
        try std.testing.expectEqual(@sizeOf(CSequenceModel), r.size);
        const c: *const CSequenceModel = @ptrCast(@alignCast(r.ptr.?));
        try expectBytes(name ++ ".charToOrderMap", value.charToOrderMap, c.charToOrderMap);
        try expectBytes(name ++ ".precedenceMatrix", value.precedenceMatrix, c.precedenceMatrix);
        try std.testing.expectEqual(@as(c_int, @intCast(value.freqCharCount)), c.freqCharCount);
        try std.testing.expectEqual(@as(u32, @bitCast(value.mTypicalPositiveRatio)), @as(u32, @bitCast(c.mTypicalPositiveRatio)));
        try std.testing.expectEqual(value.keepEnglishLetter, c.keepEnglishLetter);
        try std.testing.expectEqualStrings(value.charsetName, std.mem.span(c.charsetName));
    } else if (T == types.SMModel) {
        try expectKind(r, kind_sm_model);
        try std.testing.expectEqual(@sizeOf(CSMModel), r.size);
        const c: *const CSMModel = @ptrCast(@alignCast(r.ptr.?));
        try expectPkgInt(value.classTable, c.classTable);
        try std.testing.expectEqual(value.classFactor, c.classFactor);
        try expectPkgInt(value.stateTable, c.stateTable);
        try expectBytes(name ++ ".charLenTable", std.mem.sliceAsBytes(value.charLenTable), @ptrCast(c.charLenTable));
        try std.testing.expectEqualStrings(value.name, std.mem.span(c.name));
    } else if (@typeInfo(T) == .array) {
        try expectKind(r, kind_array);
        try std.testing.expectEqual(@sizeOf(T), r.size);
        try expectBytes(name, std.mem.asBytes(&value), @ptrCast(r.ptr.?));
    } else {
        @compileError("table differential cannot compare " ++ name ++ " of type " ++ @typeName(T));
    }
}

test "every generated table matches the C++ compiler's evaluation of upstream" {
    var modules: usize = 0;
    inline for (@typeInfo(all).@"struct".decls) |m| {
        const module = @field(all, m.name);
        const shim = @extern(*const fn (*usize) callconv(.c) [*]const Ref, .{ .name = "chardetz_shim_" ++ m.name });
        var count: usize = 0;
        const refs = shim(&count)[0..count];
        var compared: usize = 0;
        inline for (@typeInfo(module).@"struct".decls) |d| {
            const value = @field(module, d.name);
            if (@TypeOf(value) != type) {
                checkDecl(d.name, value, refs) catch |e| {
                    std.debug.print("in {s}.{s}\n", .{ m.name, d.name });
                    return e;
                };
                compared += 1;
            }
        }
        // Every C++ declaration the shim exports must have been compared.
        try std.testing.expectEqual(refs.len, compared);
        modules += 1;
    }
    // One module per manifest table entry; fewer would mean tables went unchecked.
    try std.testing.expectEqual(@import("table_options").table_modules, modules);
}
