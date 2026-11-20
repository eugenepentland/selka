//! Recognition and certain migration edits for removed negative sequence positions.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const buffer_operations = @import("buffer_operations.zig");
const number_literal = @import("number_literal.zig");

/// Diagnostic emitted for a constant negative sequence index or slice endpoint.
pub const code = "E_NEGATIVE_INDEX_REMOVED";
const message = "negative indexes are not allowed; use an explicit offset from len(base), and max(len(base) - offset, 0) for a slice bound";

/// A base spelling that can be duplicated without repeating an operation, and
/// whether its length counts Unicode scalars rather than octets.
const Base = struct { span: source.Span, pure: bool, scalar: bool = false };

/// Positional bounds reject negatives before applying their upper-bound rules.
pub fn rangeBound(kind: buffer_operations.Kind, index: usize) bool {
    if (buffer_operations.search(kind) != null) return index > 0;
    if (kind == .find_any) return index == 1;
    if (kind == .find_any_range) return index == 1 or index == 2;
    return switch (kind) {
        .slice, .view, .borrow_view, .parse_int_range, .parse_float_range, .scalar_count_range => index < 2,
        else => false,
    };
}

/// Report a constant negative position without stopping the remaining checks.
/// Computed negatives stay accepted here and trap at the located runtime check.
pub fn check(comptime Checker: type, checker: *Checker, value: typed.NodeId, bound: bool) diagnostic.Error!void {
    const node = checker.nodes.items[@backingInt(value)];
    const number = constant(Checker, checker, value) orelse return;
    return report(Checker, checker, node.span, number, bound);
}

/// Recognize constant negative positions during checking of uninstantiated generic bodies.
pub fn checkSyntax(comptime Checker: type, checker: *Checker, index: ast.NodeId, bound: bool) diagnostic.Error!void {
    const syntax = syntaxOf(Checker, checker);
    const number = syntaxConstant(checker.src, syntax, index) orelse return;
    return report(Checker, checker, syntax.nodes.items[@backingInt(index)].span, number, bound);
}

fn shadowedName(comptime Checker: type, checker: *Checker, span: source.Span, name: []const u8) diagnostic.Error!bool {
    if (checker.active.contains(name)) return true;
    if (@hasField(Checker, "module_names")) {
        if (checker.module_names) |names| return names.topLevelSpelling(span, name);
    } else if (checker.catalog.module_names) |names| return names.topLevelSpelling(span, name);
    return checker.functions.contains(name);
}

fn report(comptime Checker: type, checker: *Checker, span: source.Span, number: i128, bound: bool) diagnostic.Error!void {
    if (number >= 0) return;
    // The repair looks for the node that holds the index anywhere in the program: bodies filled on demand are filled first.
    try ast.ensureAll(syntaxOf(Checker, checker));
    for (checker.sink.items.items) |item| {
        if (std.mem.eql(u8, item.code, code) and sameSpan(item.span, span)) return;
    }
    const base = originalBase(Checker, checker, span) orelse {
        try checker.sink.items.append(checker.allocator, .{ .code = code, .span = span, .message = message });
        return;
    };
    // The positive literal must itself fit the signed index type. Never negate MIN.
    const shadowed = try shadowedName(Checker, checker, span, "len") or (bound and try shadowedName(Checker, checker, span, "max"));
    if (!base.pure or number < -std.math.maxInt(i64) or shadowed) {
        try checker.sink.items.append(checker.allocator, .{ .code = code, .span = span, .message = message });
        return;
    }
    const spelling = checker.src.text(base.span);
    // A scalar helper's window and answer count scalars, so its repair counts
    // `strings.char_count`; every surface position counts octets (wave 3's C2),
    // so the rest of the language keeps `len` (GW closes F19's gap).
    const replacement = if (bound)
        if (base.scalar)
            try std.fmt.allocPrint(checker.allocator, "max(strings.char_count({s}) - {d}, 0)", .{ spelling, -number })
        else
            try std.fmt.allocPrint(checker.allocator, "max(len({s}) - {d}, 0)", .{ spelling, -number })
    else if (base.scalar)
        try std.fmt.allocPrint(checker.allocator, "strings.char_count({s}) - {d}", .{ spelling, -number })
    else
        try std.fmt.allocPrint(checker.allocator, "len({s}) - {d}", .{ spelling, -number });
    try checker.sink.appendFix(.{ .code = code, .span = span, .message = message }, .{ .span = span, .text = replacement });
}

