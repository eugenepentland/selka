//! Certain statement repairs for retired collection and generator expressions.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const support = @import("migration_support.zig");
const gathers = @import("gather_use.zig");
const ModuleNames = @import("module_names.zig").Names;
const moves = @import("migration_moves.zig");
const binding_line = "const {s}: {s} = {s}";

/// Publish a typed accumulator repair without moving conditional or repeated work.
pub fn publish(comptime Checker: type, checker: *Checker, node: ast.Node, gather: ast.Gather, use: gathers.Use, ty: typed.Type) diagnostic.Error!void {
    if (try filled(Checker, checker, node, gather, ty)) return;
    const schema = if (ty.isAggregate()) checker.catalog.records[ty.recordIndex()] else null;
    const value = switch (use) {
        .list, .dict => schema.?.shape.buffer.?,
        .set => schema.?.collection.key.?,
        else => ty,
    };
    const types: Types = .{
        .result = try typed.surfaceTypeName(checker.allocator, ty, checker.catalog.records),
        .value = try typed.surfaceTypeName(checker.allocator, value, checker.catalog.records),
        .key = if (use == .dict) try typed.surfaceTypeName(checker.allocator, schema.?.collection.key.?, checker.catalog.records) else null,
        .managed_value = @import("own_parameters.zig").managed(checker.catalog.records, value),
        .managed_key = use == .dict and @import("own_parameters.zig").managed(checker.catalog.records, schema.?.collection.key.?),
    };
    const context: Context = .{
        .src = checker.src,
        .syntax = checker.syntax,
        .prefix = try modulePrefix(checker.allocator, checker.src, node.span, checker.catalog.module_names),
    };
    try publishNamed(checker.allocator, context, checker.sink, .{ .node = node, .gather = gather, .use = use, .types = types });
}

fn filled(comptime Checker: type, checker: *Checker, node: ast.Node, gather: ast.Gather, ty: typed.Type) diagnostic.Error!bool {
    if (gather.shape != .list) return false;
    // Import aliases still reserve their underlying module name in the checker.
    // Keep loops when adding that name could shadow any original-module binding.
    var original_bytes = checker.src.bytes;
    if (checker.src.origins.len != 0) {
        const original = checker.src.originalSpan(node.span) catch return error.InternalError;
        original_bytes = checker.src.origins[original.input].original.bytes;
    }
    var names = std.mem.tokenizeAny(u8, original_bytes, " \t\r\n.,:()[]{}+-*/=<>!\"'");
    while (names.next()) |name| if (std.mem.eql(u8, name, "lists")) return false;

    if (std.mem.indexOfScalar(u8, checker.src.text(node.span), '#') != null) return false;
    const outer = checker.syntax.statements.items[@backingInt(gather.loop)];
    if (outer.data != .for_range) return false;
    const range = outer.data.for_range;
    if (range.step != null or checker.syntax.nodes.items[@backingInt(range.start)].data != .unit) return false;
    const body = checker.syntax.statements.items[@backingInt(range.body)];
    if (body.data != .gather_step) return false;
    const output = body.data.gather_step.value;
    const checked = checker.resolved.at(@backingInt(output)) orelse return false;
    if (!support.isPureOperand(checker.syntax, output) or !support.isPureTypedOperand(checker.nodes.items, checked)) return false;
    const end = checker.resolved.at(@backingInt(range.end)) orelse return false;
    if (checker.nodes.items[@backingInt(end)].ty != .i64) return false;
    const value_span = checker.syntax.nodes.items[@backingInt(output)].span;
    for (checker.syntax.nodes.items) |child| {
        if (child.data != .name or !contains(value_span, child.span)) continue;
        if (std.mem.eql(u8, checker.src.text(child.data.name), checker.src.text(range.name))) return false;
    }
    const count = checker.src.text(checker.syntax.nodes.items[@backingInt(range.end)].span);
    const element = checker.catalog.records[ty.recordIndex()].shape.buffer.?;
    const rendered = try typed.surfaceTypeName(checker.allocator, element, checker.catalog.records);
    const prefix = try modulePrefix(checker.allocator, checker.src, node.span, checker.catalog.module_names);
    const type_name = try support.localTypeText(checker.allocator, rendered, prefix);
    const text = try std.fmt.allocPrint(checker.allocator, "lists.filled[{s}]({s}, {s})", .{ type_name, count, checker.src.text(value_span) });
    try @import("repetition.zig").removed(Checker, checker, node.span, .{
        .code = "E_COMPREHENSION_REMOVED",
        .message = "comprehensions were removed; use lists.filled for a constant fill value",
        .module = "lists",
    }, text);
    return true;
}

