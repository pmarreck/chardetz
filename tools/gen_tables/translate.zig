//! Mechanical C++ -> Zig translator for uchardet's static data tables.
//!
//! Pure core (no I/O): lexes a C/C++ source file, evaluates constant
//! initializer expressions (object-like macros, enum constants, casts and the
//! PCK4BITS/PCK8BITS/PCK16BITS packing macros) and emits equivalent Zig
//! declarations. Unknown identifiers, unknown types and out-of-range values are
//! errors: the translator refuses to guess.
const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Error = error{
    UnknownIdentifier,
    UnknownType,
    ValueOutOfRange,
    TooManyInitializers,
    MissingLicenseBlock,
    Syntax,
    UnsupportedString,
    MacroRecursion,
} || Allocator.Error;

const Tok = struct {
    kind: Kind,
    text: []const u8,

    const Kind = enum { ident, number, string, punct };

    fn is(self: Tok, kind: Kind, text: []const u8) bool {
        return self.kind == kind and std.mem.eql(u8, self.text, text);
    }

    fn isPunct(self: Tok, text: []const u8) bool {
        return self.is(.punct, text);
    }
};

/// Object-like macros and enum constants gathered from upstream headers.
/// Owns copies of everything it references.
pub const Symbols = struct {
    arena_state: std.heap.ArenaAllocator.State = .{},
    map: std.StringHashMapUnmanaged([]const Tok) = .empty,

    pub const empty: Symbols = .{};

    pub fn deinit(self: *Symbols, gpa: Allocator) void {
        self.arena_state.promote(gpa).deinit();
        self.* = undefined;
    }

    fn get(self: *const Symbols, name: []const u8) ?[]const Tok {
        return self.map.get(name);
    }
};

pub const Options = struct {
    /// Upstream-relative path recorded in the @generated provenance line.
    source_path: []const u8,
    /// Upstream revision recorded in the @generated provenance line.
    source_rev: []const u8,
};

const Define = struct { name: []const u8, body: []const Tok, token_pos: usize };

const Lexed = struct {
    toks: []Tok,
    defines: []Define,
    license: ?[]const u8,
};

/// Tokenizes C/C++ source, removing comments and preprocessor directives.
/// Object-like `#define`s are recorded with the token position they precede;
/// the first comment containing "BEGIN LICENSE BLOCK" is captured verbatim.
fn lex(arena: Allocator, src: []const u8) Error!Lexed {
    var toks: std.ArrayList(Tok) = .empty;
    var defines: std.ArrayList(Define) = .empty;
    var license: ?[]const u8 = null;
    var i: usize = 0;
    var at_line_start = true;
    while (i < src.len) {
        const c = src[i];
        if (c == '\n') {
            at_line_start = true;
            i += 1;
            continue;
        }
        if (c == ' ' or c == '\t' or c == '\r' or c == '\x0c') {
            i += 1;
            continue;
        }
        if (c == '#' and at_line_start) {
            var end = i;
            while (end < src.len and src[end] != '\n') : (end += 1) {
                if (src[end] == '\\' and end + 1 < src.len and src[end + 1] == '\n') end += 1;
            }
            const directive = try lex(arena, src[i + 1 .. end]);
            if (directive.toks.len >= 2 and directive.toks[0].is(.ident, "define")) {
                const name = directive.toks[1];
                const after_name = @intFromPtr(name.text.ptr) + name.text.len;
                const function_like = after_name < @intFromPtr(src.ptr) + end and
                    src[after_name - @intFromPtr(src.ptr)] == '(';
                if (!function_like) try defines.append(arena, .{
                    .name = name.text,
                    .body = directive.toks[2..],
                    .token_pos = toks.items.len,
                });
            }
            i = end;
            continue;
        }
        at_line_start = false;
        if (c == '/' and i + 1 < src.len and src[i + 1] == '/') {
            while (i < src.len and src[i] != '\n') i += 1;
            continue;
        }
        if (c == '/' and i + 1 < src.len and src[i + 1] == '*') {
            const close = std.mem.indexOfPos(u8, src, i + 2, "*/") orelse return error.Syntax;
            const comment = src[i .. close + 2];
            if (license == null and std.mem.indexOf(u8, comment, "BEGIN LICENSE BLOCK") != null) license = comment;
            i = close + 2;
            continue;
        }
        const start = i;
        if (std.ascii.isAlphabetic(c) or c == '_') {
            while (i < src.len and (std.ascii.isAlphanumeric(src[i]) or src[i] == '_')) i += 1;
            try toks.append(arena, .{ .kind = .ident, .text = src[start..i] });
        } else if (std.ascii.isDigit(c) or (c == '.' and i + 1 < src.len and std.ascii.isDigit(src[i + 1]))) {
            const hex = c == '0' and i + 1 < src.len and (src[i + 1] == 'x' or src[i + 1] == 'X');
            while (i < src.len) : (i += 1) {
                const d = src[i];
                if (std.ascii.isAlphanumeric(d) or d == '.' or d == '_') continue;
                if (!hex and (d == '+' or d == '-') and (src[i - 1] == 'e' or src[i - 1] == 'E')) continue;
                break;
            }
            try toks.append(arena, .{ .kind = .number, .text = src[start..i] });
        } else if (c == '"') {
            i += 1;
            while (i < src.len and src[i] != '"') : (i += 1) {
                if (src[i] == '\\') i += 1;
            }
            if (i >= src.len) return error.Syntax;
            i += 1;
            try toks.append(arena, .{ .kind = .string, .text = src[start..i] });
        } else {
            const two = if (i + 1 < src.len) src[i .. i + 2] else "";
            const len: usize = if (std.mem.eql(u8, two, "<<") or std.mem.eql(u8, two, ">>") or std.mem.eql(u8, two, "::")) 2 else 1;
            i += len;
            try toks.append(arena, .{ .kind = .punct, .text = src[start..i] });
        }
    }
    return .{ .toks = toks.items, .defines = defines.items, .license = license };
}

