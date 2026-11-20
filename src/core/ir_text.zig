//! `core-ir-v1`: the Core IR of a module as text, for the Lean copy of the IR verifier (`proofs/verify_ir`).
//!
//! The text is the module's tables as `verify_ir.zig` reads them, nothing interpreted: the compound types in
//! interning order, then each function's name, signature, instruction table, packed operand list and blocks.
//! Every instruction field is written raw (`data` as the 64-bit number it is), so the Lean checker decodes
//! extra slices, branch targets and field paths itself, and `parse` gives back a module the Zig verifier checks
//! exactly as it checked the original. `--emit-certificates DIR` writes it as `program.core-ir` beside the
//! certificates; `selka verify-ir` reads it. It never enters a stage or replay record.
//!
//! ```text
//! core-ir-v1
//! types N
//! t list E | t list_view E | t box E | t borrowed E | t dict K V | t array E N VECTOR
//! t record N T... | t union N T... | t fn SIG
//! functions N
//! function NAME SPAN LOOPS        (the declaration's span start and how many loops it records)
//! sig SIG
//! insts N
//! OP TY A B DATA CHECK          (N lines; A and B are `-` for none)
//! extra N R...
//! blocks N
//! block N R... N P...           (the block's instructions, then its predecessors)
//! end
//! ```
//!
//! A type is its number (`ir.Type`'s backing integer). `SIG` is `LINKAGE RET N PARAM... OWNED CONSUMES VIEWS
//! N X... N X... N X... N STEP... N SOURCE...`: the three passing masks and their three tails, then the borrow
//! contract's path (`fK` a field, `pK` a payload) and sources (`aK` an argument, `rN STEP...` a returned owner).
//! A name escapes every byte at or below a space, DEL and `\` as `\xNN`; the empty name is `-`.
const std = @import("std");
const ir = @import("ir.zig");

/// Why a text could not be read back.
pub const Error = error{ Malformed, OutOfMemory };

/// Where and why the text was malformed.
pub const Problem = struct { line: usize = 0, reason: []const u8 = "" };

/// The first line of every `core-ir-v1` text.
pub const format_line = "core-ir-v1";

/// The text of `module`.
pub fn render(a: std.mem.Allocator, module: *const ir.Module) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(a, "{s}\ntypes {d}\n", .{ format_line, module.compounds.items.len });
    for (module.compounds.items) |compound| try renderCompound(a, &out, compound);
    try out.print(a, "functions {d}\n", .{module.functions.items.len});
    for (module.functions.items) |*function| try renderFunction(a, &out, function);
    return out.toOwnedSlice(a);
}

fn number(ty: ir.Type) u32 {
    return @backingInt(ty);
}

fn renderCompound(a: std.mem.Allocator, out: *std.ArrayList(u8), compound: ir.Compound) std.mem.Allocator.Error!void {
    try out.print(a, "t {s}", .{@tagName(compound)});
    switch (compound) {
        .list, .list_view, .box, .borrowed => |inner| try out.print(a, " {d}", .{number(inner)}),
        .dict => |dict| try out.print(a, " {d} {d}", .{ number(dict.key), number(dict.value) }),
        .array => |array| try out.print(a, " {d} {d} {d}", .{ number(array.elem), array.n, @intFromBool(array.vector) }),
        .record, .@"union" => |parts| try renderTypes(a, out, parts),
        .@"fn" => |signature| try renderSignature(a, out, signature),
    }
    try out.append(a, '\n');
}

fn renderTypes(a: std.mem.Allocator, out: *std.ArrayList(u8), types: []const ir.Type) std.mem.Allocator.Error!void {
    try out.print(a, " {d}", .{types.len});
    for (types) |ty| try out.print(a, " {d}", .{number(ty)});
}

fn renderNumbers(a: std.mem.Allocator, out: *std.ArrayList(u8), values: []const u32) std.mem.Allocator.Error!void {
    try out.print(a, " {d}", .{values.len});
    for (values) |value| try out.print(a, " {d}", .{value});
}

fn renderPath(a: std.mem.Allocator, out: *std.ArrayList(u8), path: []const ir.BorrowProjection) std.mem.Allocator.Error!void {
    try out.print(a, " {d}", .{path.len});
    for (path) |step| switch (step) {
        .field => |index| try out.print(a, " f{d}", .{index}),
        .payload => |tag| try out.print(a, " p{d}", .{tag}),
    };
}