/// Borrowed source and syntax shared by concrete and abstract recognition.
pub const Context = struct { src: source.Source, syntax: ast.Program, prefix: []const u8 = "" };

/// One retired expression with its inferred, specialization-independent type.
pub const Request = struct { node: ast.Node, gather: ast.Gather, use: gathers.Use, types: Types };

/// Source spellings that preserve contextual literal and nested collection types.
/// A managed fact also covers a symbolic element that may own storage: its
/// generated named transfer keeps `own` in scalar and managed specializations.
pub const Types = struct { result: []const u8, value: []const u8, key: ?[]const u8 = null, managed_value: bool = false, managed_key: bool = false };

/// Publish a repair whose type spelling was derived before specialization.
pub fn publishNamed(allocator: std.mem.Allocator, context: Context, sink: *diagnostic.Sink, request: Request) diagnostic.Error!void {
    const code = if (request.gather.shape == .generator) gathers.generator_code else "E_COMPREHENSION_REMOVED";
    const message = "comprehensions and generator arguments were removed; use a typed accumulator and explicit for/if statements";
    var item: diagnostic.Diagnostic = .{ .code = code, .span = request.node.span, .message = message };
    var local = request;
    local.types = .{
        .result = try support.localTypeText(allocator, request.types.result, context.prefix),
        .value = try support.localTypeText(allocator, request.types.value, context.prefix),
        .key = if (request.types.key) |key| try support.localTypeText(allocator, key, context.prefix) else null,
        .managed_value = request.types.managed_value,
        .managed_key = request.types.managed_key,
    };
    if (try repair(allocator, context, local)) |fix| item.provenance.fix = fix;
    try sink.items.append(allocator, item);
}

/// The original expression's owning-module prefix in merged type spellings.
pub fn modulePrefix(allocator: std.mem.Allocator, src: source.Source, span: source.Span, names: ?*ModuleNames) diagnostic.Error![]const u8 {
    const modules = names orelse return "";
    const origin = src.originalSpan(span) catch return error.InternalError;
    if (origin.input >= modules.index.project.modules.items.len) return error.InternalError;
    return std.fmt.allocPrint(allocator, "{s}.", .{modules.index.project.modules.items[origin.input].name});
}