/// Records upstream header `#define`s and `enum` constants into `symbols` so
/// later translations can resolve names like ILL, PR_TRUE or eItsMe.
pub fn collectHeaderSymbols(gpa: Allocator, symbols: *Symbols, header: []const u8) Error!void {
    var arena_impl = symbols.arena_state.promote(gpa);
    defer symbols.arena_state = arena_impl.state;
    const arena = arena_impl.allocator();

    const owned = try arena.dupe(u8, header);
    const lexed = try lex(arena, owned);
    for (lexed.defines) |d| try symbols.map.put(arena, d.name, d.body);

    const toks = lexed.toks;
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        if (!toks[i].is(.ident, "enum")) continue;
        var j = i + 1;
        if (j < toks.len and toks[j].kind == .ident) j += 1;
        if (j >= toks.len or !toks[j].isPunct("{")) continue;
        j += 1;
        var next_value: i64 = 0;
        while (j < toks.len and !toks[j].isPunct("}")) {
            if (toks[j].kind != .ident) return error.Syntax;
            const name = toks[j].text;
            j += 1;
            if (j < toks.len and toks[j].isPunct("=")) {
                const expr_start = j + 1;
                j = expr_start;
                while (j < toks.len and !toks[j].isPunct(",") and !toks[j].isPunct("}")) j += 1;
                var ev: Evaluator = .{ .symbols = symbols, .locals = null, .toks = toks[expr_start..j] };
                next_value = try (try ev.evalAll()).asInt();
            }
            const text = try std.fmt.allocPrint(arena, "{d}", .{next_value});
            const body = try arena.alloc(Tok, 1);
            body[0] = .{ .kind = .number, .text = text };
            try symbols.map.put(arena, name, body);
            next_value += 1;
            if (j < toks.len and toks[j].isPunct(",")) j += 1;
        }
        i = j;
    }
}

const Float = struct {
    value: f64,
    kind: enum { double, single, cast_f32 },
};

const Pck = struct { bits: u8, args: []const i64 };

const Value = union(enum) {
    int: i64,
    float: Float,
    boolean: bool,
    pck: Pck,

    fn asInt(self: Value) Error!i64 {
        return switch (self) {
            .int => |v| v,
            else => error.Syntax,
        };
    }
};

const Locals = std.StringHashMapUnmanaged([]const Tok);

