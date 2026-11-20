//! The rules of `@sealed` records (W11, `docs/records-and-unions.md#sealed-records`).
//!
//! A sealed record is built and changed only by source text of its declaring module and of that module's test file: the
//! module named `<module>_test` that no module imports, the same rule that lets a test file call private functions
//! (`interfaces.Index.testsModule`). Its fields stay readable everywhere, and a value moves, is copied and is compared like
//! any record. A check is judged on where the text that builds or writes a value sits, which the merged program maps back
//! to its module: a field default is the text of the record that declares it, and a generic instance is the text of its
//! template. The rules end in the front end: Core sees an ordinary record.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const Names = @import("module_names.zig").Names;

/// The code of every refused use of a sealed record.
pub const code = "E_SEALED_RECORD";

/// What a refused operation would do to a sealed value; each has its own message.
pub const Operation = enum {
    /// A constructor call, from field values or from defaults.
    construct,
    /// A write to one of its fields, in any spelling.
    write,
    /// `replace(value, field=...)`, which builds a new value.
    replace,
    /// `take(mut place)`, which leaves a value built from the defaults.
    take,
    /// A field default, written in another module, that builds one.
    default,
    /// A test parameter the test runner would decode or generate.
    input,
    /// `own value.field` of a sealed `@linear` value, which ends it.
    end,
    /// `match mut` on a place that passes through a field of one: its bindings may write the field.
    match_place,
};

/// What a check reads: the merged source, the module index (null for one file, which is one module), the catalog's records
/// and the syntax, whose attributes and functions the message names.
pub const Context = struct {
    src: source.Source,
    names: ?*Names,
    records: []const typed.Record,
    syntax: ast.Program,
};

/// The module whose text at `at` would build or write a value of the sealed record `ty` against the rules: the declaring
/// module's index, or null when `ty` is not sealed or the text is that module's or its test file's.
pub fn refusedModule(context: Context, ty: typed.Type, at: source.Span) ?usize {
    if (!typed.sealed(ty, context.records)) return null;
    const names = context.names orelse return null;
    // A compiler-made node with no source position belongs to no module's text.
    if (context.src.origins.len == 0 or at.end == 0) return null;
    const declaration = context.records[ty.recordIndex()].declaration;
    const declared = context.src.originalSpan(declaration) catch return null;
    const site = context.src.originalSpan(at) catch return null;
    if (declared.input == site.input or names.index.testsModule(site.input, declared.input)) return null;
    return declared.input;
}

/// Refuse `operation` on a value of `ty` at `at` when the rules forbid it there. `instance` names the generic function whose
/// instance the text belongs to, when it is one.
pub fn check(context: Context, allocator: std.mem.Allocator, sink: *diagnostic.Sink, refusal: Refusal) diagnostic.Error!void {
    const module = refusedModule(context, refusal.ty, refusal.at) orelse return;
    const names = context.names.?;
    const record = context.records[refusal.ty.recordIndex()];
    const name = try typed.surfaceTypeName(allocator, refusal.ty, context.records);
    const owner = names.index.project.modules.items[module].name;
    const such = try suggestion(context, allocator, module, bareName(record.name), refusal.operation);
    const base = try message(allocator, refusal.operation, .{ .name = name, .owner = owner, .such = such });
    const text = if (refusal.instance) |generic|
        try std.fmt.allocPrint(allocator, "{s} (in the instance of `{s}` for `{s}`)", .{ base, generic, name })
    else
        base;
    return sink.failRelated(code, refusal.at, text, .{ .span = sealedAttribute(context.syntax, record.declaration), .message = "sealed here" });
}

/// One operation to judge: the value's type, the text that does it, and the generic function whose instance that text is.
pub const Refusal = struct {
    operation: Operation,
    ty: typed.Type,
    at: source.Span,
    instance: ?[]const u8 = null,
};

/// The names a message is written with.
const Words = struct { name: []const u8, owner: []const u8, such: []const u8 };