fn renderSignature(a: std.mem.Allocator, out: *std.ArrayList(u8), signature: ir.Signature) std.mem.Allocator.Error!void {
    try out.print(a, " {s} {d}", .{ @tagName(signature.linkage), number(signature.ret) });
    try renderTypes(a, out, signature.params);
    const passing = signature.passing;
    try out.print(a, " {d} {d} {d}", .{ passing.owned, passing.consumes, passing.views });
    try renderNumbers(a, out, passing.extra_owned);
    try renderNumbers(a, out, passing.extra_consumes);
    try renderNumbers(a, out, passing.extra_views);
    try renderPath(a, out, signature.borrow.path);
    try out.print(a, " {d}", .{signature.borrow.sources.len});
    for (signature.borrow.sources) |source| switch (source) {
        .argument => |position| try out.print(a, " a{d}", .{position}),
        .result => |path| {
            try out.append(a, ' ');
            try out.append(a, 'r');
            // `rN` then the N steps: the count is glued to the marker, the steps follow as words.
            var steps: std.ArrayList(u8) = .empty;
            try renderPath(a, &steps, path);
            try out.appendSlice(a, steps.items[1..]);
        },
    };
}

fn renderRef(a: std.mem.Allocator, out: *std.ArrayList(u8), ref: ir.Ref) std.mem.Allocator.Error!void {
    if (ref == .none) return out.appendSlice(a, " -");
    try out.print(a, " {d}", .{ref.index()});
}

/// `name` with every byte at or below a space, DEL and `\` written `\xNN`; the empty name is `-`, the name `-` is `\x2d`.
pub fn escapedName(a: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (name.len == 0) return a.dupe(u8, "-");
    if (std.mem.eql(u8, name, "-")) return a.dupe(u8, "\\x2d");
    var out: std.ArrayList(u8) = .empty;
    for (name) |byte| {
        if (byte <= 0x20 or byte == 0x7f or byte == '\\') try out.print(a, "\\x{x:0>2}", .{byte}) else try out.append(a, byte);
    }
    return out.toOwnedSlice(a);
}

fn renderFunction(a: std.mem.Allocator, out: *std.ArrayList(u8), function: *const ir.Function) std.mem.Allocator.Error!void {
    // The span and the number of loops: compiler-only marker declarations must have neither (`build_equality.zig`).
    try out.print(a, "function {s} {d} {d}\nsig", .{ try escapedName(a, function.name), function.span, function.loops.items.len });
    try renderSignature(a, out, function.signature);
    try out.print(a, "\ninsts {d}\n", .{function.insts.items.len});
    for (function.insts.items) |inst| {
        try out.print(a, "{s} {d}", .{ @tagName(inst.op), number(inst.ty) });
        try renderRef(a, out, inst.a);
        try renderRef(a, out, inst.b);
        try out.print(a, " {d} {s}\n", .{ inst.data, @tagName(inst.check) });
    }
    try out.print(a, "extra {d}", .{function.extra.items.len});
    for (function.extra.items) |ref| try renderRef(a, out, ref);
    try out.print(a, "\nblocks {d}\n", .{function.blocks.items.len});
    for (function.blocks.items) |block| {
        try out.print(a, "block {d}", .{block.insts.items.len});
        for (block.insts.items) |ref| try renderRef(a, out, ref);
        try out.print(a, " {d}", .{block.preds.items.len});
        for (block.preds.items) |pred| try out.print(a, " {d}", .{pred.index()});
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "end\n");
}

/// The module a `core-ir-v1` text describes. Every slice is allocated on `a`.
pub fn parse(a: std.mem.Allocator, text: []const u8, problem: *Problem) Error!ir.Module {
    var reader: Reader = .{ .a = a, .problem = problem, .lines = std.mem.splitScalar(u8, text, '\n') };
    const first = try reader.next();
    if (first.len != 1 or !std.mem.eql(u8, first[0], format_line)) return reader.fail("not a core-ir-v1 text");
    var module: ir.Module = .{};
    const types = try reader.counted("types");
    for (0..types) |_| try module.compounds.append(a, try reader.compound());
    const functions = try reader.counted("functions");
    for (0..functions) |_| try module.functions.append(a, try reader.function());
    while (reader.lines.next()) |rest| {
        reader.problem.line += 1;
        if (rest.len != 0) return reader.fail("text after the last function");
    }
    return module;
}

