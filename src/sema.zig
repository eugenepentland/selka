//! Scope and type checking use resolved binding identities, including advisory use counts.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const records = @import("records.zig");
const Error = diagnostic.Error;
const Work = struct { id: ast.NodeId, emit: bool = false };
const CheckedStatement = struct { id: typed.StatementId, terminates: bool };

const Checker = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    syntax: ast.Program,
    sink: *diagnostic.Sink,
    nodes: std.ArrayList(typed.Node) = .empty,
    statements: std.ArrayList(typed.Statement) = .empty,
    locals: std.ArrayList(typed.Local) = .empty,
    active: std.StringHashMapUnmanaged(typed.LocalId) = .empty,
    resolved: []?typed.NodeId,
    functions: std.StringHashMapUnmanaged(typed.FunctionId) = .empty,
    return_type: typed.Type = .i64,
    catalog: records.Catalog,
    conversion_fields: ?[]bool = null,

    fn ty(self: *Checker, span: source.Span) Error!typed.Type {
        return self.catalog.resolve(self.src, span, self.sink);
    }
    fn fields(self: *Checker, record_type: typed.Type, initializers: []const ast.FieldInit, complete: bool, span: source.Span) Error![]const typed.FieldInit {
        const record = try self.catalog.record(record_type, span, self.sink);
        const seen = try self.allocator.alloc(bool, record.fields.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        const checked = try self.allocator.alloc(typed.FieldInit, initializers.len);
        for (initializers, checked) |field, *out| {
            const index = try self.catalog.field(record_type, self.src, field.name, self.sink);
            if (seen[index]) return self.sink.fail("E_DUPLICATE_FIELD", field.name, "field is initialized more than once");
            seen[index] = true;
            const value = self.resolved[@backingInt(field.value)].?;
            try self.require(self.nodes.items[@backingInt(value)].ty, record.fields[index].ty, self.syntax.nodes.items[@backingInt(field.value)].span);
            out.* = .{ .index = index, .value = value };
        }
        if (complete) for (seen, record.fields) |present, field| {
            if (!present) {
                const message = try std.fmt.allocPrint(self.allocator, "missing initializer for field `{s}` of `{s}`", .{ field.name, record.name });
                return self.sink.failRelated("E_INCOMPLETE_CONSTRUCTION", span, message, .{ .span = field.declaration, .message = "missing field declared here" });
            }
        };
        return checked;
    }
    fn queueFields(self: *Checker, work: *std.ArrayList(Work), initializers: []const ast.FieldInit) Error!void {
        var i = initializers.len;
        while (i > 0) {
            i -= 1;
            try work.append(self.allocator, .{ .id = initializers[i].value });
        }
    }
    fn require(self: *Checker, actual: typed.Type, expected: typed.Type, span: source.Span) Error!void {
        if (actual != expected) {
            const message = try std.fmt.allocPrint(self.allocator, "expected {s}, found {s}", .{ typed.typeName(expected, self.catalog.records), typed.typeName(actual, self.catalog.records) });
            return self.sink.fail("E_TYPE", span, message);
        }
    }
    fn resolve(self: *Checker, name: source.Span) Error!typed.LocalId {
        return self.active.get(self.src.text(name)) orelse self.sink.fail("E_UNKNOWN_NAME", name, "name is not defined in this scope");
    }
    fn minimum(self: *Checker, node: ast.Node) bool {
        if (node.data != .unary or node.data.unary.op != .neg) return false;
        const child = self.syntax.nodes.items[@backingInt(node.data.unary.operand)];
        if (child.data != .integer) return false;
        const magnitude = std.fmt.parseUnsigned(u64, self.src.text(child.data.integer), 10) catch return false;
        return magnitude == (@as(u64, 1) << 63);
    }
    fn expression(self: *Checker, root: ast.NodeId) Error!typed.NodeId {
        var work: std.ArrayList(Work) = .empty;
        defer work.deinit(self.allocator);
        try work.append(self.allocator, .{ .id = root });
        while (work.pop()) |task| {
            const index = @backingInt(task.id);
            if (self.resolved[index] != null) continue;
            const node = self.syntax.nodes.items[index];
            const is_minimum = self.minimum(node);
            if (!task.emit and !is_minimum) {
                switch (node.data) {
                    .record => |record| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try self.queueFields(&work, record.fields);
                        continue;
                    },
                    .update => |update| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try self.queueFields(&work, update.fields);
                        try work.append(self.allocator, .{ .id = update.base });
                        continue;
                    },
                    .field => |field| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = field.base });
                        continue;
                    },
                    .call => |call| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        var i = call.arguments.len;
                        while (i > 0) {
                            i -= 1;
                            try work.append(self.allocator, .{ .id = call.arguments[i] });
                        }
                        continue;
                    },
                    .unary => |u| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = u.operand });
                        continue;
                    },
                    .binary => |b| {
                        try work.append(self.allocator, .{ .id = task.id, .emit = true });
                        try work.append(self.allocator, .{ .id = b.right });
                        try work.append(self.allocator, .{ .id = b.left });
                        continue;
                    },
                    else => {},
                }
            }
            var out: typed.Node = .{ .span = node.span, .ty = .i64, .data = undefined };
            if (is_minimum) {
                out.data = .{ .integer = std.math.minInt(i64) };
            } else switch (node.data) {
                .record => |record| {
                    out.ty = try self.ty(record.name);
                    out.data = .{ .record = try self.fields(out.ty, record.fields, true, node.span) };
                },
                .update => |update| {
                    const base = self.resolved[@backingInt(update.base)].?;
                    out.ty = self.nodes.items[@backingInt(base)].ty;
                    out.data = .{ .update = .{ .base = base, .fields = try self.fields(out.ty, update.fields, false, node.span) } };
                },
                .field => |field| {
                    const base = self.resolved[@backingInt(field.base)].?;
                    const record_type = self.nodes.items[@backingInt(base)].ty;
                    const field_index = try self.catalog.field(record_type, self.src, field.name, self.sink);
                    if (self.conversion_fields) |seen| {
                        const base_node = self.nodes.items[@backingInt(base)];
                        if (base_node.data == .local and @backingInt(base_node.data.local) == 0) seen[field_index] = true;
                    }
                    out.ty = self.catalog.records[@backingInt(record_type) - 2].fields[field_index].ty;
                    out.data = .{ .field = .{ .base = base, .index = field_index } };
                },
                .integer => |token| out.data = .{ .integer = std.fmt.parseInt(i64, self.src.text(token), 10) catch
                    return self.sink.fail("E_INTEGER_RANGE", token, "integer literal does not fit i64; the minimum magnitude must be directly negated") },
                .boolean => |value| {
                    out.ty = .bool;
                    out.data = .{ .boolean = value };
                },
                .name => |name| {
                    const slot = try self.resolve(name);
                    self.locals.items[@backingInt(slot)].reads += 1;
                    out.ty = self.locals.items[@backingInt(slot)].ty;
                    out.data = .{ .local = slot };
                },
                .call => |call| {
                    const function = self.functions.get(self.src.text(call.name)) orelse
                        return self.sink.fail("E_UNKNOWN_FUNCTION", call.name, "no top-level function has this name");
                    const signature = self.syntax.functions[@backingInt(function)];
                    if (signature.parameters.len != call.arguments.len)
                        return self.sink.fail("E_ARITY", node.span, "argument count does not match function parameters");
                    const arguments = try self.allocator.alloc(typed.NodeId, call.arguments.len);
                    for (call.arguments, signature.parameters, arguments) |arg, parameter, *out_arg| {
                        out_arg.* = self.resolved[@backingInt(arg)].?;
                        try self.require(self.nodes.items[@backingInt(out_arg.*)].ty, try self.ty(parameter.ty), self.syntax.nodes.items[@backingInt(arg)].span);
                    }
                    out.ty = try self.ty(signature.return_type);
                    out.data = .{ .call = .{ .function = function, .arguments = arguments } };
                },
                .unary => |u| {
                    const operand = self.resolved[@backingInt(u.operand)].?;
                    out.ty = if (u.op == .neg) .i64 else .bool;
                    try self.require(self.nodes.items[@backingInt(operand)].ty, out.ty, u.op_span);
                    out.data = .{ .unary = .{ .op = if (u.op == .neg) .neg else .not, .operand = operand, .op_span = u.op_span } };
                },
                .binary => |b| {
                    const left = self.resolved[@backingInt(b.left)].?;
                    const right = self.resolved[@backingInt(b.right)].?;
                    const lt = self.nodes.items[@backingInt(left)].ty;
                    const rt = self.nodes.items[@backingInt(right)].ty;
                    try self.require(rt, lt, b.op_span);
                    switch (b.op) {
                        .logical_and, .logical_or => {
                            try self.require(lt, .bool, b.op_span);
                            out.ty = .bool;
                        },
                        .eq, .ne => {
                            if (lt != .i64 and lt != .bool) return self.sink.fail("E_TYPE", b.op_span, "record equality is not defined; compare the relevant fields explicitly");
                            out.ty = .bool;
                        },
                        .lt, .le, .gt, .ge => {
                            try self.require(lt, .i64, b.op_span);
                            out.ty = .bool;
                        },
                        else => try self.require(lt, .i64, b.op_span),
                    }
                    out.data = .{ .binary = .{
                        .op = std.meta.stringToEnum(typed.BinaryOp, @tagName(b.op)).?,
                        .left = left,
                        .right = right,
                        .op_span = b.op_span,
                    } };
                },
            }
            self.resolved[index] = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, out);
        }
        return self.resolved[@backingInt(root)].?;
    }
    fn statement(self: *Checker, id: ast.StatementId) Error!CheckedStatement {
        const stmt = self.syntax.statements.items[@backingInt(id)];
        var terminates = false;
        const data: @FieldType(typed.Statement, "data") = switch (stmt.data) {
            .block => |children| block: {
                const first_local = self.locals.items.len;
                defer for (self.locals.items[first_local..]) |local| {
                    _ = self.active.remove(local.name);
                };
                var checked: std.ArrayList(typed.StatementId) = .empty;
                for (children) |child| {
                    if (terminates) return self.sink.fail("E_UNREACHABLE", self.syntax.statements.items[@backingInt(child)].span, "statement follows a structurally terminating statement");
                    const result = try self.statement(child);
                    terminates = result.terminates;
                    try checked.append(self.allocator, result.id);
                }
                break :block .{ .block = try checked.toOwnedSlice(self.allocator) };
            },
            .discard => |expr| .{ .discard = try self.expression(expr) },
            .branch => |branch| branch: {
                const condition = try self.expression(branch.condition);
                try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(branch.condition)].span);
                const then_body = try self.statement(branch.then_body);
                const else_body = if (branch.else_body) |other| try self.statement(other) else null;
                terminates = then_body.terminates and if (else_body) |other| other.terminates else false;
                break :branch .{ .branch = .{ .condition = condition, .then_body = then_body.id, .else_body = if (else_body) |other| other.id else null } };
            },
            .loop => |loop| loop: {
                const condition = try self.expression(loop.condition);
                try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(loop.condition)].span);
                const body = try self.statement(loop.body);
                break :loop .{ .loop = .{ .condition = condition, .body = body.id } };
            },
            .ret => |expr| ret: {
                const value = try self.expression(expr);
                try self.require(self.nodes.items[@backingInt(value)].ty, self.return_type, stmt.span);
                terminates = true;
                break :ret .{ .ret = value };
            },
            .binding => |b| binding: {
                const name = self.src.text(b.name);
                if (self.functions.contains(name) or self.catalog.names.contains(name) or self.active.contains(name))
                    return self.sink.fail("E_SHADOWING", b.name, "binding shadows an active local or top-level function");
                const value = try self.expression(b.value);
                const value_type = self.nodes.items[@backingInt(value)].ty;
                if (b.annotation) |annotation| try self.require(value_type, try self.ty(annotation), annotation);
                const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
                try self.locals.append(self.allocator, .{ .name = name, .declaration = b.name, .ty = value_type, .mutable = b.mutable });
                try self.active.put(self.allocator, name, slot);
                break :binding .{ .initialize = .{ .slot = slot, .value = value } };
            },
            .assignment => |a| assignment: {
                const slot = try self.resolve(a.name);
                if (!self.locals.items[@backingInt(slot)].mutable)
                    return self.sink.fail("E_IMMUTABLE", a.name, "assignment requires a let mut binding");
                var value = try self.expression(a.value);
                if (a.op != .set) {
                    try self.require(self.locals.items[@backingInt(slot)].ty, .i64, a.op_span);
                    try self.require(self.nodes.items[@backingInt(value)].ty, .i64, a.op_span);
                    self.locals.items[@backingInt(slot)].reads += 1;
                    const read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
                    try self.nodes.append(self.allocator, .{ .ty = .i64, .span = a.name, .data = .{ .local = slot } });
                    const combined: typed.NodeId = @fromBackingInt(self.nodes.items.len);
                    try self.nodes.append(self.allocator, .{ .ty = .i64, .span = stmt.span, .data = .{ .binary = .{
                        .op = if (a.op == .add) .add else .sub,
                        .left = read,
                        .right = value,
                        .op_span = a.op_span,
                    } } });
                    value = combined;
                }
                try self.require(self.nodes.items[@backingInt(value)].ty, self.locals.items[@backingInt(slot)].ty, stmt.span);
                self.locals.items[@backingInt(slot)].writes += 1;
                break :assignment .{ .assign = .{ .slot = slot, .value = value } };
            },
        };
        const result: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = terminates, .data = data });
        return .{ .id = result, .terminates = terminates };
    }
};
fn warningLess(_: void, a: diagnostic.Diagnostic, b: diagnostic.Diagnostic) bool {
    if (a.span.start != b.span.start) return a.span.start < b.span.start;
    return std.mem.lessThan(u8, a.code, b.code);
}
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink) Error!typed.Program {
    const resolved = try allocator.alloc(?typed.NodeId, program.nodes.items.len);
    @memset(resolved, null);
    const catalog = try records.collect(allocator, src, program.records, sink);
    var checker: Checker = .{ .allocator = allocator, .src = src, .syntax = program, .sink = sink, .resolved = resolved, .catalog = catalog };
    for (program.functions, 0..) |function, i| {
        const name = src.text(function.name);
        if (catalog.names.contains(name)) return sink.fail("E_DUPLICATE_NAME", function.name, "function name conflicts with a record type");
        if (checker.functions.get(name)) |previous| return sink.failRelated("E_DUPLICATE_FUNCTION", function.name, "function name is already declared", .{ .span = program.functions[@backingInt(previous)].name, .message = "previous function declaration" });
        try checker.functions.put(allocator, name, @fromBackingInt(i));
    }
    const main = checker.functions.get("main") orelse return sink.fail("E_MAIN", .{ .start = 0, .end = 0 }, "the program requires fn main() -> i64");
    const entry = program.functions[@backingInt(main)];
    if (entry.parameters.len != 0) return sink.fail("E_MAIN", entry.name, "main must have no parameters");
    if (try checker.ty(entry.return_type) != .i64) return sink.fail("E_TYPE", entry.return_type, "main must return i64");
    const functions = try allocator.alloc(typed.Function, program.functions.len);
    for (program.functions, functions, 0..) |function, *out, i| {
        checker.locals = .empty;
        checker.active.clearRetainingCapacity();
        checker.return_type = try checker.ty(function.return_type);
        for (function.parameters) |parameter| {
            const name = src.text(parameter.name);
            if (checker.active.get(name)) |previous| return sink.failRelated("E_DUPLICATE_PARAMETER", parameter.name, "parameter name is already declared", .{ .span = checker.locals.items[@backingInt(previous)].declaration, .message = "previous parameter declaration" });
            if (checker.functions.contains(name) or checker.catalog.names.contains(name)) return sink.fail("E_SHADOWING", parameter.name, "parameter shadows a top-level function");
            const slot: typed.LocalId = @fromBackingInt(checker.locals.items.len);
            try checker.locals.append(allocator, .{ .name = name, .declaration = parameter.name, .ty = try checker.ty(parameter.ty), .mutable = false });
            try checker.active.put(allocator, name, slot);
        }
        checker.conversion_fields = null;
        if (function.conversion) {
            if (function.parameters.len != 1) return sink.fail("E_CONVERSION_SIGNATURE", function.name, "a complete conversion requires one source record parameter");
            const source_record = try catalog.record(checker.locals.items[0].ty, function.parameters[0].ty, sink);
            _ = try catalog.record(checker.return_type, function.return_type, sink);
            try conversionBody(src, program, function, sink);
            checker.conversion_fields = try allocator.alloc(bool, source_record.fields.len);
            @memset(checker.conversion_fields.?, false);
        }
        const body = try checker.statement(function.body);
        if (checker.conversion_fields) |seen| {
            const source_record = catalog.records[@backingInt(checker.locals.items[0].ty) - 2];
            for (seen, source_record.fields) |accounted, field| {
                if (!accounted) {
                    const message = try std.fmt.allocPrint(allocator, "source field `{s}` is not accounted for; use it in the destination or explicitly discard that named field", .{field.name});
                    return sink.failRelated("E_INCOMPLETE_CONVERSION", function.name, message, .{ .span = field.declaration, .message = "unaccounted source field declared here" });
                }
            }
        }
        if (!body.terminates) return sink.fail("E_MISSING_RETURN", function.name, "function may fall through without returning its declared type; loops are conservatively treated as falling through, even while true");
        out.* = .{ .conversion = function.conversion, .id = @fromBackingInt(i), .name = src.text(function.name), .declaration = function.name, .return_type = checker.return_type, .parameter_count = function.parameters.len, .body = body.id, .locals = try checker.locals.toOwnedSlice(allocator) };
    }
    for (functions) |function| {
        for (function.locals) |local| {
            if (local.reads == 0) try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNUSED_BINDING",
                .span = local.declaration,
                .message = "binding is never read; use it or remove it, preserving initializer effects with discard when needed",
            });
            if (local.mutable and local.writes == 0) try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNNECESSARY_MUT",
                .span = local.declaration,
                .message = "binding is never assigned after initialization; remove mut",
            });
        }
    }
    std.mem.sort(diagnostic.Diagnostic, sink.items.items, {}, warningLess);
    return .{ .nodes = try checker.nodes.toOwnedSlice(allocator), .statements = try checker.statements.toOwnedSlice(allocator), .functions = functions, .main = main, .records = catalog.records };
}