fn repair(allocator: std.mem.Allocator, checker: Context, request: Request) diagnostic.Error!?diagnostic.Fix {
    const node = request.node;
    const gather = request.gather;
    const use = request.use;
    const type_name = request.types.result;
    const syntax = checker.syntax;
    if (std.mem.indexOfScalar(u8, checker.src.text(node.span), '#') != null) return null;
    var replacement = node.span;
    if (gather.shape == .generator and use.folds()) {
        replacement = consumingCall(checker.src, syntax, node.span) orelse return null;
    }
    const statement_span = support.enclosingStatement(syntax, replacement) orelse return null;
    const root = statementRoot(syntax, statement_span) orelse return null;
    if (!certainPath(syntax, root, replacement, 0)) return null;
    // Nested expressions remain in their generated local binding. Later fix
    // rounds can repair them inside the loop, preserving repeated evaluation.
    const out = try fresh(allocator, checker.src, "gather_result", node.span.start);
    const candidate = try fresh(allocator, checker.src, "gather_value", node.span.start);
    const seen = try fresh(allocator, checker.src, "gather_seen", node.span.start);
    var writer: Writer = .{ .allocator = allocator, .context = checker, .use = use, .names = .{ .out = out, .candidate = candidate, .seen = seen }, .types = request.types };
    const initial: []const u8 = switch (use) {
        .list => "[]",
        .set => "set()",
        .dict => "{}",
        .sum => if (std.mem.eql(u8, type_name, "float")) "0.0" else "0",
        .any => "False",
        .all => "True",
        .min, .max => "None",
    };
    const accumulator_type = if (use == .min or use == .max) try std.fmt.allocPrint(allocator, "{s}?", .{type_name}) else type_name;
    try writer.line(0, "mut {s}: {s} = {s}", .{ out, accumulator_type, initial });
    if (use == .any or use == .all) try writer.line(0, "mut {s} = False", .{seen});
    if (!try writer.loop(gather.loop, 0)) return null;
    var result = out;
    if (use == .min or use == .max) {
        const final = try fresh(allocator, checker.src, "gather_final", node.span.start);
        try writer.line(0, "mut {s}: {s}", .{ final, type_name });
        try writer.line(0, "match {s}{s}:", .{ if (request.types.managed_value) "own " else "", out });
        try writer.line(1, "case Some({s}):", .{candidate});
        try writer.line(2, "{s} = {s}{s}", .{ final, if (request.types.managed_value) "own " else "", candidate });
        try writer.line(1, "case None:", .{});
        try writer.line(2, "assert False, \"{s}() arg is an empty sequence\"", .{@tagName(use)});
        const empty = try fresh(allocator, checker.src, "gather_empty", node.span.start);
        try writer.line(2, "const {s}: {s}[] = []", .{ empty, type_name });
        try writer.line(2, "{s} = {s}({s})", .{ final, @tagName(use), empty });
        result = final;
    }
    const insertion = try support.insertBeforeStatement(allocator, checker.src, statement_span, writer.text.items) orelse return null;
    const managed_result = use == .list or use == .set or use == .dict or request.types.managed_value;
    if (managed_result and storedResult(checker.src, syntax, statement_span, replacement)) result = try std.fmt.allocPrint(allocator, "own {s}", .{result});
    return .{ .edit = .{ .span = replacement, .text = result }, .more = try allocator.dupe(diagnostic.Edit, &.{insertion}) };
}

fn storedResult(src: source.Source, syntax: ast.Program, statement_span: source.Span, value: source.Span) bool {
    for (syntax.statements.items) |statement| {
        if (!std.meta.eql(statement.span, statement_span)) continue;
        const root = switch (statement.data) {
            .binding => |binding| binding.value,
            .assignment => |assignment| assignment.value,
            else => break,
        };
        if (std.meta.eql(syntax.nodes.items[@backingInt(root)].span, value)) return true;
        break;
    }
    // Hoisting a fresh result into a named accumulator must preserve the
    // original constructor/callee transfer, while len/copy still only read.
    for (syntax.nodes.items) |parent| switch (parent.data) {
        .wrap => |wrapped| if (sameValue(syntax, wrapped.value, value)) return true,
        .variant => |variant| {
            if (variant.value) |id| if (sameValue(syntax, id, value)) return true;
            for (variant.values) |id| if (sameValue(syntax, id, value)) return true;
        },
        .record => |record| {
            for (record.fields) |field| if (sameValue(syntax, field.value, value)) return true;
        },
        .list_literal, .set_literal, .dictionary_literal, .tuple => |items| {
            for (items) |id| if (sameValue(syntax, id, value)) return true;
        },
        .call => |call| {
            for (call.arguments, 0..) |id, position| if (sameValue(syntax, id, value))
                return takingArgument(src, syntax, call, position);
        },
        else => {},
    };
    return false;
}