/// One line at a time, split into words; `words` stays valid until the next line is read.
const Reader = struct {
    a: std.mem.Allocator,
    problem: *Problem,
    lines: std.mem.SplitIterator(u8, .scalar),
    words: std.ArrayList([]const u8) = .empty,
    at: usize = 0,

    fn fail(self: *Reader, reason: []const u8) Error {
        self.problem.reason = reason;
        return error.Malformed;
    }

    /// The words of the next line.
    fn next(self: *Reader) Error![]const []const u8 {
        const line = self.lines.next() orelse return self.fail("the text ends early");
        self.problem.line += 1;
        self.words.clearRetainingCapacity();
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        while (it.next()) |piece| try self.words.append(self.a, piece);
        self.at = 0;
        return self.words.items;
    }

    /// The next word of the current line.
    fn word(self: *Reader) Error![]const u8 {
        if (self.at >= self.words.items.len) return self.fail("a line ends early");
        self.at += 1;
        return self.words.items[self.at - 1];
    }

    fn end(self: *Reader) Error!void {
        if (self.at != self.words.items.len) return self.fail("a line has extra words");
    }

    fn int(self: *Reader, comptime T: type) Error!T {
        return parseDecimal(T, try self.word()) orelse self.fail("expected a number");
    }

    fn ty(self: *Reader) Error!ir.Type {
        return @fromBackingInt(try self.int(u32));
    }

    fn ref(self: *Reader) Error!ir.Ref {
        const text = try self.word();
        if (std.mem.eql(u8, text, "-")) return .none;
        const value = parseDecimal(u32, text) orelse return self.fail("expected an instruction number or -");
        if (value == std.math.maxInt(u32)) return self.fail("an instruction number out of range");
        return @fromBackingInt(value);
    }

    /// `KEYWORD N`: a count line.
    fn counted(self: *Reader, expected: []const u8) Error!usize {
        const w = try self.next();
        if (w.len != 2 or !std.mem.eql(u8, w[0], expected)) return self.fail("expected a count line");
        self.at = 1;
        return self.int(usize);
    }

    fn types(self: *Reader) Error![]const ir.Type {
        const out = try self.a.alloc(ir.Type, try self.int(usize));
        for (out) |*slot| slot.* = try self.ty();
        return out;
    }

    fn numbers(self: *Reader) Error![]const u32 {
        const out = try self.a.alloc(u32, try self.int(usize));
        for (out) |*slot| slot.* = try self.int(u32);
        return out;
    }

    fn step(self: *Reader) Error!ir.BorrowProjection {
        const text = try self.word();
        if (text.len < 2) return self.fail("expected a projection step");
        const index = parseDecimal(u32, text[1..]) orelse return self.fail("a bad projection step");
        return switch (text[0]) {
            'f' => .{ .field = index },
            'p' => .{ .payload = index },
            else => self.fail("a bad projection step"),
        };
    }

    fn steps(self: *Reader, count: usize) Error![]const ir.BorrowProjection {
        const out = try self.a.alloc(ir.BorrowProjection, count);
        for (out) |*slot| slot.* = try self.step();
        return out;
    }

    fn source(self: *Reader) Error!ir.BorrowSource {
        const text = try self.word();
        if (text.len < 2) return self.fail("expected a borrow source");
        const value = parseDecimal(u32, text[1..]) orelse return self.fail("a bad borrow source");
        return switch (text[0]) {
            'a' => .{ .argument = value },
            'r' => .{ .result = try self.steps(value) },
            else => self.fail("a bad borrow source"),
        };
    }

    fn signature(self: *Reader) Error!ir.Signature {
        const linkage = std.meta.stringToEnum(ir.Linkage, try self.word()) orelse return self.fail("an unknown linkage");
        const ret = try self.ty();
        const params = try self.types();
        var passing: ir.ParameterPassing = .{ .owned = try self.int(u64), .consumes = try self.int(u64), .views = try self.int(u64) };
        passing.extra_owned = try self.numbers();
        passing.extra_consumes = try self.numbers();
        passing.extra_views = try self.numbers();
        const path = try self.steps(try self.int(usize));
        const sources = try self.a.alloc(ir.BorrowSource, try self.int(usize));
        for (sources) |*slot| slot.* = try self.source();
        return .{ .params = params, .ret = ret, .linkage = linkage, .passing = passing, .borrow = .{ .path = path, .sources = sources } };
    }

    fn compound(self: *Reader) Error!ir.Compound {
        const w = try self.next();
        if (w.len < 2 or !std.mem.eql(u8, w[0], "t")) return self.fail("expected a type line");
        self.at = 2;
        const kind = std.meta.stringToEnum(std.meta.Tag(ir.Compound), w[1]) orelse return self.fail("an unknown compound kind");
        const result: ir.Compound = switch (kind) {
            .list => .{ .list = try self.ty() },
            .list_view => .{ .list_view = try self.ty() },
            .box => .{ .box = try self.ty() },
            .borrowed => .{ .borrowed = try self.ty() },
            .dict => .{ .dict = .{ .key = try self.ty(), .value = try self.ty() } },
            .array => .{ .array = .{ .elem = try self.ty(), .n = try self.int(u32), .vector = try self.flag() } },
            .record => .{ .record = try self.types() },
            .@"union" => .{ .@"union" = try self.types() },
            .@"fn" => .{ .@"fn" = try self.signature() },
        };
        try self.end();
        return result;
    }

    fn flag(self: *Reader) Error!bool {
        return switch (try self.int(u8)) {
            0 => false,
            1 => true,
            else => self.fail("expected 0 or 1"),
        };
    }

    fn keyword(self: *Reader, expected: []const u8) Error!void {
        const w = try self.next();
        if (w.len == 0 or !std.mem.eql(u8, w[0], expected)) return self.fail("an unexpected line");
        self.at = 1;
    }

    fn inst(self: *Reader) Error!ir.Inst {
        _ = try self.next();
        const op = std.meta.stringToEnum(ir.Op, try self.word()) orelse return self.fail("an unknown operation");
        var result: ir.Inst = .{ .op = op, .ty = try self.ty(), .a = try self.ref(), .b = try self.ref(), .data = try self.int(u64) };
        result.check = std.meta.stringToEnum(ir.Check, try self.word()) orelse return self.fail("an unknown check");
        try self.end();
        return result;
    }

    fn block(self: *Reader) Error!ir.Block {
        try self.keyword("block");
        var result: ir.Block = .{};
        const count = try self.int(usize);
        try result.insts.ensureTotalCapacityPrecise(self.a, count);
        for (0..count) |_| result.insts.appendAssumeCapacity(try self.ref());
        const preds = try self.int(usize);
        try result.preds.ensureTotalCapacityPrecise(self.a, preds);
        for (0..preds) |_| result.preds.appendAssumeCapacity(@fromBackingInt(try self.int(u32)));
        try self.end();
        return result;
    }

    fn function(self: *Reader) Error!ir.Function {
        try self.keyword("function");
        const name = try unescape(self.a, try self.word()) orelse return self.fail("a bad escape in a name");
        const span = try self.int(u32);
        const loops = try self.int(usize);
        try self.end();
        try self.keyword("sig");
        var result: ir.Function = .{ .name = name, .signature = try self.signature(), .span = span };
        try self.end();
        // Only the number of loops is kept: no verifier rule reads a loop's blocks.
        const zero: ir.BlockId = @fromBackingInt(0);
        for (0..loops) |index| try result.loops.append(self.a, .{ .id = index, .header = zero, .body = zero, .latch = zero, .exit = zero });
        const insts = try self.counted("insts");
        try result.insts.ensureTotalCapacityPrecise(self.a, insts);
        for (0..insts) |_| result.insts.appendAssumeCapacity(try self.inst());
        try self.keyword("extra");
        const extra = try self.int(usize);
        try result.extra.ensureTotalCapacityPrecise(self.a, extra);
        for (0..extra) |_| result.extra.appendAssumeCapacity(try self.ref());
        try self.end();
        const blocks = try self.counted("blocks");
        try result.blocks.ensureTotalCapacityPrecise(self.a, blocks);
        for (0..blocks) |_| result.blocks.appendAssumeCapacity(try self.block());
        try self.keyword("end");
        try self.end();
        return result;
    }
};