/// Recursive-descent evaluator for C constant expressions over a token slice.
/// Precedence follows C: `|` < shifts < additive < multiplicative < unary.
const Evaluator = struct {
    symbols: *const Symbols,
    locals: ?*const Locals,
    toks: []const Tok,
    pos: usize = 0,
    depth: u8 = 0,
    arena: ?Allocator = null,

    const max_depth = 64;

    fn evalAll(self: *Evaluator) Error!Value {
        const v = try self.parseOr();
        if (self.pos != self.toks.len) return error.Syntax;
        return v;
    }

    fn peek(self: *Evaluator) ?Tok {
        return if (self.pos < self.toks.len) self.toks[self.pos] else null;
    }

    fn expectPunct(self: *Evaluator, text: []const u8) Error!void {
        const t = self.peek() orelse return error.Syntax;
        if (!t.isPunct(text)) return error.Syntax;
        self.pos += 1;
    }

    fn binary(self: *Evaluator, comptime ops: []const []const u8, comptime next: fn (*Evaluator) Error!Value) Error!Value {
        var lhs = try next(self);
        outer: while (self.peek()) |t| {
            inline for (ops) |op| {
                if (t.isPunct(op)) {
                    self.pos += 1;
                    const rhs = try next(self);
                    lhs = try applyBinary(op, lhs, rhs);
                    continue :outer;
                }
            }
            break;
        }
        return lhs;
    }

    fn parseOr(self: *Evaluator) Error!Value {
        return self.binary(&.{"|"}, parseShift);
    }
    fn parseShift(self: *Evaluator) Error!Value {
        return self.binary(&.{ "<<", ">>" }, parseAdd);
    }
    fn parseAdd(self: *Evaluator) Error!Value {
        return self.binary(&.{ "+", "-" }, parseMul);
    }
    fn parseMul(self: *Evaluator) Error!Value {
        return self.binary(&.{ "*", "/", "%" }, parseUnary);
    }

    fn parseUnary(self: *Evaluator) Error!Value {
        const t = self.peek() orelse return error.Syntax;
        if (t.isPunct("-")) {
            self.pos += 1;
            return switch (try self.parseUnary()) {
                .int => |v| .{ .int = -v },
                .float => |f| .{ .float = .{ .value = -f.value, .kind = f.kind } },
                else => error.Syntax,
            };
        }
        if (t.isPunct("+")) {
            self.pos += 1;
            return self.parseUnary();
        }
        return self.parsePrimary();
    }

    fn parsePrimary(self: *Evaluator) Error!Value {
        const t = self.peek() orelse return error.Syntax;
        switch (t.kind) {
            .number => {
                self.pos += 1;
                return parseNumber(t.text);
            },
            .string => return error.Syntax,
            .punct => {
                if (!t.isPunct("(")) return error.Syntax;
                if (self.castType()) |cast| {
                    const inner = try self.parseUnary();
                    return applyCast(cast, inner);
                }
                self.pos += 1;
                const v = try self.parseOr();
                try self.expectPunct(")");
                return v;
            },
            .ident => {
                self.pos += 1;
                if (std.mem.eql(u8, t.text, "true")) return .{ .boolean = true };
                if (std.mem.eql(u8, t.text, "false")) return .{ .boolean = false };
                if (self.peek()) |n| if (n.isPunct("(")) return self.parseCall(t.text);
                const body = (if (self.locals) |l| l.get(t.text) else null) orelse
                    self.symbols.get(t.text) orelse return error.UnknownIdentifier;
                if (self.depth >= max_depth) return error.MacroRecursion;
                var sub: Evaluator = .{
                    .symbols = self.symbols,
                    .locals = self.locals,
                    .toks = body,
                    .depth = self.depth + 1,
                    .arena = self.arena,
                };
                return sub.evalAll();
            },
        }
    }

    const CastKind = enum { float, int };

    /// Recognizes `( type-name... )` at the cursor and consumes it.
    fn castType(self: *Evaluator) ?CastKind {
        var j = self.pos + 1;
        var kind: ?CastKind = null;
        while (j < self.toks.len and self.toks[j].kind == .ident) : (j += 1) {
            const name = self.toks[j].text;
            if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "double")) {
                kind = .float;
            } else if (isIntTypeWord(name)) {
                if (kind == null) kind = .int;
            } else return null;
        }
        if (kind == null or j >= self.toks.len or !self.toks[j].isPunct(")")) return null;
        self.pos = j + 1;
        return kind;
    }

    fn parseCall(self: *Evaluator, name: []const u8) Error!Value {
        const bits: u8 = if (std.mem.eql(u8, name, "PCK4BITS"))
            4
        else if (std.mem.eql(u8, name, "PCK8BITS"))
            8
        else if (std.mem.eql(u8, name, "PCK16BITS"))
            16
        else
            return error.UnknownIdentifier;
        const arity: usize = 32 / bits;
        const arena = self.arena orelse return error.Syntax;
        const args = try arena.alloc(i64, arity);
        try self.expectPunct("(");
        for (args, 0..) |*arg, k| {
            if (k > 0) try self.expectPunct(",");
            arg.* = try (try self.parseOr()).asInt();
            if (arg.* < 0 or arg.* >= (@as(i64, 1) << @intCast(bits))) return error.ValueOutOfRange;
        }
        try self.expectPunct(")");
        return .{ .pck = .{ .bits = bits, .args = args } };
    }
};

fn isIntTypeWord(name: []const u8) bool {
    const words = [_][]const u8{ "int", "unsigned", "signed", "char", "short", "long", "PRUint32", "PRInt32", "PRUint16", "PRInt16", "PRUint8", "PRInt8" };
    for (words) |w| if (std.mem.eql(u8, name, w)) return true;
    return false;
}