fn sameValue(syntax: ast.Program, id: ast.NodeId, span: source.Span) bool {
    return std.meta.eql(syntax.nodes.items[@backingInt(id)].span, span);
}

fn takingArgument(src: source.Source, syntax: ast.Program, call: @FieldType(@FieldType(ast.Node, "data"), "call"), position: usize) bool {
    const name = src.text(call.name);
    if (call.owner != null) return false;
    for (syntax.functions) |function| {
        if (function.policy.owner != null or !std.mem.eql(u8, src.text(function.name), name)) continue;
        if (src.origins.len != 0) {
            const invoked = src.originalSpan(call.name) catch return false;
            const declared = src.originalSpan(function.name) catch return false;
            if (invoked.input != declared.input) continue;
        }
        var parameter = position;
        if (call.argument_names.len != 0) if (call.argument_names[position]) |label| {
            for (function.signature.parameters, 0..) |input, index| if (std.mem.eql(u8, src.text(input.name), src.text(label))) {
                parameter = index;
                break;
            };
        };
        return parameter < function.signature.parameters.len and function.signature.parameters[parameter].own;
    }
    for (syntax.types.records) |record| if (std.mem.eql(u8, src.text(record.name), name)) return true;
    return std.mem.eql(u8, name, "Some") or std.mem.eql(u8, name, "Ok") or std.mem.eql(u8, name, "Err");
}

fn fresh(allocator: std.mem.Allocator, src: source.Source, stem: []const u8, offset: usize) diagnostic.Error![]const u8 {
    return support.freshOriginNameAt(allocator, src, stem, offset) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidSourceSpan => error.InternalError,
    };
}

fn consumingCall(src: source.Source, syntax: ast.Program, span: source.Span) ?source.Span {
    for (syntax.nodes.items) |node| {
        if (node.data != .call or node.data.call.owner != null or node.data.call.arguments.len != 1) continue;
        const argument = syntax.nodes.items[@backingInt(node.data.call.arguments[0])];
        if (argument.span.start != span.start or argument.span.end != span.end) continue;
        const use = gathers.Use.consuming(src.text(node.data.call.name)) orelse continue;
        if (use.folds()) return node.span;
    }
    return null;
}
fn statementRoot(syntax: ast.Program, span: source.Span) ?ast.NodeId {
    for (syntax.statements.items) |statement| {
        if (statement.span.start != span.start or statement.span.end != span.end) continue;
        return switch (statement.data) {
            .binding => |binding| binding.value,
            .assignment => |assignment| if (assignment.op == .set) assignment.value else null,
            .ret, .discard => |value| value,
            .branch => |branch| branch.condition,
            .assertion => |claim| claim.condition,
            .for_each => |each| each.iterable,
            .match => |match| match.value,
            else => null,
        };
    }
    return null;
}
fn contains(span: source.Span, target: source.Span) bool {
    return span.start <= target.start and span.end >= target.end;
}
fn certainPath(syntax: ast.Program, id: ast.NodeId, target: source.Span, depth: usize) bool {
    if (depth > 128) return false;
    const node = syntax.nodes.items[@backingInt(id)];
    if (node.span.start == target.start and node.span.end == target.end) return true;
    if (!contains(node.span, target)) return false;
    return switch (node.data) {
        .length, .propagate => |value| certainPath(syntax, value, target, depth + 1),
        .unary => |unary| certainPath(syntax, unary.operand, target, depth + 1),
        .binary => |binary| if (contains(syntax.nodes.items[@backingInt(binary.left)].span, target))
            certainPath(syntax, binary.left, target, depth + 1)
        else if (binary.op == .logical_and or binary.op == .logical_or) false else support.evaluationOrderCertain(syntax, &.{binary.left}) and certainPath(syntax, binary.right, target, depth + 1),
        .call => |call| call.owner == null and call.evaluation_order.len == 0 and callPath(syntax, call.arguments, target, depth),
        // `"".join([...])` and `b"".join(...)`: the receiver is evaluated before the arguments, so
        // the loop may move ahead of it only when it is a stable literal.
        .method_call => |call| call.argument_names.len == 0 and stableOperands(syntax, &.{call.base}) and callPath(syntax, call.arguments, target, depth),
        else => false,
    };
}
fn callPath(syntax: ast.Program, arguments: []const ast.NodeId, target: source.Span, depth: usize) bool {
    for (arguments, 0..) |argument, index| {
        if (!contains(syntax.nodes.items[@backingInt(argument)].span, target)) continue;
        return stableOperands(syntax, arguments[0..index]) and certainPath(syntax, argument, target, depth + 1);
    }
    return false;
}
/// Operands a hoisted loop may cross without changing what the statement evaluates: the stable
/// literals every migration accepts, plus string and byte literals, which evaluate to constant text.
fn stableOperands(syntax: ast.Program, preceding: []const ast.NodeId) bool {
    for (preceding) |operand| {
        if (@backingInt(operand) >= syntax.nodes.items.len) return false;
        switch (syntax.nodes.items[@backingInt(operand)].data) {
            .text, .bytes => {},
            else => if (!support.evaluationOrderCertain(syntax, &.{operand})) return false,
        }
    }
    return true;
}