/// A decimal number of digits only (no sign), or null.
fn parseDecimal(comptime T: type, text: []const u8) ?T {
    if (text.len == 0) return null;
    for (text) |c| if (c < '0' or c > '9') return null;
    return std.fmt.parseInt(T, text, 10) catch null;
}

/// The name an escaped name stands for, or null for a bad escape.
fn unescape(a: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error!?[]const u8 {
    if (std.mem.eql(u8, text, "-")) return "";
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] != '\\') {
            try out.append(a, text[i]);
            continue;
        }
        if (i + 4 > text.len or text[i + 1] != 'x') return null;
        try out.append(a, std.fmt.parseInt(u8, text[i + 2 .. i + 4], 16) catch return null);
        i += 3;
    }
    return out.items;
}

test "a module rendered as core-ir-v1 reads back into the same text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const record = try module.intern(a, .{ .record = &.{ .str, list } });
    const optional = try module.option(a, record);
    _ = try module.intern(a, .{ .array = .{ .elem = .f32, .n = 4, .vector = true } });
    _ = try module.intern(a, .{ .dict = .{ .key = .str, .value = .bytes_view } });
    const sources: []const ir.BorrowSource = &.{ .{ .argument = 0 }, .{ .result = &.{ .{ .field = 0 }, .{ .payload = 2 } } } };
    const contract: ir.BorrowContract = .{ .path = &.{.{ .payload = 1 }}, .sources = sources };
    const passing: ir.ParameterPassing = .{ .owned = 1, .extra_views = &.{70} };
    const callable = try module.intern(a, .{ .@"fn" = .{ .params = &.{ list, .u8 }, .ret = optional, .passing = passing, .borrow = contract } });
    var f: ir.Function = .{ .name = "odd name\\", .signature = .{ .params = &.{list}, .ret = callable }, .span = 42 };
    try f.insts.appendSlice(a, &.{
        .{ .op = .param, .ty = list },
        .{ .op = .func_ref, .ty = callable, .data = 0 },
        .{ .op = .phi, .ty = list, .data = ir.ExtraSlice.pack(.{ .start = 0, .len = 2 }) },
        .{ .op = .branch, .ty = .void, .a = @fromBackingInt(0), .data = ir.packTargets(@fromBackingInt(1), @fromBackingInt(1)), .check = .exact },
        .{ .op = .ret, .ty = .void, .a = @fromBackingInt(1), .data = std.math.maxInt(u64) },
    });
    try f.extra.appendSlice(a, &.{ @fromBackingInt(0), .none });
    try f.blocks.append(a, .{});
    try f.blocks.items[0].insts.append(a, @fromBackingInt(3));
    try f.blocks.append(a, .{});
    try f.blocks.items[1].insts.appendSlice(a, &.{ @fromBackingInt(2), @fromBackingInt(4) });
    try f.blocks.items[1].preds.appendSlice(a, &.{ @fromBackingInt(0), @fromBackingInt(0) });
    try module.functions.append(a, f);
    try module.functions.append(a, .{ .name = "", .signature = .{ .params = &.{}, .ret = .byte_buffer, .linkage = .runtime_c } });
    const text = try render(a, &module);
    var problem: Problem = .{};
    const back = try parse(a, text, &problem);
    try std.testing.expectEqualStrings(text, try render(a, &back));
    try std.testing.expectEqualStrings("odd name\\", back.functions.items[0].name);
    try std.testing.expectEqual(@as(u32, 42), back.functions.items[0].span);
    try std.testing.expect(back.functions.items[0].signature.eql(f.signature));
    try std.testing.expect(ir.sameCompound(back.compounds.items[5], module.compounds.items[5]));
    try std.testing.expectEqual(@as(usize, 6), back.compounds.items.len);
}

test "a malformed core-ir-v1 text names its line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var problem: Problem = .{};
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), "core-ir-v1\ntypes 1\nt list\n", &problem));
    try std.testing.expectEqual(@as(usize, 3), problem.line);
    try std.testing.expectError(error.Malformed, parse(arena.allocator(), "ownership-certificate-v2\n", &problem));
    try std.testing.expectEqualStrings("not a core-ir-v1 text", problem.reason);
}