fn applyCast(kind: Evaluator.CastKind, v: Value) Error!Value {
    return switch (kind) {
        .float => switch (v) {
            .int => |i| .{ .float = .{ .value = @floatFromInt(i), .kind = .cast_f32 } },
            .float => |f| .{ .float = .{ .value = f.value, .kind = .cast_f32 } },
            else => error.Syntax,
        },
        .int => switch (v) {
            .int => v,
            else => error.Syntax,
        },
    };
}

fn applyBinary(comptime op: []const u8, lhs: Value, rhs: Value) Error!Value {
    const a = try lhs.asInt();
    const b = try rhs.asInt();
    const r: i64 = if (comptime std.mem.eql(u8, op, "|"))
        a | b
    else if (comptime std.mem.eql(u8, op, "<<"))
        std.math.shl(i64, a, b)
    else if (comptime std.mem.eql(u8, op, ">>"))
        std.math.shr(i64, a, b)
    else if (comptime std.mem.eql(u8, op, "+"))
        a + b
    else if (comptime std.mem.eql(u8, op, "-"))
        a - b
    else if (comptime std.mem.eql(u8, op, "*"))
        a * b
    else if (comptime std.mem.eql(u8, op, "/"))
        (if (b == 0) return error.Syntax else @divTrunc(a, b))
    else if (comptime std.mem.eql(u8, op, "%"))
        (if (b == 0) return error.Syntax else @rem(a, b))
    else
        @compileError("unsupported operator");
    return .{ .int = r };
}

/// Parses a C numeric literal: decimal, octal (leading 0), hex, with integer
/// suffixes (u/U/l/L) or a float literal with optional f/F suffix.
fn parseNumber(text: []const u8) Error!Value {
    const is_hex = text.len > 1 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X');
    const is_float = !is_hex and (std.mem.indexOfAny(u8, text, ".eE") != null);
    if (is_float) {
        var body = text;
        var kind: @FieldType(Float, "kind") = .double;
        if (body[body.len - 1] == 'f' or body[body.len - 1] == 'F') {
            body = body[0 .. body.len - 1];
            kind = .single;
        }
        const v = std.fmt.parseFloat(f64, body) catch return error.Syntax;
        return .{ .float = .{ .value = v, .kind = kind } };
    }
    var end = text.len;
    while (end > 0 and std.mem.indexOfScalar(u8, "uUlL", text[end - 1]) != null) end -= 1;
    const digits = text[0..end];
    const parsed = if (is_hex)
        std.fmt.parseInt(i64, digits[2..], 16)
    else if (digits.len > 1 and digits[0] == '0')
        std.fmt.parseInt(i64, digits[1..], 8)
    else
        std.fmt.parseInt(i64, digits, 10);
    return .{ .int = parsed catch return error.Syntax };
}

const Item = union(enum) {
    expr: []const Tok,
    list: []const Item,
};

const ElemType = enum {
    u8,
    i16,
    u32,

    fn zigName(self: ElemType) []const u8 {
        return @tagName(self);
    }

    fn inRange(self: ElemType, v: i64) bool {
        return switch (self) {
            .u8 => v >= 0 and v <= std.math.maxInt(u8),
            .i16 => v >= std.math.minInt(i16) and v <= std.math.maxInt(i16),
            .u32 => v >= 0 and v <= std.math.maxInt(u32),
        };
    }
};

const StructType = enum { SequenceModel, SMModel };

const DeclType = union(enum) {
    array: ElemType,
    structure: StructType,
};

fn classifyType(words: []const []const u8, arena: Allocator) Error!DeclType {
    const joined = try std.mem.join(arena, " ", words);
    const map = [_]struct { []const u8, DeclType }{
        .{ "unsigned char", .{ .array = .u8 } },
        .{ "PRUint8", .{ .array = .u8 } },
        .{ "PRInt16", .{ .array = .i16 } },
        .{ "PRUint32", .{ .array = .u32 } },
        .{ "SequenceModel", .{ .structure = .SequenceModel } },
        .{ "SMModel", .{ .structure = .SMModel } },
    };
    for (map) |entry| if (std.mem.eql(u8, entry[0], joined)) return entry[1];
    return error.UnknownType;
}