// This initial conversion form is declarative. Restricting its body avoids
// pretending arbitrary control/data flow proves source-field accounting.
fn conversionBody(src: source.Source, program: ast.Program, function: ast.Function, sink: *diagnostic.Sink) Error!void {
    const statements = program.statements.items[@backingInt(function.body)].data.block;
    for (statements) |id| {
        const stmt = program.statements.items[@backingInt(id)];
        switch (stmt.data) {
            .ret => |value| {
                if (program.nodes.items[@backingInt(value)].data != .record)
                    return sink.fail("E_CONVERSION_BODY", stmt.span, "conversion must return an explicit complete record construction");
            },
            .discard => |value| {
                const expression = program.nodes.items[@backingInt(value)];
                if (expression.data != .field) return sink.fail("E_CONVERSION_BODY", stmt.span, "conversion discard must name a direct source field");
                const base = program.nodes.items[@backingInt(expression.data.field.base)];
                if (base.data != .name or !std.mem.eql(u8, src.text(base.data.name), src.text(function.parameters[0].name)))
                    return sink.fail("E_CONVERSION_BODY", stmt.span, "conversion discard must name a direct source field");
            },
            else => return sink.fail("E_CONVERSION_BODY", stmt.span, "conversion bodies contain named source-field discards followed by a complete record construction; use helpers for transformations"),
        }
    }
}