/// The module and member a call names, whether the parser kept the module as a
/// separate owner or folded it into the call's dotted name.
const Qualified = struct { module: []const u8, member: []const u8 };

fn callQualified(comptime Checker: type, checker: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?Qualified {
    if (call.owner) |owner| return .{ .module = checker.src.text(owner), .member = checker.src.text(call.name) };
    const text = checker.src.text(call.name);
    const dot = std.mem.lastIndexOfScalar(u8, text, '.') orelse return null;
    return .{ .module = text[0..dot], .member = text[dot + 1 ..] };
}

/// The base a helper's position argument indexes: the helper's first argument,
/// whose length is counted in scalars rather than octets.
fn helperBase(comptime Checker: type, checker: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), position: usize) Base {
    var base = baseOf(Checker, checker, call.arguments[0]);
    base.scalar = true;
    for (call.arguments[1..position]) |before| base.pure = base.pure and pureBase(Checker, checker, before);
    return base;
}

/// Whether `module.name` is a scalar helper whose first argument is the value a
/// later position argument indexes.
/// Whether `module.name` is one of the bytes range homes (F-b11), whose first
/// argument is the byte string a bound indexes.
fn byteRangeHome(module: []const u8, name: []const u8) bool {
    if (!std.mem.eql(u8, module, "bytes")) return false;
    return std.mem.eql(u8, name, "parse_int_range") or std.mem.eql(u8, name, "parse_float_range") or std.mem.eql(u8, name, "scalar_count_range");
}

/// The base of a bytes range home's bound: its first argument, with its own length
/// (not a scalar count), and the purity of the operands before the bound.
fn byteRangeBase(comptime Checker: type, checker: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), position: usize) Base {
    var base = baseOf(Checker, checker, call.arguments[0]);
    for (call.arguments[1..position]) |before| base.pure = base.pure and pureBase(Checker, checker, before);
    return base;
}

fn helperCall(module: []const u8, name: []const u8) bool {
    if (std.mem.eql(u8, module, "lists")) return std.mem.eql(u8, name, "stride");
    if (!std.mem.eql(u8, module, "strings")) return false;
    inline for (.{ "char_count", "char_at", "char_slice", "char_stride", "char_find", "char_rfind", "char_index", "char_rindex", "char_count_of", "char_startswith", "char_endswith" }) |spelling| {
        if (std.mem.eql(u8, name, spelling)) return true;
    }
    return false;
}

fn sameSpan(left: source.Span, right: source.Span) bool {
    return left.start == right.start and left.end == right.end;
}

fn constant(comptime Checker: type, checker: *Checker, id: typed.NodeId) ?i128 {
    return switch (checker.nodes.items[@backingInt(id)].data) {
        .integer => |value| value,
        .cast => |input| cast: {
            const ty = checker.nodes.items[@backingInt(id)].ty;
            if (!ty.isInteger()) break :cast null;
            const value = constant(Checker, checker, input) orelse break :cast null;
            break :cast if (value >= ty.min() and value <= ty.max()) value else null;
        },
        .unary => |unary| if (unary.op == .neg) negate: {
            const value = constant(Checker, checker, unary.operand) orelse break :negate null;
            const result = std.math.negate(value) catch break :negate null;
            const ty = checker.nodes.items[@backingInt(id)].ty;
            break :negate if (ty.isInteger() and result >= ty.min() and result <= ty.max()) result else null;
        } else null,
        .binary => |binary| calculated: {
            const ty = checker.nodes.items[@backingInt(id)].ty;
            if (!ty.isInteger()) break :calculated null;
            const left = constant(Checker, checker, binary.left) orelse break :calculated null;
            const right = constant(Checker, checker, binary.right) orelse break :calculated null;
            const result = arithmetic(binary.op, left, right) orelse break :calculated null;
            break :calculated if (result >= ty.min() and result <= ty.max()) result else null;
        },
        else => null,
    };
}