fn message(allocator: std.mem.Allocator, operation: Operation, w: Words) ![]const u8 {
    return switch (operation) {
        .construct => std.fmt.allocPrint(allocator, "`{s}` is sealed: only module `{s}` and its test file `{s}_test` build one; call a function of " ++
            "`{s}` that returns a `{s}`{s}", .{ w.name, w.owner, w.owner, w.owner, w.name, w.such }),
        .write => std.fmt.allocPrint(allocator, "`{s}` is sealed: only module `{s}` and its test file `{s}_test` change its fields; read the field " ++
            "here, or ask `{s}` for a changed value", .{ w.name, w.owner, w.owner, w.owner }),
        .replace => std.fmt.allocPrint(allocator, "`replace` builds a new `{s}`, and `{s}` is sealed: only module `{s}` and its test file `{s}_test` " ++
            "build one", .{ w.name, w.name, w.owner, w.owner }),
        .take => std.fmt.allocPrint(allocator, "`take` leaves a `{s}` built from its defaults in the place, and `{s}` is sealed: only module `{s}` " ++
            "and its test file `{s}_test` build one; use `exchange(mut place, value)` with a value `{s}` made", .{ w.name, w.name, w.owner, w.owner, w.owner }),
        .default => std.fmt.allocPrint(allocator, "this default builds a `{s}`, and `{s}` is sealed: only module `{s}` and its test file `{s}_test` " ++
            "build one; give the field no default, or make it an option", .{ w.name, w.name, w.owner, w.owner }),
        .input => std.fmt.allocPrint(allocator, "the test runner would build this `{s}` (from a cases file or a generated input), and `{s}` is sealed: " ++
            "only the tests of module `{s}` and its test file `{s}_test` take one as an input", .{ w.name, w.name, w.owner, w.owner }),
        .end => std.fmt.allocPrint(allocator, "`own` of a field ends the sealed `@linear` `{s}` outside module `{s}`; give it to one of its " ++
            "functions that takes `own {s}`{s}", .{ w.name, w.owner, w.name, w.such }),
        .match_place => std.fmt.allocPrint(allocator, "`match mut` asks to write a field of `{s}`, and `{s}` is sealed: only module `{s}` and " ++
            "its test file `{s}_test` change its fields; read it with a plain `match`", .{ w.name, w.name, w.owner, w.owner }),
    };
}

/// The record's name without its module or type arguments: `seal::Token` is `Token`, `pool::Handle<str>` is `Handle`.
fn bareName(name: []const u8) []const u8 {
    var bare = name;
    if (std.mem.indexOfScalar(u8, bare, '<')) |open| bare = bare[0..open];
    if (std.mem.lastIndexOf(u8, bare, "::")) |colons| bare = bare[colons + 2 ..];
    if (std.mem.lastIndexOfScalar(u8, bare, '.')) |dot| bare = bare[dot + 1 ..];
    return bare;
}

/// ", such as `module.function`" for the first public function of the declaring module that returns the record (to build
/// one) or takes it with `own` (to end one), or "" when there is none.
fn suggestion(context: Context, allocator: std.mem.Allocator, module: usize, bare: []const u8, operation: Operation) ![]const u8 {
    if (operation != .construct and operation != .end) return "";
    const names = context.names.?;
    for (context.syntax.functions) |function| {
        const at = context.src.originalSpan(function.name) catch continue;
        if (at.input != module or !names.index.functionExported(context.src, function.name)) continue;
        const fits = switch (operation) {
            .construct => std.mem.eql(u8, std.mem.trim(u8, context.src.text(function.signature.return_type), " "), bare),
            else => owns: {
                for (function.signature.parameters) |parameter| if (parameter.own and std.mem.eql(u8, context.src.text(parameter.ty), bare)) break :owns true;
                break :owns false;
            },
        };
        if (!fits) continue;
        return std.fmt.allocPrint(allocator, ", such as `{s}.{s}`", .{ names.index.project.modules.items[module].name, context.src.text(function.name) });
    }
    return "";
}

/// The `@sealed` clause above the record declared at `declaration`, or the declaration itself.
fn sealedAttribute(syntax: ast.Program, declaration: source.Span) source.Span {
    for (ast.attributesOf(syntax, declaration)) |attribute| if (attribute.kind == .sealed) return attribute.span;
    return declaration;
}

/// Judge every construction, record update and in-place write a checked body built since node `first`: a construction is
/// rule 1 (a `take`'s default is refused first, in `sema_exchange`), an update is a field write (`replace` is refused where
/// it is checked), and a place written in place (`take` or `exchange` of a field, `append(mut r.items, v)`, a `mut r.f`
/// argument; `Checker.writtenPlaces`) is a write when its path passes through a sealed record. The message names the
/// generic function when the body is one of its instances.
pub fn checkBody(comptime Checker: type, self: *Checker, first: usize) diagnostic.Error!void {
    const context = contextOf(Checker, self);
    const instance = instanceOf(Checker, self);
    var index = first;
    while (index < self.nodes.items.len) : (index += 1) {
        const node = self.nodes.items[index];
        const judged: ?Refusal = switch (node.data) {
            .record => .{ .operation = .construct, .ty = node.ty, .at = node.span, .instance = instance },
            .update => .{ .operation = .write, .ty = node.ty, .at = node.span, .instance = instance },
            else => null,
        };
        if (judged) |refusal| try check(context, self.allocator, self.sink, refusal);
        var places: [8]typed.NodeId = undefined;
        const count = self.writtenPlaces(@fromBackingInt(index), &places);
        for (places[0..count]) |place| {
            const holder = sealedHolder(context, self.nodes.items, place) orelse continue;
            try check(context, self.allocator, self.sink, .{ .operation = .write, .ty = holder, .at = node.span, .instance = instance });
        }
    }
}