const Translator = struct {
    arena: Allocator,
    symbols: *const Symbols,
    locals: Locals = .empty,
    out: std.ArrayList(u8) = .empty,
    emitted_any: bool = false,
    emitted: std.ArrayList(Emitted) = .empty,
    last_was_block: bool = false,

    fn evaluator(self: *Translator, toks: []const Tok) Evaluator {
        return .{ .symbols = self.symbols, .locals = &self.locals, .toks = toks, .arena = self.arena };
    }

    fn eval(self: *Translator, toks: []const Tok) Error!Value {
        var ev = self.evaluator(toks);
        return ev.evalAll();
    }

    fn print(self: *Translator, comptime fmt: []const u8, args: anytype) Error!void {
        try self.out.print(self.arena, fmt, args);
    }

    fn beginItem(self: *Translator, block: bool) Error!void {
        if (self.emitted_any and (block or self.last_was_block)) try self.out.append(self.arena, '\n');
        self.emitted_any = true;
        self.last_was_block = block;
    }

    fn emitDefine(self: *Translator, d: Define) Error!void {
        if (d.body.len == 0) return;
        const v = try self.eval(d.body);
        try self.beginItem(false);
        try self.emitted.append(self.arena, .{ .name = d.name, .kind = if (v == .int) .int_const else .float_const });
        switch (v) {
            .int => |i| try self.print("pub const {s} = {d};\n", .{ d.name, i }),
            .float => |f| switch (f.kind) {
                .double => try self.print("pub const {s}: f64 = {d};\n", .{ d.name, f.value }),
                .single => try self.print("pub const {s}: f32 = {d};\n", .{ d.name, f.value }),
                .cast_f32 => try self.print("pub const {s}: f32 = @floatCast(@as(f64, {d}));\n", .{ d.name, f.value }),
            },
            else => return error.Syntax,
        }
    }

    fn emitDecl(self: *Translator, header: []const Tok, init: Item) Error!void {
        var words: std.ArrayList([]const u8) = .empty;
        var dims: std.ArrayList(?[]const Tok) = .empty;
        var end = header.len;
        while (end > 0 and header[end - 1].isPunct("]")) {
            var open = end - 1;
            while (open > 0 and !header[open].isPunct("[")) open -= 1;
            if (!header[open].isPunct("[")) return error.Syntax;
            const inner = header[open + 1 .. end - 1];
            try dims.insert(self.arena, 0, if (inner.len == 0) null else inner);
            end = open;
        }
        if (end == 0 or header[end - 1].kind != .ident) return error.Syntax;
        const name = header[end - 1].text;
        for (header[0 .. end - 1]) |t| {
            if (t.kind != .ident) return error.Syntax;
            if (std.mem.eql(u8, t.text, "static") or std.mem.eql(u8, t.text, "const") or std.mem.eql(u8, t.text, "extern")) continue;
            try words.append(self.arena, t.text);
        }
        const decl_type = try classifyType(words.items, self.arena);
        try self.beginItem(true);
        try self.emitted.append(self.arena, .{ .name = name, .kind = switch (decl_type) {
            .array => .array,
            .structure => |st| switch (st) {
                .SequenceModel => .sequence_model,
                .SMModel => .sm_model,
            },
        } });
        switch (decl_type) {
            .array => |elem| try self.emitArray(name, elem, dims.items, init),
            .structure => |st| {
                if (dims.items.len != 0) return error.Syntax;
                try self.emitStruct(name, st, init);
            },
        }
    }

    fn dimValue(self: *Translator, dim: ?[]const Tok, count: usize) Error!usize {
        const toks = dim orelse return count;
        const n = try (try self.eval(toks)).asInt();
        if (n < 0) return error.Syntax;
        const declared: usize = @intCast(n);
        if (count > declared) return error.TooManyInitializers;
        return declared;
    }

    fn emitArray(self: *Translator, name: []const u8, elem: ElemType, dims: []const ?[]const Tok, init: Item) Error!void {
        const rows = switch (init) {
            .list => |l| l,
            .expr => return error.Syntax,
        };
        switch (dims.len) {
            1 => {
                const n = try self.dimValue(dims[0], rows.len);
                try self.print("pub const {s} = [{d}]{s}{{\n", .{ name, n, elem.zigName() });
                // Cells are rendered first so columns can be aligned the way
                // `zig fmt` aligns multi-row array literals.
                const cells = try self.arena.alloc([]const u8, n);
                var packed_words = false;
                for (cells, 0..) |*cell, k| {
                    const v: Value = if (k < rows.len) switch (rows[k]) {
                        .expr => |e| try self.eval(e),
                        .list => return error.Syntax,
                    } else .{ .int = 0 };
                    switch (v) {
                        .int => |i| {
                            if (!elem.inRange(i)) return error.ValueOutOfRange;
                            cell.* = try std.fmt.allocPrint(self.arena, "{d},", .{i});
                        },
                        .pck => |p| {
                            if (elem != .u32) return error.ValueOutOfRange;
                            packed_words = true;
                            var text: std.ArrayList(u8) = .empty;
                            try text.print(self.arena, "types.pck{d}bits(.{{ ", .{p.bits});
                            for (p.args, 0..) |a, ai| try text.print(self.arena, "{s}{d}", .{ if (ai == 0) "" else ", ", a });
                            try text.appendSlice(self.arena, " }),");
                            cell.* = text.items;
                        },
                        else => return error.Syntax,
                    }
                }
                const per_line: usize = if (packed_words) 1 else values_per_line;
                var widths = [_]usize{0} ** values_per_line;
                for (cells, 0..) |cell, k| widths[k % per_line] = @max(widths[k % per_line], cell.len);
                for (cells, 0..) |cell, k| {
                    const col = k % per_line;
                    const last_in_row = col == per_line - 1 or k == cells.len - 1;
                    if (col == 0) try self.print("    ", .{});
                    try self.print("{s}", .{cell});
                    if (last_in_row) {
                        try self.print("\n", .{});
                    } else {
                        try self.out.appendNTimes(self.arena, ' ', widths[col] - cell.len + 1);
                    }
                }
                try self.print("}};\n", .{});
            },
            2 => {
                const n_rows = try self.dimValue(dims[0], rows.len);
                const inner_dim = dims[1] orelse return error.Syntax;
                const n_cols = try self.dimValue(inner_dim, 0);
                try self.print("pub const {s} = [{d}][{d}]{s}{{\n", .{ name, n_rows, n_cols, elem.zigName() });
                for (0..n_rows) |r| {
                    const cols: []const Item = if (r < rows.len) switch (rows[r]) {
                        .list => |l| l,
                        .expr => return error.Syntax,
                    } else &.{};
                    if (cols.len > n_cols) return error.TooManyInitializers;
                    try self.print("    .{{ ", .{});
                    for (0..n_cols) |k| {
                        const i: i64 = if (k < cols.len) switch (cols[k]) {
                            .expr => |e| try (try self.eval(e)).asInt(),
                            .list => return error.Syntax,
                        } else 0;
                        if (!elem.inRange(i)) return error.ValueOutOfRange;
                        try self.print("{s}{d}", .{ if (k == 0) "" else ", ", i });
                    }
                    try self.print(" }},\n", .{});
                }
                try self.print("}};\n", .{});
            },
            else => return error.Syntax,
        }
    }

    const FieldKind = enum { ref, int, f32, boolean, string, pkgint };
    const Field = struct { name: []const u8, kind: FieldKind };

    const sequence_model_fields = [_]Field{
        .{ .name = "charToOrderMap", .kind = .ref },
        .{ .name = "precedenceMatrix", .kind = .ref },
        .{ .name = "freqCharCount", .kind = .int },
        .{ .name = "mTypicalPositiveRatio", .kind = .f32 },
        .{ .name = "keepEnglishLetter", .kind = .boolean },
        .{ .name = "charsetName", .kind = .string },
    };
    const sm_model_fields = [_]Field{
        .{ .name = "classTable", .kind = .pkgint },
        .{ .name = "classFactor", .kind = .int },
        .{ .name = "stateTable", .kind = .pkgint },
        .{ .name = "charLenTable", .kind = .ref },
        .{ .name = "name", .kind = .string },
    };
    const pkgint_fields = [_][]const u8{ "idxsft", "sftmsk", "bitsft", "unitmsk" };

    fn emitStruct(self: *Translator, name: []const u8, st: StructType, init: Item) Error!void {
        const fields: []const Field = switch (st) {
            .SequenceModel => &sequence_model_fields,
            .SMModel => &sm_model_fields,
        };
        const items = switch (init) {
            .list => |l| l,
            .expr => return error.Syntax,
        };
        if (items.len != fields.len) return error.Syntax;
        try self.print("pub const {s}: types.{s} = .{{\n", .{ name, @tagName(st) });
        for (fields, items) |f, item| {
            try self.print("    .{s} = ", .{f.name});
            try self.emitField(f.kind, item);
            try self.print(",\n", .{});
        }
        try self.print("}};\n", .{});
    }

    fn emitField(self: *Translator, kind: FieldKind, item: Item) Error!void {
        if (kind == .pkgint) {
            const parts = switch (item) {
                .list => |l| l,
                .expr => return error.Syntax,
            };
            if (parts.len != pkgint_fields.len + 1) return error.Syntax;
            try self.print(".{{ ", .{});
            for (pkgint_fields, parts[0..pkgint_fields.len]) |fname, part| {
                const v = try self.eval(try exprOf(part));
                try self.print(".{s} = {d}, ", .{ fname, try v.asInt() });
            }
            try self.print(".data = ", .{});
            try self.emitField(.ref, parts[pkgint_fields.len]);
            try self.print(" }}", .{});
            return;
        }
        const toks = try exprOf(item);
        switch (kind) {
            .ref => {
                const ident = if (toks.len == 2 and toks[0].isPunct("&")) toks[1] else if (toks.len == 1) toks[0] else return error.Syntax;
                if (ident.kind != .ident) return error.Syntax;
                try self.print("&{s}", .{ident.text});
            },
            .string => {
                if (toks.len != 1 or toks[0].kind != .string) return error.Syntax;
                for (toks[0].text[1 .. toks[0].text.len - 1]) |ch| {
                    if (!(std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_')) return error.UnsupportedString;
                }
                try self.print("{s}", .{toks[0].text});
            },
            .int => try self.print("{d}", .{try (try self.eval(toks)).asInt()}),
            .boolean => switch (try self.eval(toks)) {
                .boolean => |b| try self.print("{}", .{b}),
                else => return error.Syntax,
            },
            .f32 => switch (try self.eval(toks)) {
                .float => |f| switch (f.kind) {
                    .single => try self.print("@as(f32, {d})", .{f.value}),
                    .double, .cast_f32 => try self.print("@floatCast(@as(f64, {d}))", .{f.value}),
                },
                .int => |i| try self.print("{d}", .{i}),
                else => return error.Syntax,
            },
            .pkgint => unreachable,
        }
    }
};

const values_per_line = 16;

fn exprOf(item: Item) Error![]const Tok {
    return switch (item) {
        .expr => |e| e,
        .list => error.Syntax,
    };
}

const InitParser = struct {
    arena: Allocator,
    toks: []const Tok,
    pos: usize,

    fn parseItem(self: *InitParser) Error!Item {
        if (self.pos >= self.toks.len) return error.Syntax;
        if (self.toks[self.pos].isPunct("{")) {
            self.pos += 1;
            var items: std.ArrayList(Item) = .empty;
            while (true) {
                if (self.pos >= self.toks.len) return error.Syntax;
                if (self.toks[self.pos].isPunct("}")) {
                    self.pos += 1;
                    break;
                }
                try items.append(self.arena, try self.parseItem());
                if (self.pos >= self.toks.len) return error.Syntax;
                if (self.toks[self.pos].isPunct(",")) {
                    self.pos += 1;
                } else if (!self.toks[self.pos].isPunct("}")) return error.Syntax;
            }
            return .{ .list = items.items };
        }
        const start = self.pos;
        var parens: usize = 0;
        while (self.pos < self.toks.len) : (self.pos += 1) {
            const t = self.toks[self.pos];
            if (t.isPunct("(")) parens += 1;
            if (t.isPunct(")")) {
                if (parens == 0) return error.Syntax;
                parens -= 1;
            }
            if (parens == 0 and (t.isPunct(",") or t.isPunct("}") or t.isPunct(";"))) break;
        }
        if (self.pos == start) return error.Syntax;
        return .{ .expr = self.toks[start..self.pos] };
    }
};

/// Writes the upstream file's own license block as Zig line comments.
fn emitLicense(out: *std.ArrayList(u8), arena: Allocator, block: []const u8) Error!void {
    var lines = std.mem.splitScalar(u8, block, '\n');
    var first = true;
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (first) {
            line = std.mem.trimStart(u8, line["/*".len..], " ");
            first = false;
        } else if (std.mem.startsWith(u8, line, "* ")) {
            line = line[2..];
        } else if (std.mem.eql(u8, line, "*")) {
            line = "";
        }
        if (std.mem.endsWith(u8, line, "*/")) line = std.mem.trimEnd(u8, line[0 .. line.len - 2], " ");
        if (line.len == 0) try out.appendSlice(arena, "//\n") else try out.print(arena, "// {s}\n", .{line});
    }
}

/// Translates one upstream C/C++ table source into a Zig source file.
/// Returned slice is owned by the caller (allocated with `gpa`).
pub fn translate(gpa: Allocator, symbols: *const Symbols, source: []const u8, opts: Options) Error![]u8 {
    var out = try translateDetailed(gpa, symbols, source, opts);
    defer out.deinit(gpa);
    return gpa.dupe(u8, out.zig);
}

/// A top-level declaration the translator emitted, by C name and kind.
pub const Emitted = struct {
    name: []const u8,
    kind: Kind,

    pub const Kind = enum { int_const, float_const, array, sequence_model, sm_model };
};

/// Zig source plus the declarations it contains; owns all of its memory.
pub const Output = struct {
    arena_state: std.heap.ArenaAllocator.State,
    zig: []const u8,
    emitted: []const Emitted,

    pub fn deinit(self: *Output, gpa: Allocator) void {
        self.arena_state.promote(gpa).deinit();
        self.* = undefined;
    }
};

/// Like `translate`, but also lists the emitted declarations so callers can
/// build the C++ comparison shim for the table-level differential check.
pub fn translateDetailed(gpa: Allocator, symbols: *const Symbols, source: []const u8, opts: Options) Error!Output {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    errdefer arena_impl.deinit();
    const arena = arena_impl.allocator();

    const lexed = try lex(arena, source);
    const license = lexed.license orelse return error.MissingLicenseBlock;

    var tr: Translator = .{ .arena = arena, .symbols = symbols };
    for (lexed.defines) |d| try tr.locals.put(arena, d.name, d.body);

    try emitLicense(&tr.out, arena, license);
    try tr.print(
        "//\n// SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later\n" ++
            "// @generated by tools/gen_tables from uchardetz {s} @ {s}; do not edit.\n\n" ++
            "const types = @import(\"types.zig\");\n\n",
        .{ opts.source_path, opts.source_rev },
    );

    const toks = lexed.toks;
    var next_define: usize = 0;
    var depth: usize = 0;
    var parens: usize = 0;
    var stmt_start: usize = 0;
    var i: usize = 0;
    while (i < toks.len) {
        while (next_define < lexed.defines.len and lexed.defines[next_define].token_pos <= i) : (next_define += 1) {
            if (depth == 0) try tr.emitDefine(lexed.defines[next_define]);
        }
        const t = toks[i];
        if (t.isPunct("(")) parens += 1;
        if (t.isPunct(")") and parens > 0) parens -= 1;
        if (t.isPunct("{")) depth += 1;
        if (t.isPunct("}")) {
            if (depth == 0) return error.Syntax;
            depth -= 1;
            if (depth == 0) stmt_start = i + 1;
        }
        if (depth == 0 and parens == 0 and t.isPunct(";")) stmt_start = i + 1;
        if (depth == 0 and parens == 0 and t.isPunct("=")) {
            var ip: InitParser = .{ .arena = arena, .toks = toks, .pos = i + 1 };
            const init = try ip.parseItem();
            if (ip.pos >= toks.len or !toks[ip.pos].isPunct(";")) return error.Syntax;
            try tr.emitDecl(toks[stmt_start..i], init);
            i = ip.pos + 1;
            stmt_start = i;
            continue;
        }
        i += 1;
    }
    while (next_define < lexed.defines.len) : (next_define += 1) try tr.emitDefine(lexed.defines[next_define]);

    return .{ .arena_state = arena_impl.state, .zig = tr.out.items, .emitted = tr.emitted.items };
}

/// Renders the test-only C++ shim for one upstream table file. The shim
/// `#include`s the upstream source verbatim, so the C++ compiler (not this
/// translator) evaluates every table, and exports a reference to each emitted
/// declaration under `chardetz_shim_<stem>`.
pub fn renderShim(gpa: Allocator, stem: []const u8, include_path: []const u8, emitted: []const Emitted) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.print(gpa,
        \\// @generated by tools/gen_tables: test-only shim; do not edit.
        \\#include <stddef.h>
        \\#include "{s}"
        \\
        \\#include "chardetz_shim.h"
        \\
        \\static const chardetz_table_ref refs[] = {{
        \\
    , .{include_path});
    for (emitted) |e| switch (e.kind) {
        .int_const => try out.print(gpa, "    {{ \"{s}\", CHARDETZ_INT, NULL, 0, (long long)({s}), 0.0 }},\n", .{ e.name, e.name }),
        .float_const => try out.print(gpa, "    {{ \"{s}\", CHARDETZ_FLOAT, NULL, 0, 0, (double)({s}) }},\n", .{ e.name, e.name }),
        .array => try out.print(gpa, "    {{ \"{s}\", CHARDETZ_ARRAY, (const void *){s}, sizeof({s}), 0, 0.0 }},\n", .{ e.name, e.name, e.name }),
        .sequence_model => try out.print(gpa, "    {{ \"{s}\", CHARDETZ_SEQUENCE_MODEL, (const void *)&{s}, sizeof({s}), 0, 0.0 }},\n", .{ e.name, e.name, e.name }),
        .sm_model => try out.print(gpa, "    {{ \"{s}\", CHARDETZ_SM_MODEL, (const void *)&{s}, sizeof({s}), 0, 0.0 }},\n", .{ e.name, e.name, e.name }),
    };
    try out.print(gpa,
        \\}};
        \\
        \\extern "C" const chardetz_table_ref *chardetz_shim_{s}(size_t *count) {{
        \\    *count = sizeof(refs) / sizeof(refs[0]);
        \\    return refs;
        \\}}
        \\
    , .{stem});
    return out.toOwnedSlice(gpa);
}