fn matches(syntax: ast.Program, id: ast.NodeId, span: source.Span) bool {
    return sameSpan(syntax.nodes.items[@backingInt(id)].span, span);
}

fn originalBase(comptime Checker: type, checker: *Checker, span: source.Span) ?Base {
    const syntax = syntaxOf(Checker, checker);
    for (syntax.nodes.items) |node| switch (node.data) {
        .index => |index| if (matches(syntax, index.index, span)) return baseOf(Checker, checker, index.base),
        .slice => |slice| {
            var base = baseOf(Checker, checker, slice.base);
            // Reverse bounds formerly clamped below zero to -1, which cannot be
            // expressed by the ordinary max(..., 0) forward-slice migration.
            if (slice.step) |step| base.pure = base.pure and (syntaxConstant(checker.src, syntax, step) orelse 0) > 0;
            if (slice.start) |first| if (matches(syntax, first, span)) return base;
            if (slice.end) |last| if (matches(syntax, last, span)) {
                if (slice.start) |first| base.pure = base.pure and pureBase(Checker, checker, first);
                return base;
            };
        },
        .replace => |replace| if (matches(syntax, replace.index, span)) return baseOf(Checker, checker, replace.base),
        .method_call => |call| if (argumentPosition(syntax, call.arguments, span)) |position| {
            var base = baseOf(Checker, checker, call.base);
            for (call.arguments[0..position]) |before| base.pure = base.pure and pureBase(Checker, checker, before);
            return base;
        },
        .list_operation => |operation| if (argumentPosition(syntax, operation.arguments, span)) |position| {
            var base = baseOf(Checker, checker, operation.base);
            for (operation.arguments[0..position]) |before| base.pure = base.pure and pureBase(Checker, checker, before);
            return base;
        },
        .call => |call| if (argumentPosition(syntax, call.arguments, span)) |position| {
            // A qualified text or list helper takes the collection it indexes as
            // its first argument, so a later position's repair names that
            // argument in the helper's own unit. The parser records the module
            // as a separate owner or, once the module is imported, inside the
            // call's dotted name, so both shapes are read.
            if (callQualified(Checker, checker, call)) |qualified| {
                if (position >= 1 and call.arguments.len >= 2 and helperCall(qualified.module, qualified.member))
                    return helperBase(Checker, checker, call, position);
                // A bytes range word's home (`bytes.parse_int_range(data, -1, 99)`, F-b11)
                // takes the byte string it reads first; its bounds are byte offsets, so
                // the repair names that string's own length, as the method's did.
                if (position >= 1 and call.arguments.len >= 2 and byteRangeHome(qualified.module, qualified.member))
                    return byteRangeBase(Checker, checker, call, position);
            }
            // A writer home (`lists.insert(mut values, -1, item)`) takes the
            // collection it writes as a marked first argument, so a later
            // position's repair names that place exactly as the method's did.
            if (position >= 1 and call.arguments.len >= 2) {
                const receiver = syntax.nodes.items[@backingInt(call.arguments[0])];
                if (receiver.data == .mut_argument) return baseOf(Checker, checker, receiver.data.mut_argument);
                if (receiver.data == .own_argument) return baseOf(Checker, checker, receiver.data.own_argument);
            }
            if (call.owner) |owner| {
                var pure = checker.active.contains(checker.src.text(owner));
                for (call.arguments[0..position]) |before| pure = pure and pureBase(Checker, checker, before);
                return .{ .span = owner, .pure = pure };
            }
        } else if (std.mem.eql(u8, checker.src.text(call.name), "replace") and call.arguments.len == 3 and matches(syntax, call.arguments[1], span)) {
            return baseOf(Checker, checker, call.arguments[0]);
        },
        else => {},
    };
    return null;
}

fn argumentPosition(syntax: ast.Program, arguments: []const ast.NodeId, span: source.Span) ?usize {
    for (arguments, 0..) |argument, position| if (matches(syntax, argument, span)) return position;
    return null;
}

fn baseOf(comptime Checker: type, checker: *Checker, id: ast.NodeId) Base {
    return .{ .span = syntaxOf(Checker, checker).nodes.items[@backingInt(id)].span, .pure = pureBase(Checker, checker, id) };
}

