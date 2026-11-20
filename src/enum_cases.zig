//! The names of an enum's cases: `case_name(value)`, `Kind.cases()` and `Kind.from_name(text)`.
//!
//! Zig's `@tagName`, `std.enums.values` and `std.meta.stringToEnum` have no hand-written counterpart in this language, so a
//! program that printed or parsed a tag kept a `match` over every case (F-S1B-A-103, -201, B2-2, C-104, C-106).
//! `case_name(value)` is a prelude function like `len` and `copy`: it names the case of any enum or tagged union value, as a `str`
//! that holds the declared identifier (`Cooling.fan` is `"fan"`, a payload is ignored). `Kind.cases()` and `Kind.from_name(text)`
//! are calls on the enum type, the spelling a domain operation has, and they exist for an enum none of whose cases carries a payload:
//! the first is the list of every case in declaration order, the second the case a `str` or `bytes` name spells, or `None`.
//! A case named `cases` or `from_name` keeps its own meaning, as a declared function does over a builtin.
//!
//! None of the three adds a typed node kind. `case_name` and `from_name` are a `cast` node whose operand and result types say
//! which (an enum to `str`, a text to an option of the enum), as `function_digest` is a `cast` of a callable to `str`; Core
//! lowers each to a chain of tag tests (`core/build_enum_names.zig`). `cases` is the list literal the source could have written.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const prelude = @import("prelude.zig");
const call_arguments = @import("call_arguments.zig");
const collections = @import("collection_lower.zig");
const sema_shared = @import("sema_shared.zig");
const Error = @import("diagnostic.zig").Error;
const Work = sema_shared.Work;

/// The prelude spelling that names a case; shadowable by a declaration like every prelude name.
pub const name_builtin = "case_name";
/// The method of an enum type that lists its cases.
pub const cases_method = "cases";
/// The method of an enum type that parses a case from its name.
pub const from_name_method = "from_name";
/// The code of every refusal in this file.
pub const code = "E_ENUM_CASES";
/// What `case_name` accepts, for its refusals.
pub const name_message = "case_name takes one enum or tagged union value: `case_name(value)`";

const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
/// Which of the two enum-type methods a call is.
pub const Which = enum { cases, from_name };
/// A recognized `Kind.cases()` or `Kind.from_name(text)`: the method and the enum it is called on.
pub const Recognized = struct { which: Which, enum_type: typed.Type };

/// Whether `ty` is a declared enum or tagged union: a variants type that is neither `Option` nor a checked result.
pub fn isCaseType(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const variants = records[ty.recordIndex()].shape.variants orelse return false;
    return !variants.fallible and prelude.optionCases(variants) == null;
}

/// `case_name(value)`: the typed node of the case's name. It is the `cast` of an enum value to `str`, which no `str(...)` call
/// can make (`E_TEXT_CONVERSION` refuses one), so the lowering reads the pair of types as this operation.
pub fn checkName(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId) Error!typed.Node {
    if (arguments.len != 1) return checker.sink.fail("E_ARITY", span, name_message);
    if (!isCaseType(checker.catalog.records, checker.nodes.items[@backingInt(arguments[0])].ty)) return checker.sink.fail(code, span, name_message);
    return .{ .span = span, .ty = checker.catalog.names.get("str") orelse return error.InternalError, .data = .{ .cast = arguments[0] } };
}

/// The enum a call names with `Kind.cases()` or `Kind.from_name(text)`, or null when the call is another one: not a method
/// of those names, an owner that is a local, a module or no enum, or an enum with a case of that name (the case wins).
fn recognize(comptime Checker: type, self: *Checker, call: Call) Error!?Recognized {
    const owner = call.owner orelse return null;
    if (call.type_arguments.len != 0) return null;
    const method = self.src.text(call.name);
    const which: Which = if (std.mem.eql(u8, method, cases_method)) .cases else if (std.mem.eql(u8, method, from_name_method)) .from_name else return null;
    if (self.active.contains(self.src.text(owner))) return null;
    const enum_type = (try self.catalog.variantType(self.src, owner, self.sink)) orelse return null;
    const variants = self.catalog.records[enum_type.recordIndex()].shape.variants.?;
    for (variants.cases) |case| if (std.mem.eql(u8, case.name, method)) return null;
    return .{ .which = which, .enum_type = enum_type };
}

/// Queue the operand of a `Kind.from_name(text)` call; `Kind.cases()` has none. False when the call is not one of these.
pub fn queue(comptime Checker: type, self: *Checker, work: *std.ArrayList(Work), call: Call, span: source.Span) Error!bool {
    const found = (try recognize(Checker, self, call)) orelse return false;
    try call_arguments.positional(call, self.sink);
    if (call.arguments.len != arity(found.which)) return self.sink.fail("E_ARITY", span, arityMessage(found.which));
    for (call.arguments) |argument| try work.append(self.allocator, .{ .id = argument });
    return true;
}

fn arity(which: Which) usize {
    return if (which == .cases) 0 else 1;
}

fn arityMessage(which: Which) []const u8 {
    return if (which == .cases) "cases takes no arguments: `Kind.cases()`" else "from_name takes one str or bytes name: `Kind.from_name(text)`";
}

/// Check `Kind.cases()` or `Kind.from_name(text)`, with the operand checked already. False when the call is not one of these.
pub fn check(comptime Checker: type, self: *Checker, node: ast.Node, call: Call, out: *typed.Node) Error!bool {
    const found = (try recognize(Checker, self, call)) orelse return false;
    if (!self.catalog.records[found.enum_type.recordIndex()].isEnum())
        return self.sink.fail(code, node.span, "cases and from_name need an enum none of whose cases carries a payload");
    if (call.arguments.len != arity(found.which)) return self.sink.fail("E_ARITY", node.span, arityMessage(found.which));
    const builder: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    if (found.which == .from_name) {
        const text = self.resolved.at(@backingInt(call.arguments[0])).?;
        if (!isText(self.catalog.records, self.nodes.items[@backingInt(text)].ty))
            return self.sink.fail(code, self.syntax.nodes.items[@backingInt(call.arguments[0])].span, arityMessage(.from_name));
        out.* = .{ .span = node.span, .ty = try collections.optionType(&self.catalog, found.enum_type, node.span), .data = .{ .cast = text } };
        return true;
    }
    const variants = self.catalog.records[found.enum_type.recordIndex()].shape.variants.?;
    const values = try self.allocator.alloc(typed.NodeId, variants.cases.len);
    for (values, 0..) |*value, tag| value.* = try builder.node(found.enum_type, .{ .variant = .{ .tag = tag, .value = null } });
    out.* = try builder.literal(try collections.listType(&self.catalog, found.enum_type, node.span), values);
    return true;
}

/// Whether `ty` is `str` or `bytes`, the names `from_name` reads.
pub fn isText(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = records[ty.recordIndex()];
    return record.collection.kind == .string or typed.isByteString(record);
}

/// What a symbolic (generic body) check of the call sees: the method and its enum once the enum and the arity are right, or null
/// when the call is not one of these. The caller builds the result type, which a generic body names through its own shapes.
pub fn symbolic(comptime Checker: type, self: *Checker, call: Call, span: source.Span) Error!?Recognized {
    const found = (try recognize(Checker, self, call)) orelse return null;
    if (!self.catalog.records[found.enum_type.recordIndex()].isEnum())
        return self.sink.fail(code, span, "cases and from_name need an enum none of whose cases carries a payload");
    if (call.arguments.len != arity(found.which)) return self.sink.fail("E_ARITY", span, arityMessage(found.which));
    return found;
}