const Names = struct { out: []const u8, candidate: []const u8, seen: []const u8 };

/// Source loop reconstruction in clause order; each line has relative indentation.
const Writer = struct {
    allocator: std.mem.Allocator,
    context: Context,
    use: gathers.Use,
    names: Names,
    types: Types,
    text: std.ArrayList(u8) = .empty,

    fn line(self: *Writer, depth: usize, comptime format: []const u8, args: anytype) diagnostic.Error!void {
        try self.text.appendNTimes(self.allocator, ' ', depth * 4);
        try self.text.appendSlice(self.allocator, try std.fmt.allocPrint(self.allocator, format, args));
        try self.text.append(self.allocator, '\n');
    }
    fn expression(self: Writer, id: ast.NodeId) []const u8 {
        return self.context.src.text(self.context.syntax.nodes.items[@backingInt(id)].span);
    }
    fn loop(self: *Writer, id: ast.StatementId, depth: usize) diagnostic.Error!bool {
        const statement = self.context.syntax.statements.items[@backingInt(id)];
        switch (statement.data) {
            .for_each => |each| {
                const names = if (each.index_name) |index| try std.fmt.allocPrint(self.allocator, "{s}, {s}", .{ self.context.src.text(index), self.context.src.text(each.name) }) else self.context.src.text(each.name);
                const input = if (each.enumerated) try std.fmt.allocPrint(self.allocator, "enumerate({s})", .{self.expression(each.iterable)}) else self.expression(each.iterable);
                try self.line(depth, "for {s} in {s}:", .{ names, input });
                if (!try self.loop(each.body, depth + 1)) return false;
                try self.exit(depth + 1);
            },
            .for_range => |range| {
                const start = if (self.context.syntax.nodes.items[@backingInt(range.start)].data == .unit) "0" else self.expression(range.start);
                const stride = if (range.step) |value| try std.fmt.allocPrint(self.allocator, ", {s}", .{self.expression(value)}) else "";
                try self.line(depth, "for {s} in range({s}, {s}{s}):", .{ self.context.src.text(range.name), start, self.expression(range.end), stride });
                if (!try self.loop(range.body, depth + 1)) return false;
                try self.exit(depth + 1);
            },
            .branch => |branch| {
                if (branch.else_body != null) return false;
                try self.line(depth, "if {s}:", .{self.expression(branch.condition)});
                return self.loop(branch.then_body, depth + 1);
            },
            .gather_step => |value| return self.step(value, depth),
            else => return false,
        }
        return true;
    }
    fn exit(self: *Writer, depth: usize) diagnostic.Error!void {
        if (self.use != .any and self.use != .all) return;
        try self.line(depth, "if {s}:", .{self.names.seen});
        try self.line(depth + 1, "break", .{});
    }
    fn step(self: *Writer, value: ast.GatherStep, depth: usize) diagnostic.Error!bool {
        const text = try moves.capture(self.allocator, self.context.src, self.context.syntax, value.value, self.types.managed_value);
        if (self.use != .dict) try self.line(depth, binding_line, .{ self.names.candidate, self.types.value, text });
        switch (self.use) {
            .list => if (self.types.managed_value)
                try self.line(depth, "append(mut {s}, own {s})", .{ self.names.out, self.names.candidate })
            else
                try self.line(depth, "append(mut {s}, {s})", .{ self.names.out, self.names.candidate }),
            .set => try self.line(depth, "{s}.add({s}{s})", .{ self.names.out, if (self.types.managed_value) "own " else "", self.names.candidate }),
            .dict => {
                const key = value.key orelse return false;
                const key_name = try fresh(self.allocator, self.context.src, "gather_key", valueSpan(self.context.syntax, value.value).start);
                const key_text = try moves.capture(self.allocator, self.context.src, self.context.syntax, key, self.types.managed_key);
                try self.line(depth, binding_line, .{ key_name, self.types.key.?, key_text });
                try self.line(depth, binding_line, .{ self.names.candidate, self.types.value, text });
                try self.line(depth, "{s}[{s}{s}] = {s}{s}", .{ self.names.out, if (self.types.managed_key) "own " else "", key_name, if (self.types.managed_value) "own " else "", self.names.candidate });
            },
            .sum => try self.line(depth, "{s} += {s}", .{ self.names.out, self.names.candidate }),
            .any, .all => {
                try self.line(depth, "if {s}({s}):", .{ if (self.use == .all) "not " else "", self.names.candidate });
                try self.line(depth + 1, "{s} = {s}", .{ self.names.out, if (self.use == .any) "True" else "False" });
                try self.line(depth + 1, "{s} = True", .{self.names.seen});
                try self.line(depth + 1, "break", .{});
            },
            .min, .max => {
                const replace = try fresh(self.allocator, self.context.src, "gather_replace", valueSpan(self.context.syntax, value.value).start);
                try self.line(depth, "mut {s} = False", .{replace});
                try self.line(depth, "match {s}:", .{self.names.out});
                const previous = try fresh(self.allocator, self.context.src, "gather_previous", valueSpan(self.context.syntax, value.value).start);
                try self.line(depth + 1, "case Some({s}):", .{previous});
                try self.line(depth + 2, "{s} = {s} {s} {s}", .{ replace, self.names.candidate, if (self.use == .min) "<" else ">", previous });
                try self.line(depth + 1, "case None:", .{});
                try self.line(depth + 2, "{s} = True", .{replace});
                // The selected payload borrows the accumulator until the match
                // ends. Decide inside that scope, then replace the owner outside.
                try self.line(depth, "if {s}:", .{replace});
                try self.line(depth + 1, "{s} = Some({s}{s})", .{ self.names.out, if (self.types.managed_value) "own " else "", self.names.candidate });
            },
        }
        return true;
    }
};

fn valueSpan(syntax: ast.Program, id: ast.NodeId) source.Span {
    return syntax.nodes.items[@backingInt(id)].span;
}

// spec-case: COMPREHENSION-3
test "wave1 comprehensions local type rendering respects nested token boundaries" {
    const text = try support.localTypeText(std.testing.allocator, "dict[shapes.Key, other.shapes.Value[shapes.PartSpec[]]?]", "shapes.");
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("dict[Key, other.shapes.Value[PartSpec[]]?]", text);
}