// L01's shared typed predicate replaces the standalone predicate on integration.
fn pureBase(comptime Checker: type, checker: *Checker, id: ast.NodeId) bool {
    if (syntaxConstant(checker.src, syntaxOf(Checker, checker), id) != null) return true;
    switch (syntaxOf(Checker, checker).nodes.items[@backingInt(id)].data) {
        .text, .bytes, .boolean, .unit => return true,
        else => {},
    }
    if (@hasField(Checker, "resolved")) if (checker.resolved.at(@backingInt(id))) |resolved| return @import("migration_support.zig").isPureTypedOperand(checker.nodes.items, resolved);
    return switch (syntaxOf(Checker, checker).nodes.items[@backingInt(id)].data) {
        .name => |name| checker.active.contains(checker.src.text(name)),
        .integer, .text, .bytes, .boolean, .unit => true,
        .field => |field| pureBase(Checker, checker, field.base),
        .unary => |unary| unary.op == .not and pureBase(Checker, checker, unary.operand),
        else => false,
    };
}

fn syntaxOf(comptime Checker: type, checker: *Checker) ast.Program {
    return if (@hasField(Checker, "syntax")) checker.syntax else checker.program;
}

fn syntaxConstant(src: source.Source, syntax: ast.Program, id: ast.NodeId) ?i128 {
    return switch (syntax.nodes.items[@backingInt(id)].data) {
        .integer => |span| literal: {
            const parsed = number_literal.integer(src.text(span));
            if (parsed != .ok) break :literal null;
            const magnitude = number_literal.magnitude(parsed.ok) orelse break :literal null;
            break :literal std.math.cast(i128, magnitude);
        },
        .unary => |unary| if (unary.op == .neg) negate: {
            const value = syntaxConstant(src, syntax, unary.operand) orelse break :negate null;
            const result = std.math.negate(value) catch break :negate null;
            const ty = syntaxIntegerType(src, syntax, unary.operand) orelse break :negate null;
            break :negate if (result >= ty.min() and result <= ty.max()) result else null;
        } else null,
        .binary => |binary| calculated: {
            if (!unsuffixedTree(src, syntax, binary.left) or !unsuffixedTree(src, syntax, binary.right)) break :calculated null;
            const left = syntaxConstant(src, syntax, binary.left) orelse break :calculated null;
            const right = syntaxConstant(src, syntax, binary.right) orelse break :calculated null;
            const result = arithmetic(binary.op, left, right) orelse break :calculated null;
            break :calculated if (result >= std.math.minInt(i64) and result <= std.math.maxInt(i64)) result else null;
        },
        else => null,
    };
}

fn unsuffixedTree(src: source.Source, syntax: ast.Program, id: ast.NodeId) bool {
    return switch (syntax.nodes.items[@backingInt(id)].data) {
        .integer => |span| @import("integer_literal.zig").unsuffixed(src.text(span)),
        .unary => |unary| unary.op == .neg and unsuffixedTree(src, syntax, unary.operand),
        .binary => |binary| (binary.op == .add or binary.op == .sub or binary.op == .mul) and unsuffixedTree(src, syntax, binary.left) and unsuffixedTree(src, syntax, binary.right),
        else => false,
    };
}

fn arithmetic(op: anytype, left: i128, right: i128) ?i128 {
    return switch (op) {
        .add => std.math.add(i128, left, right) catch null,
        .sub => std.math.sub(i128, left, right) catch null,
        .mul => std.math.mul(i128, left, right) catch null,
        else => null,
    };
}

fn syntaxIntegerType(src: source.Source, syntax: ast.Program, id: ast.NodeId) ?typed.Type {
    return switch (syntax.nodes.items[@backingInt(id)].data) {
        .integer => |span| literal: {
            const parsed = number_literal.integer(src.text(span));
            if (parsed != .ok) break :literal null;
            break :literal if (parsed.ok.suffix.len == 0) .i64 else typed.Type.fromName(parsed.ok.suffix);
        },
        .unary => |unary| if (unary.op == .neg) syntaxIntegerType(src, syntax, unary.operand) else null,
        .binary => if (unsuffixedTree(src, syntax, id)) .i64 else null,
        else => null,
    };
}