/// Rule 3 for `match mut <place>:` (W11): its payload bindings write through to the place, whatever the arms then do, so a
/// place whose path passes through a field of a sealed record (`s.mode`, `h.sw.mode`, `xs[0].mode`, `tok.kind` of a binding)
/// is refused outside the record's module and its test file. A plain `match` reads it.
pub fn checkMatchPlace(comptime Checker: type, self: *Checker, place: typed.NodeId, at: source.Span) diagnostic.Error!void {
    const holder = sealedHolder(contextOf(Checker, self), self.nodes.items, place) orelse return;
    return checkHere(Checker, self, .match_place, holder, at);
}

/// The first sealed record on the path of a written place (`t.items`, `h.tok.items[i]`, `xs[i].label`) whose field the
/// write changes, or null.
fn sealedHolder(context: Context, nodes: []const typed.Node, place: typed.NodeId) ?typed.Type {
    var current = place;
    var depth: usize = 0;
    while (depth < 16) : (depth += 1) {
        switch (nodes[@backingInt(current)].data) {
            .field => |field| {
                const base = nodes[@backingInt(field.base)].ty;
                if (typed.sealed(base, context.records)) return base;
                current = field.base;
            },
            .index => |element| current = element.base,
            else => return null,
        }
    }
    return null;
}

/// Rule 12: a test's parameter whose type holds a sealed record anywhere (a field, an element, a key, an option or a union
/// case) is an input the test runner would build, so it is refused unless the test is in the record's module or its test
/// file. `types` and `spans` are the parameters' types and the spans of their declared types, in that module's text.
pub fn checkTestInputs(context: Context, allocator: std.mem.Allocator, sink: *diagnostic.Sink, types: []const typed.Type, spans: []const source.Span) diagnostic.Error!void {
    for (types, spans) |ty, span| {
        var visited: std.AutoHashMapUnmanaged(usize, void) = .empty;
        defer visited.deinit(allocator);
        const held = try heldSealed(context.records, allocator, &visited, ty) orelse continue;
        try check(context, allocator, sink, .{ .operation = .input, .ty = held, .at = span });
    }
}

/// The name of the generic function whose instance the checker is checking, or null for an ordinary body.
pub fn instanceOf(comptime Checker: type, self: *Checker) ?[]const u8 {
    const id = self.current_function orelse return null;
    const function = self.syntaxFunction(id);
    if (function.signature.type_parameters.len == 0) return null;
    return self.src.text(function.name);
}

/// Judge one operation of the body the checker is checking, naming the generic function when the body is an instance.
pub fn checkHere(comptime Checker: type, self: *Checker, operation: Operation, ty: typed.Type, at: source.Span) diagnostic.Error!void {
    return check(contextOf(Checker, self), self.allocator, self.sink, .{ .operation = operation, .ty = ty, .at = at, .instance = instanceOf(Checker, self) });
}

/// The context a checker gives the rules.
pub fn contextOf(comptime Checker: type, self: *const Checker) Context {
    return .{ .src = self.src, .names = self.catalog.module_names, .records = self.catalog.records, .syntax = self.syntax };
}

/// The first sealed record `ty` is or holds, or null.
fn heldSealed(records: []const typed.Record, allocator: std.mem.Allocator, visited: *std.AutoHashMapUnmanaged(usize, void), ty: typed.Type) !?typed.Type {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    if (records[ty.recordIndex()].contract.sealed) return ty;
    if ((try visited.getOrPut(allocator, ty.recordIndex())).found_existing) return null;
    const record = records[ty.recordIndex()];
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| if (try heldSealed(records, allocator, visited, payload)) |found| return found;
        return null;
    }
    if (record.shape.array) |array| return heldSealed(records, allocator, visited, array.element);
    if (record.shape.buffer) |element| if (try heldSealed(records, allocator, visited, element)) |found| return found;
    if (record.collection.key) |key| if (try heldSealed(records, allocator, visited, key)) |found| return found;
    for (record.fields) |field| if (try heldSealed(records, allocator, visited, field.ty)) |found| return found;
    return null;
}

/// Whether a declared function is one the test runner calls with inputs: a public `test_` function or a `@test` one.
pub fn isTest(syntax: ast.Program, src: source.Source, names: ?*Names, function: ast.Function) bool {
    if (ast.hasAttribute(syntax, function.name, .@"test")) return true;
    if (!std.mem.startsWith(u8, src.text(function.name), "test_")) return false;
    const index = (names orelse return true).index;
    return index.functionExported(src, function.name);
}
